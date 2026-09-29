import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/execution_logger.dart';
import 'frame_parser.dart';
import 'robot_connection.dart';
import 'robot_protocol.dart';
import 'bluetooth_strategy.dart';
import 'serial_strategy.dart';
import 'wifi_strategy.dart';

enum ConnectionType {
  bluetooth,
  serial,
  wifi;

  String get displayName {
    switch (this) {
      case ConnectionType.bluetooth:
        return 'Bluetooth';
      case ConnectionType.serial:
        return 'USB Serial';
      case ConnectionType.wifi:
        return 'WiFi';
    }
  }
}

/// What the board told us about itself (from HELLO / STATUS text frames).
class BoardInfo {
  final String type; // esp32, uno, mega, unknown
  final String firmware;
  final String? ip;
  final String? name;
  const BoardInfo({this.type = 'unknown', this.firmware = '', this.ip, this.name});
  bool get supportsWifiSetup => type == 'esp32';
  BoardInfo copyWith({String? type, String? firmware, String? ip, String? name}) =>
      BoardInfo(type: type ?? this.type, firmware: firmware ?? this.firmware, ip: ip ?? this.ip, name: name ?? this.name);
}

/// Owns the active transport and exposes a single command/state/message
/// surface to the rest of the app. Remembers the last used transport and
/// WiFi address.
class ConnectivityManager {
  static final ConnectivityManager _instance = ConnectivityManager._internal();
  factory ConnectivityManager() => _instance;
  ConnectivityManager._internal();

  static const _prefType = 'connection_type';
  static const _prefWifiHost = 'connection_wifi_host';

  RobotConnection? _activeConnection;
  ConnectionType _activeType = ConnectionType.bluetooth;
  String _wifiHost = WifiStrategy.mdnsHost;
  StreamSubscription? _strategySub;
  StreamSubscription? _inboundSub;
  bool _prefsLoaded = false;
  BoardInfo _board = const BoardInfo();

  late final FrameParser _parser = FrameParser(onControl: _onControl, onText: _onText);

  final StreamController<RobotConnectionState> _stateController =
      StreamController<RobotConnectionState>.broadcast();
  final StreamController<TextFrame> _messageController =
      StreamController<TextFrame>.broadcast();

  Stream<RobotConnectionState> get stateStream => _stateController.stream;
  /// Text frames from the board (HELLO, WIFI status, OK/ERR replies, WATCHDOG).
  Stream<TextFrame> get messages => _messageController.stream;

  RobotConnectionState get state =>
      _activeConnection?.currentState ?? RobotConnectionState.disconnected;
  bool get isConnected => state == RobotConnectionState.connected;
  ConnectionType get activeType => _activeType;
  String get wifiHost => _wifiHost;
  BoardInfo get board => _board;

  RobotConnection get connection {
    if (_activeConnection == null) {
      _setStrategy(_activeType);
    }
    return _activeConnection!;
  }

  /// Restores the last used transport. Safe to call more than once.
  Future<void> loadPreferences() async {
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    final prefs = await SharedPreferences.getInstance();
    final typeName = prefs.getString(_prefType);
    _activeType = ConnectionType.values.firstWhere(
      (t) => t.name == typeName,
      orElse: () => ConnectionType.bluetooth,
    );
    _wifiHost = prefs.getString(_prefWifiHost) ?? _wifiHost;
  }

  Future<void> setWifiHost(String hostPort) async {
    _wifiHost = hostPort.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefWifiHost, _wifiHost);
  }

  Future<void> setType(ConnectionType type) async {
    if (_activeType == type && _activeConnection != null) return;

    final old = _activeConnection;
    _strategySub?.cancel();
    _strategySub = null;
    _inboundSub?.cancel();
    _inboundSub = null;
    if (old != null) {
      await old.dispose(); // dispose() disconnects first.
    }
    _setStrategy(type);
    _stateController.add(RobotConnectionState.disconnected);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefType, type.name);
  }

  void _setStrategy(ConnectionType type) {
    _activeType = type;
    switch (type) {
      case ConnectionType.bluetooth:
        _activeConnection = BluetoothStrategy();
        break;
      case ConnectionType.serial:
        _activeConnection = SerialStrategy();
        break;
      case ConnectionType.wifi:
        _activeConnection = WifiStrategy();
        break;
    }

    _strategySub?.cancel();
    _strategySub = _activeConnection!.stateStream.listen((s) {
      if (s != RobotConnectionState.connected) {
        _parser.reset();
        _board = const BoardInfo();
      }
      _stateController.add(s);
    });
    _inboundSub?.cancel();
    _inboundSub = _activeConnection!.inbound.listen(_parser.feed);
  }

  void _onControl(ControlFrame f) {
    // Reserved for sensor feedback packets from the board.
    debugPrint("Board → phone control frame: $f");
  }

  void _onText(TextFrame f) {
    final fields = f.fields;
    switch (f.command) {
      case 'HELLO':
        _board = BoardInfo(
          type: fields.length > 1 ? fields[1] : 'unknown',
          firmware: fields.length > 2 ? fields[2] : '',
          name: _board.name,
        );
        break;
      case 'WIFI':
        if (fields.length > 2 && fields[1] == 'CONNECTED') {
          _board = _board.copyWith(ip: fields[2]);
        }
        break;
      case 'STATUS':
        for (final kv in fields.skip(1)) {
          final i = kv.indexOf('=');
          if (i < 0) continue;
          final k = kv.substring(0, i), v = kv.substring(i + 1);
          if (k == 'ip' && v != '0.0.0.0') _board = _board.copyWith(ip: v);
          if (k == 'name') _board = _board.copyWith(name: v);
        }
        break;
    }
    debugPrint("Board → phone: ${f.text.replaceAll('\t', ' | ')}");
    final line = logLineFor(f);
    if (line != null) ExecutionLogger().log(line);
    _messageController.add(f);
  }

  /// The line the execution log shows for a board message, or null if it
  /// isn't worth showing there. The firmware sends at most one ERR a second.
  static String? logLineFor(TextFrame f) {
    final detail = f.fields.skip(1).join(' ');
    switch (f.command) {
      case 'ERR':
        // Uno/Mega answer every text command this way; not a program problem.
        if (detail == 'unsupported') return null;
        if (detail.startsWith('bad pin ')) {
          return "Robot: pin ${detail.substring(8)} can't be used on this board";
        }
        return 'Robot: $detail';
      case 'WATCHDOG':
        return 'Robot stopped its outputs: no signal from the phone for 2 s';
    }
    return null;
  }

  Future<void> connect() async {
    await loadPreferences();
    final id = _activeType == ConnectionType.wifi ? _wifiHost : null;
    await connection.connect(deviceId: id);
  }

  Future<void> disconnect() => connection.disconnect();

  Future<void> sendCommand(int cmd, int pin, int value) =>
      connection.sendCommand(cmd, pin, value);

  /// Sends a text command to the board (tab-separated fields).
  Future<void> sendText(String text) => connection.sendBytes(FrameParser.encodeText(text));

  /// Sends a text command and waits for the first reply whose command is one
  /// of [expect]. Returns null on timeout.
  Future<TextFrame?> request(String text, {List<String> expect = const ['OK', 'ERR'],
      Duration timeout = const Duration(seconds: 3)}) async {
    final completer = Completer<TextFrame?>();
    final sub = messages.listen((f) {
      if (expect.contains(f.command) && !completer.isCompleted) completer.complete(f);
    });
    try {
      await sendText(text);
      return await completer.future.timeout(timeout, onTimeout: () => null);
    } finally {
      sub.cancel();
    }
  }

  /// Firmware-side emergency stop: every touched pin LOW / PWM 0 / servo stop.
  Future<void> stopAll() =>
      connection.sendCommand(RobotProtocol.cmdStopAll, 0, 0);
}
