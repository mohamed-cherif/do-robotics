import 'package:do_robotics/services/sensor_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Device frame (Android/iOS): +X right edge, +Y top edge, +Z out of the
/// screen. The accelerometer at rest reads +9.8 along "up". The Earth's field
/// in the northern hemisphere points north and down (here 20 µT north,
/// 40 µT down).
void main() {
  group('tilt-compensated heading', () {
    test('flat phone, top edge north → 0°', () {
      // x = east, y = north, z = up
      expect(SensorMath.facingHeadingDeg(0, 0, 9.8, 0, 20, -40), closeTo(0, 0.5));
    });

    test('flat phone, top edge east → 90° (same as the old flat-only formula)', () {
      // y = east, z = up, x = south
      final h = SensorMath.facingHeadingDeg(0, 0, 9.8, -20, 0, -40);
      expect(h, closeTo(90, 0.5));
      expect(SensorMath.headingDeg(-20, 0), closeTo(h, 0.5));
    });

    test('upright phone on a robot, camera facing north → 0°', () {
      // y = up, camera (-z) = north so z = south, x = east
      expect(SensorMath.facingHeadingDeg(0, 9.8, 0, 0, -40, -20), closeTo(0, 0.5));
      // The old formula assumed a flat phone and read this as south.
      expect(SensorMath.headingDeg(0, -40), closeTo(180, 0.5));
    });

    test('upright phone, camera facing east → 90°', () {
      // y = up, -z = east so z = west, x = south
      expect(SensorMath.facingHeadingDeg(0, 9.8, 0, -20, -40, 0), closeTo(90, 0.5));
    });

    test('upright phone, camera facing west → 270°', () {
      // y = up, -z = west so z = east, x = north
      expect(SensorMath.facingHeadingDeg(0, 9.8, 0, 20, -40, 0), closeTo(270, 0.5));
    });

    test('robust to a moderate tilt (robot on a slope)', () {
      // Flat phone pointing north, pitched 15° nose-up.
      const s = 0.258819, c = 0.965926; // sin/cos 15°
      // Rotate gravity and field about +X by +15°.
      final ay = 9.8 * s, az = 9.8 * c;
      final my = 20 * c - 40 * s, mz = -20 * s - 40 * c;
      expect(SensorMath.facingHeadingDeg(0, ay, az, 0, my, mz), closeTo(0, 1.0));
    });
  });

  group('yaw rate about the vertical axis', () {
    test('flat phone: yaw is the gyro Z rate', () {
      expect(SensorMath.yawRateRadS(0, 0, 1.2, 0, 0, 9.8), closeTo(1.2, 1e-9));
    });

    test('upright phone: turning the robot shows up on gyro Y, not Z', () {
      // Before, "Rotation Rate" read gyro Z, which is ~0 when an upright phone
      // turns with the robot.
      expect(SensorMath.yawRateRadS(0, 1.2, 0, 0, 9.8, 0), closeTo(1.2, 1e-9));
      expect(SensorMath.yawRateRadS(0, 0, 1.2, 0, 9.8, 0), closeTo(0, 1e-9));
    });
  });
}
