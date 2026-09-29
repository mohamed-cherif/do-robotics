import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'robot_connection.dart';
import 'robot_protocol.dart';

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
  int _reconnectAttempts = 0;

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

  @override
  Stream<RobotConnectionState> get stateStream => _stateController.stream;
  @override
  RobotConnectionState get currentState => _currentState;
  @override
  Stream<Uint8List> get inbound => _inboundController.stream;

  void _updateState(RobotConnectionState state) {
    if (_currentState != state) {
      _currentState = state;
      _stateController.add(state);
    }
  }

  @override
  Future<void> connect({String? deviceId}) async {
    if (_currentState != RobotConnectionState.disconnected) return;
    _userDisconnected = false;
    _reconnectAttempts = 0;

    if (await FlutterBluePlus.isSupported == false) {
      debugPrint("BLE: Bluetooth not supported on this device");
      return;
    }

    _updateState(RobotConnectionState.connecting);

    // Fast path: reconnect to the device we used last time.
    final last = _lastDevice;
    if (last != null && deviceId == null) {
      if (await _connectToDevice(last)) return;
      if (_userDisconnected) return;
    }
    await _scanAndConnect(deviceId);
  }

  Future<void> _scanAndConnect(String? deviceId) async {
    try {
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }

      await _scanSub?.cancel();
      _scanSub = FlutterBluePlus.scanResults.listen((results) async {
        for (final r in results) {
          final name = r.device.platformName.isNotEmpty
              ? r.device.platformName
              : r.advertisementData.advName;
          final matches = deviceId != null
              ? (r.device.remoteId.str == deviceId || name == deviceId)
              : _targetNames.any(name.contains);
          if (matches) {
            await _scanSub?.cancel();
            _scanSub = null;
            _scanTimeout?.cancel();
            await FlutterBluePlus.stopScan();
            await _connectToDevice(r.device);
            break;
          }
        }
      });

      await FlutterBluePlus.startScan(timeout: _scanDuration);

      _scanTimeout?.cancel();
      _scanTimeout = Timer(_scanDuration + const Duration(seconds: 1), () {
        if (_currentState == RobotConnectionState.connecting && _connectedDevice == null) {
          _scanSub?.cancel();
          _scanSub = null;
          debugPrint("BLE: no robot found (looking for names containing $_targetNames)");
          _updateState(RobotConnectionState.disconnected);
        }
      });
    } catch (e) {
      debugPrint("BLE Scan Error: $e");
      _updateState(RobotConnectionState.disconnected);
    }
  }

  Future<bool> _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect(timeout: const Duration(seconds: 15));
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
        await device.disconnect();
        _updateState(RobotConnectionState.disconnected);
        return false;
      }

      final rx = _rxCharacteristic;
      if (rx != null && rx.properties.notify) {
        try {
          await rx.setNotifyValue(true);
          _notifySub?.cancel();
          _notifySub = rx.onValueReceived.listen((bytes) {
            _inboundController.add(Uint8List.fromList(bytes));
          });
        } catch (e) {
          debugPrint("BLE: could not subscribe to notifications: $e");
        }
      }

      debugPrint("BLE: connected to ${device.platformName}");
      _reconnectAttempts = 0;
      _updateState(RobotConnectionState.connected);
      _startHeartbeat();
      return true;
    } catch (e) {
      debugPrint("BLE Connection Error: $e");
      _connectedDevice = null;
      _txCharacteristic = null;
      _rxCharacteristic = null;
      _updateState(RobotConnectionState.disconnected);
      return false;
    }
  }

  /// Unexpected link loss: try to get back to the same device a few times.
  void _onDropped() {
    _stopHeartbeat();
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
    Future.delayed(const Duration(seconds: 2), () async {
      if (_userDisconnected) {
        _updateState(RobotConnectionState.disconnected);
        return;
      }
      final ok = await _connectToDevice(_lastDevice!);
      if (!ok && !_userDisconnected) _onDropped();
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
    _scanTimeout?.cancel();
    await _scanSub?.cancel();
    _scanSub = null;
    if (FlutterBluePlus.isScanningNow) {
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
    _stateController.close();
    _inboundController.close();
  }
}
