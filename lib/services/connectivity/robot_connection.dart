import 'dart:async';
import 'dart:typed_data';

enum RobotConnectionState {
  disconnected,
  connecting,
  connected,
}

abstract class RobotConnection {
  Stream<RobotConnectionState> get stateStream;
  RobotConnectionState get currentState;

  /// Raw bytes coming back from the board (text frames, future sensor data).
  Stream<Uint8List> get inbound;

  Future<void> connect({String? deviceId});
  Future<void> disconnect();

  /// Sends a 5-byte control packet.
  Future<void> sendCommand(int cmd, int pin, int value);

  /// Sends pre-encoded bytes (e.g. a text frame).
  Future<void> sendBytes(List<int> bytes);

  Future<void> dispose();
}
