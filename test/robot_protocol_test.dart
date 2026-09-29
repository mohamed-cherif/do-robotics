import 'package:flutter_test/flutter_test.dart';
import 'package:do_robotics/services/connectivity/robot_protocol.dart';

void main() {
  group('RobotProtocol', () {
    test('builds a 5-byte packet with a valid checksum', () {
      final p = RobotProtocol.buildPacket(RobotProtocol.cmdAnalogWrite, 9, 200);
      expect(p, hasLength(5));
      expect(p[0], 0xAA);
      expect(p[1], 0x02);
      expect(p[2], 9);
      expect(p[3], 200);
      expect(p[4], (0xAA + 0x02 + 9 + 200) % 256);
      expect(RobotProtocol.isValidPacket(p), isTrue);
    });

    test('clamps every field to a single byte', () {
      final p = RobotProtocol.buildPacket(RobotProtocol.cmdServoWrite, 300, 3000);
      expect(p[2], 255);
      expect(p[3], 255);
      expect(RobotProtocol.isValidPacket(p), isTrue);

      final n = RobotProtocol.buildPacket(RobotProtocol.cmdDigitalWrite, -5, -1);
      expect(n[2], 0);
      expect(n[3], 0);
    });

    test('heartbeat and stop-all packets match the firmware command table', () {
      expect(RobotProtocol.heartbeatPacket[1], 0x00);
      expect(RobotProtocol.stopAllPacket[1], 0x06);
      expect(RobotProtocol.isValidPacket(RobotProtocol.heartbeatPacket), isTrue);
      expect(RobotProtocol.isValidPacket(RobotProtocol.stopAllPacket), isTrue);
    });

    test('rejects corrupted packets', () {
      final p = RobotProtocol.buildPacket(1, 2, 3);
      expect(RobotProtocol.isValidPacket([...p]..[3] = 4), isFalse);
      expect(RobotProtocol.isValidPacket([...p]..[0] = 0xAB), isFalse);
      expect(RobotProtocol.isValidPacket(p.sublist(0, 4)), isFalse);
    });

    test('continuous servo µs encoding round-trips', () {
      expect(RobotProtocol.usToServoValue(1300), 0);
      expect(RobotProtocol.usToServoValue(1500), 100);
      expect(RobotProtocol.usToServoValue(1700), 200);
      expect(RobotProtocol.usToServoValue(2500), 200); // clamped
      expect(RobotProtocol.servoValueToUs(100), 1500);
    });
  });
}
