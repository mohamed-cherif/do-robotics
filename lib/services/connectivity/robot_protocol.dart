import 'dart:typed_data';

/// Wire protocol shared by every transport (BLE, USB serial, WiFi TCP) and by
/// every firmware target (ESP32, Uno, Mega).
///
/// Packet layout (5 bytes):
///   [HEADER][CMD][PIN][VALUE][CHECKSUM]
///   CHECKSUM = (HEADER + CMD + PIN + VALUE) % 256
///
/// All fields are single bytes, so callers must keep values in 0..255. The
/// builder clamps defensively so a bad block value can never corrupt the
/// stream or desync the firmware state machine.
class RobotProtocol {
  RobotProtocol._();

  static const int header = 0xAA;

  // ── Commands ──────────────────────────────────────────────────────────────
  /// No-op. Sent periodically so the firmware watchdog knows the link is alive.
  static const int cmdHeartbeat = 0x00;
  /// value: 0 = LOW, 1 = HIGH
  static const int cmdDigitalWrite = 0x01;
  /// value: 0..255 PWM duty
  static const int cmdAnalogWrite = 0x02;
  /// value: 0 = INPUT, 1 = OUTPUT, 2 = INPUT_PULLUP
  static const int cmdPinMode = 0x03;
  /// Positional servo, value = angle 0..180
  static const int cmdServoWrite = 0x04;
  /// Continuous servo, value = (µs - 1300) / 2  → 0 = 1300µs, 100 = 1500µs (stop), 200 = 1700µs
  static const int cmdServoWriteUs = 0x05;
  /// Emergency stop: firmware drives every touched pin LOW / PWM 0 / servo stop.
  /// pin and value are ignored.
  static const int cmdStopAll = 0x06;

  /// Interval at which transports send [cmdHeartbeat]. The firmware watchdog
  /// timeout is 2 s, so this leaves three missed beats before a failsafe stop.
  static const Duration heartbeatInterval = Duration(milliseconds: 500);

  /// Pulse-width helpers for continuous-rotation servos.
  static int usToServoValue(int microseconds) =>
      ((microseconds - 1300) / 2).round().clamp(0, 200);
  static int servoValueToUs(int value) => 1300 + value * 2;

  static int checksum(int cmd, int pin, int value) =>
      (header + cmd + pin + value) & 0xFF;

  /// Builds a packet, clamping every field to a single byte.
  static Uint8List buildPacket(int cmd, int pin, int value) {
    final c = cmd.clamp(0, 255);
    final p = pin.clamp(0, 255);
    final v = value.clamp(0, 255);
    return Uint8List.fromList([header, c, p, v, checksum(c, p, v)]);
  }

  static Uint8List get heartbeatPacket => buildPacket(cmdHeartbeat, 0, 0);
  static Uint8List get stopAllPacket => buildPacket(cmdStopAll, 0, 0);

  /// Validates a received 5-byte packet (used by tests and by any future
  /// phone-side receiver for sensor data coming back from the board).
  static bool isValidPacket(List<int> bytes) {
    if (bytes.length != 5) return false;
    if (bytes[0] != header) return false;
    return bytes[4] == checksum(bytes[1], bytes[2], bytes[3]);
  }
}
