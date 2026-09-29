import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'robot_connection.dart';
import 'robot_protocol.dart';

/// A robot seen in a Bluetooth scan.
class FoundRobot {
  /// Platform device id (the MAC address on Android); what connect() takes.
  final String id;
  final String name;
  /// Signal strength in dBm (about -40 right next to the phone, -90 far away).
  final int rssi;
  const FoundRobot({required this.id, required this.name, required this.rssi});
}

class BluetoothStrategy implements RobotConnection {
  BluetoothDevice? _connectedDevice;
  BluetoothDevice? _lastDevice;
  BluetoothCharacteristic? _txCharacteristic; // phone → board (NUS RX on the board)
  BluetoothCharacteristic? _rxCharacteristic; // board → phone (NUS TX on the board)
  StreamSubscription? _connectionStateSub;
  StreamSubscription? _notifySub;
  StreamSubscription? _scanSub;
  Timer? _scanTimeout;
  Timer? _heartbeatTimer;
  bool _userDisconnected = false;
  bool _disposed = false;
  bool _reconnectPending = false;
  int _reconnectAttempts = 0;
  /// Bumped by disconnect(): attempts started before it must not complete,
  /// even if connect() was called again meanwhile.
  int _attempt = 0;
  Future<bool>? _pendingConnect;

  final StreamController<RobotConnectionState> _stateController =
      StreamController<RobotConnectionState>.broadcast();
  final StreamController<Uint8List> _inboundController =
      StreamController<Uint8List>.broadcast();
  RobotConnectionState _currentState = RobotConnectionState.disconnected;

  // Configuration
  /// Any advertised name containing one of these is treated as our robot.
  static const List<String> _targetNames = ["ESP32", "robot", "Robot"];
  /// Nordic UART Service characteristics. Matches receiver.ino.
  static final Guid _nusRxUuid = Guid("6E400002-B5A3-F393-E0A9-E50E24DCCA9E");
  static final Guid _nusTxUuid = Guid("6E400003-B5A3-F393-E0A9-E50E24DCCA9E");
  static const Duration _scanDuration = Duration(seconds: 10);
  static const int _maxReconnectAttempts = 5;

  /// FlutterBluePlus has one scan for the whole app, and a new scan silently
  /// replaces the running one. Every scan takes a number from here; code
  /// only stops the scan if it is still the one it started.
  static int _scanGeneration = 0;
  int _myScan = -1;

  /// True for advertised names that look like one of our robots.
  static bool isRobotName(String name) => _targetNames.any(name.contains);

  static String _nameOf(ScanResult r) => r.device.platformName.isNotEmpty
      ? r.device.platformName
      : r.advertisementData.advName;

  /// Scans for [duration] and reports the robots seen so far (each event is
  /// the full list). The stream closes when the scan ends; cancelling the
  /// subscription stops the scan. Only lists — never connects. Don't run it
  /// while a connect() attempt is scanning: they would share the one scan.
  static Stream<List<FoundRobot>> scanForRobots({Duration duration = _scanDuration}) {
    StreamSubscription<List<ScanResult>>? resultsSub;
    StreamSubscription<bool>? scanningSub;
    int myScan = -1;
    bool finished = false;
    late final StreamController<List<FoundRobot>> out;

    Future<void> finish() async {
      if (finished) return;
      finished = true;
      // Decide before awaiting anything, while nobody else can have started
      // a scan that we would stop by mistake.
      final stopOurScan = myScan == _scanGeneration && FlutterBluePlus.isScanningNow;
      final r = resultsSub, s = scanningSub;
      resultsSub = null;
      scanningSub = null;
      await r?.cancel();
      await s?.cancel();
      if (stopOurScan) {
        try {
          await FlutterBluePlus.stopScan();
        } catch (_) {}
      }
      // Not awaited: after a cancel there may be no listener to take "done".
      if (!out.isClosed) out.close();
    }

    out = StreamController<List<FoundRobot>>(
      onListen: () async {
        try {
          if (await FlutterBluePlus.isSupported == false) {
            throw StateError('Bluetooth is not supported on this device');
          }
          myScan = ++_scanGeneration;
          await FlutterBluePlus.startScan(timeout: duration);
          if (finished) {
            // Cancelled while the scan was starting.
            if (myScan == _scanGeneration && FlutterBluePlus.isScanningNow) {
              await FlutterBluePlus.stopScan();
            }
            return;
          }
          resultsSub = FlutterBluePlus.scanResults.listen((results) {
            if (out.isClosed) return;
            out.add([
              for (final r in results)
                if (isRobotName(_nameOf(r)))
                  FoundRobot(id: r.device.remoteId.str, name: _nameOf(r), rssi: r.rssi),
            ]);
          }, onError: (Object e) {
            if (!out.isClosed) out.addError(e);
          });
          // isScanning re-emits its current value, so a scan that already
          // ended (or was replaced) finishes us straight away.
          scanningSub = FlutterBluePlus.isScanning.listen((scanning) {
            if (!scanning) finish();
          });
        } catch (e) {
          if (!out.isClosed) out.addError(e);
          await finish();
        }
      },
      onCancel: finish,
    );
    return out.stream;
  }

  @override
  Stream<RobotConnectionState> get stateStream => _stateController.stream;
  @override
  RobotConnectionState get currentState => _currentState;
  @override
  Stream<Uint8List> get inbound => _inboundController.stream;

  void _updateState(RobotConnectionState state) {
    if (_disposed) return;
    if (_currentState != state) {
      _currentState = state;
      _stateController.add(state);
    }
  }

  @override
  Future<void> connect({String? deviceId}) async {
    if (_currentState != RobotConnectionState.disconnected || _disposed) return;
    final attempt = _attempt;
    _userDisconnected = false;
    _reconnectAttempts = 0;

    if (await FlutterBluePlus.isSupported == false) {
      debugPrint("BLE: Bluetooth not supported on this device");
      return;
    }

    _updateState(RobotConnectionState.connecting);

    // A connect started before the last disconnect() may still be running
    // (the phone makes one connection at a time). Let it finish and clean up
    // first, so it can't disconnect or overwrite this one.
    final pending = _pendingConnect;
    if (pending != null) await pending;
    if (attempt != _attempt || _disposed) return;

    // Fast path: reconnect to the device we used last time (if it is the one
    // asked for).
    final last = _lastDevice;
    if (last != null && (deviceId == null || last.remoteId.str == deviceId)) {
      if (await _connectToDevice(last, attempt)) return;
      if (attempt != _attempt || _disposed) return;
    }
    await _scanAndConnect(deviceId, attempt);
  }

  /// Scans until a robot matching [deviceId] (any robot if null) shows up,
  /// then connects. Gives up quietly once [attempt] is out of date.
  Future<void> _scanAndConnect(String? deviceId, int attempt) async {
    bool stale() => attempt != _attempt || _disposed;
    try {
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }

      await _scanSub?.cancel();
      if (stale()) return;
      _myScan = ++_scanGeneration;
      _scanSub = FlutterBluePlus.scanResults.listen((results) async {
        if (stale()) return;
        for (final r in results) {
          final name = _nameOf(r);
          final matches = deviceId != null
              ? (r.device.remoteId.str == deviceId || name == deviceId)
              : isRobotName(name);
          if (matches) {
            await _scanSub?.cancel();
            _scanSub = null;
            _scanTimeout?.cancel();
            await FlutterBluePlus.stopScan();
            if (!stale()) await _connectToDevice(r.device, attempt);
            break;
          }
        }
      });

      await FlutterBluePlus.startScan(timeout: _scanDuration);
      if (stale()) return;

      _scanTimeout?.cancel();
      _scanTimeout = Timer(_scanDuration + const Duration(seconds: 1), () {
        if (stale()) return;
        // _scanSub is null once a robot matched (possibly from results that
        // were already there before this timer was set): connecting, not lost.
        if (_scanSub != null &&
            _currentState == RobotConnectionState.connecting &&
            _connectedDevice == null) {
          _scanSub?.cancel();
          _scanSub = null;
          debugPrint("BLE: no robot found (looking for names containing $_targetNames)");
          _updateState(RobotConnectionState.disconnected);
        }
      });
    } catch (e) {
      debugPrint("BLE Scan Error: $e");
      if (!stale()) _updateState(RobotConnectionState.disconnected);
    }
  }

  Future<bool> _connectToDevice(BluetoothDevice device, int attempt) =>
      _pendingConnect = _connectToDeviceOnce(device, attempt);

  /// One connection attempt, on behalf of [attempt]. Once disconnect() has
  /// run, the attempt is stale: it only cleans up its own device and leaves
  /// the shared state to whatever connect() comes next.
  Future<bool> _connectToDeviceOnce(BluetoothDevice device, int attempt) async {
    bool stale() => _userDisconnected || _disposed || attempt != _attempt;
    try {
      await device.connect(timeout: const Duration(seconds: 15));
      if (stale()) {
        // disconnect()/dispose() ran while we were connecting.
        try {
          await device.disconnect();
        } catch (_) {}
        return false;
      }
      _connectedDevice = device;
      _lastDevice = device;

      _connectionStateSub?.cancel();
      _connectionStateSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _onDropped();
        }
      });

      // Bigger MTU so text frames (up to 123 bytes) arrive in one notification.
      try {
        await device.requestMtu(185);
      } catch (_) {}

      final services = await device.discoverServices();
      BluetoothCharacteristic? fallback;
      _txCharacteristic = null;
      _rxCharacteristic = null;
      for (final s in services) {
        for (final c in s.characteristics) {
          if (c.uuid == _nusRxUuid) _txCharacteristic = c;
          if (c.uuid == _nusTxUuid) _rxCharacteristic = c;
          if (fallback == null && (c.properties.write || c.properties.writeWithoutResponse)) {
            fallback = c;
          }
        }
      }
      _txCharacteristic ??= fallback;

      if (_txCharacteristic == null) {
        debugPrint("BLE: no writable characteristic found — disconnecting");
        // Not a drop: don't let the listener start a reconnect loop.
        _connectionStateSub?.cancel();
        _connectionStateSub = null;
        _connectedDevice = null;
        await device.disconnect();
        if (!stale()) _updateState(RobotConnectionState.disconnected);
        return false;
      }

      final rx = _rxCharacteristic;
      if (rx != null && rx.properties.notify) {
        try {
          await rx.setNotifyValue(true);
          _notifySub?.cancel();
          _notifySub = rx.onValueReceived.listen((bytes) {
            if (!_disposed) _inboundController.add(Uint8List.fromList(bytes));
          });
        } catch (e) {
          debugPrint("BLE: could not subscribe to notifications: $e");
        }
      }

      if (stale()) {
        // Set up after disconnect() ran; no newer attempt has started yet
        // (connect() waits for this one), so these are ours to undo.
        _notifySub?.cancel();
        _notifySub = null;
        try {
          await device.disconnect();
        } catch (_) {}
        return false;
      }

      debugPrint("BLE: connected to ${device.platformName}");
      _reconnectAttempts = 0;
      _updateState(RobotConnectionState.connected);
      _startHeartbeat();
      return true;
    } catch (e) {
      debugPrint("BLE Connection Error: $e");
      if (attempt != _attempt) {
        try {
          await device.disconnect();
        } catch (_) {}
        return false;
      }
      _connectedDevice = null;
      _txCharacteristic = null;
      _rxCharacteristic = null;
      // A failure after connect() succeeded (e.g. service discovery) would
      // otherwise leave the link up but unusable. Detach the drop listener
      // first so this deliberate disconnect doesn't start a reconnect loop.
      _connectionStateSub?.cancel();
      _connectionStateSub = null;
      try {
        await device.disconnect();
      } catch (_) {}
      _updateState(RobotConnectionState.disconnected);
      return false;
    }
  }

  /// Unexpected link loss: try to get back to the same device a few times.
  void _onDropped() {
    // One reconnect loop at a time: the connection-state listener and a
    // failed attempt can both report the same drop.
    if (_reconnectPending) return;
    _stopHeartbeat();
    _connectionStateSub?.cancel();
    _connectionStateSub = null;
    _notifySub?.cancel();
    _notifySub = null;
    _connectedDevice = null;
    _txCharacteristic = null;
    _rxCharacteristic = null;
    if (_userDisconnected || _lastDevice == null) {
      _updateState(RobotConnectionState.disconnected);
      return;
    }
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint("BLE: giving up after $_reconnectAttempts reconnect attempts");
      _updateState(RobotConnectionState.disconnected);
      return;
    }
    _reconnectAttempts++;
    _updateState(RobotConnectionState.connecting);
    debugPrint("BLE: link lost, reconnect attempt $_reconnectAttempts");
    _reconnectPending = true;
    final attempt = _attempt;
    Future.delayed(const Duration(seconds: 2), () async {
      // disconnect() ran meanwhile: it set the state, and a newer connect()
      // may own it now.
      if (attempt != _attempt) return;
      if (_userDisconnected || _disposed) {
        _reconnectPending = false;
        _updateState(RobotConnectionState.disconnected);
        return;
      }
      final ok = await _connectToDevice(_lastDevice!, attempt);
      if (attempt != _attempt) return;
      _reconnectPending = false;
      if (!ok && !_userDisconnected && !_disposed) _onDropped();
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(RobotProtocol.heartbeatInterval, (_) {
      _write(RobotProtocol.heartbeatPacket);
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<void> _write(List<int> packet) async {
    final c = _txCharacteristic;
    if (c == null || _currentState != RobotConnectionState.connected) return;
    try {
      await c.write(packet, withoutResponse: c.properties.writeWithoutResponse);
    } catch (e) {
      debugPrint("BLE Write Error: $e");
    }
  }

  @override
  Future<void> disconnect() async {
    _userDisconnected = true;
    _attempt++;
    _reconnectPending = false; // a pending reconnect gives up (attempt changed)
    _scanTimeout?.cancel();
    await _scanSub?.cancel();
    _scanSub = null;
    // Only our own scan: the robot list may be scanning right now.
    if (_myScan == _scanGeneration && FlutterBluePlus.isScanningNow) {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    }
    _stopHeartbeat();
    _notifySub?.cancel();
    _notifySub = null;
    _connectionStateSub?.cancel();
    _connectionStateSub = null;
    final device = _connectedDevice;
    _connectedDevice = null;
    _txCharacteristic = null;
    _rxCharacteristic = null;
    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {}
    }
    _updateState(RobotConnectionState.disconnected);
  }

  @override
  Future<void> sendCommand(int cmd, int pin, int value) =>
      _write(RobotProtocol.buildPacket(cmd, pin, value));

  @override
  Future<void> sendBytes(List<int> bytes) => _write(bytes);

  @override
  Future<void> dispose() async {
    await disconnect();
    _disposed = true;
    _stateController.close();
    _inboundController.close();
  }
}
