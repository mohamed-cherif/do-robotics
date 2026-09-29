import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:usb_serial/usb_serial.dart';
import 'robot_connection.dart';
import 'robot_protocol.dart';

class SerialStrategy implements RobotConnection {
  UsbPort? _port;
  final StreamController<RobotConnectionState> _stateController =
      StreamController<RobotConnectionState>.broadcast();
  final StreamController<Uint8List> _inboundController =
      StreamController<Uint8List>.broadcast();
  RobotConnectionState _currentState = RobotConnectionState.disconnected;
  Timer? _heartbeatTimer;
  StreamSubscription? _usbEventSub;
  StreamSubscription? _inputSub;

  static const int _baudRate = 115200;

  @override
  Stream<RobotConnectionState> get stateStream => _stateController.stream;
  @override
  RobotConnectionState get currentState => _currentState;
  @override
  Stream<Uint8List> get inbound => _inboundController.stream;

  void _updateState(RobotConnectionState state) {
    if (_currentState == state) return;
    _currentState = state;
    _stateController.add(state);
  }

  @override
  Future<void> connect({String? deviceId}) async {
    if (_currentState != RobotConnectionState.disconnected) return;
    _updateState(RobotConnectionState.connecting);

    final devices = await UsbSerial.listDevices();
    if (devices.isEmpty) {
      debugPrint("USB: no serial devices found");
      _updateState(RobotConnectionState.disconnected);
      return;
    }

    final device = devices.firstWhere(
      (d) => deviceId != null && (d.deviceName == deviceId || '${d.deviceId}' == deviceId),
      orElse: () => devices.first,
    );
    debugPrint("USB: connecting to ${device.deviceName} (VID:${device.vid} PID:${device.pid})");

    try {
      final port = await device.create();
      if (port == null || !(await port.open())) {
        debugPrint("USB: failed to open port");
        _updateState(RobotConnectionState.disconnected);
        return;
      }
      _port = port;

      await port.setDTR(true);
      await port.setRTS(true);
      await port.setPortParameters(
        _baudRate,
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );

      // Toggling DTR resets AVR boards; give the bootloader time to hand over
      // to the sketch before we start streaming packets at it.
      await Future.delayed(const Duration(milliseconds: 1800));

      _updateState(RobotConnectionState.connected);
      _startHeartbeat();
      _startUsbEventWatch();

      _inputSub?.cancel();
      _inputSub = port.inputStream?.listen(
        (data) => _inboundController.add(data),
        onError: (_) => _handleDisconnect(),
        onDone: () => _handleDisconnect(),
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint("USB Connection Error: $e");
      _port = null;
      _updateState(RobotConnectionState.disconnected);
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(RobotProtocol.heartbeatInterval, (_) async {
      final port = _port;
      if (port == null) return;
      try {
        await port.write(RobotProtocol.heartbeatPacket);
      } catch (_) {
        _handleDisconnect();
      }
    });
  }

  void _startUsbEventWatch() {
    _usbEventSub?.cancel();
    _usbEventSub = UsbSerial.usbEventStream?.listen((UsbEvent event) {
      if (event.event == UsbEvent.ACTION_USB_DETACHED) {
        _handleDisconnect();
      }
    });
  }

  void _handleDisconnect() {
    if (_currentState == RobotConnectionState.disconnected) return;
    _cleanup();
    _updateState(RobotConnectionState.disconnected);
  }

  void _cleanup() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _usbEventSub?.cancel();
    _usbEventSub = null;
    _inputSub?.cancel();
    _inputSub = null;
    _port = null;
  }

  @override
  Future<void> disconnect() async {
    final port = _port;
    _cleanup();
    if (port != null) {
      try {
        await port.close();
      } catch (_) {}
    }
    _updateState(RobotConnectionState.disconnected);
  }

  @override
  Future<void> sendCommand(int cmd, int pin, int value) =>
      sendBytes(RobotProtocol.buildPacket(cmd, pin, value));

  @override
  Future<void> sendBytes(List<int> bytes) async {
    final port = _port;
    if (port == null || _currentState != RobotConnectionState.connected) return;
    try {
      await port.write(Uint8List.fromList(bytes));
    } catch (_) {
      _handleDisconnect();
    }
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    _stateController.close();
    _inboundController.close();
  }
}
