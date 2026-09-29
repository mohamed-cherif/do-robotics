import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:do_robotics/services/sensor_service.dart';
import 'package:do_robotics/services/vision_service.dart';

void main() {
  group('SensorMath', () {
    test('flat phone has zero pitch and roll', () {
      expect(SensorMath.pitchDeg(0, 0, 9.8), closeTo(0, 1e-6));
      expect(SensorMath.rollDeg(0, 0, 9.8), closeTo(0, 1e-6));
    });

    test('45° tilt with the top edge raised reads +45° pitch', () {
      final g = 9.8 / 1.4142135;
      expect(SensorMath.pitchDeg(0, g, g), closeTo(45, 1e-3));
    });

    test('heading is 0 pointing north and 90 pointing east', () {
      expect(SensorMath.headingDeg(0, 1), closeTo(0, 1e-6));
      expect(SensorMath.headingDeg(-1, 0), closeTo(90, 1e-6));
      expect(SensorMath.headingDeg(0, -1), closeTo(180, 1e-6));
    });

    test('angle difference wraps around 360', () {
      expect(SensorMath.angleDiff(350, 10), -20);
      expect(SensorMath.angleDiff(10, 350), 20);
      expect(SensorMath.angleDiff(180, 0).abs(), 180);
    });
  });

  group('VisionService tracking math', () {
    test('IoU of identical rects is 1, disjoint is 0', () {
      const a = Rect.fromLTWH(0.1, 0.1, 0.2, 0.2);
      expect(VisionService.computeIoU(a, a), closeTo(1.0, 1e-9));
      expect(VisionService.computeIoU(a, const Rect.fromLTWH(0.5, 0.5, 0.2, 0.2)), 0.0);
    });

    test('associate follows the overlapping same-label detection', () {
      final tracked = DetectedObjectData(const Rect.fromLTWH(0.4, 0.4, 0.2, 0.2), ['person'], 0.9);
      final near = DetectedObjectData(const Rect.fromLTWH(0.42, 0.41, 0.2, 0.2), ['person'], 0.6);
      final far = DetectedObjectData(const Rect.fromLTWH(0.0, 0.0, 0.1, 0.1), ['person'], 0.95);
      final cat = DetectedObjectData(const Rect.fromLTWH(0.4, 0.4, 0.2, 0.2), ['cat'], 0.99);
      expect(VisionService.associate(tracked, [far, cat, near]), same(near));
    });

    test('associate snaps to most confident same-label when overlap is lost', () {
      final tracked = DetectedObjectData(const Rect.fromLTWH(0.0, 0.0, 0.1, 0.1), ['dog'], 0.9);
      final a = DetectedObjectData(const Rect.fromLTWH(0.8, 0.8, 0.1, 0.1), ['dog'], 0.5);
      final b = DetectedObjectData(const Rect.fromLTWH(0.8, 0.1, 0.1, 0.1), ['dog'], 0.7);
      expect(VisionService.associate(tracked, [a, b]), same(b));
    });

    test('associate returns null when the label vanished', () {
      final tracked = DetectedObjectData(const Rect.fromLTWH(0.4, 0.4, 0.2, 0.2), ['person'], 0.9);
      final cat = DetectedObjectData(const Rect.fromLTWH(0.4, 0.4, 0.2, 0.2), ['cat'], 0.99);
      expect(VisionService.associate(tracked, [cat]), isNull);
    });
  });
}
