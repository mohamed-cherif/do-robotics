import 'dart:ui';

import 'package:do_robotics/services/object_detector_service.dart';
import 'package:do_robotics/services/vision_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final vision = VisionService();
  var now = DateTime(2026, 1, 1, 12);
  vision.clock = () => now;

  test('a frozen camera stops reporting its last target', () {
    vision.debugOnDetections([
      DetectionResult(boundingBox: const Rect.fromLTRB(0.6, 0.4, 0.9, 0.8), label: 'person', score: 0.9),
    ]);
    vision.autoLockOnLabel('person');
    expect(vision.isObjectDetected, isTrue);
    expect(vision.isLocked, isTrue);
    expect(vision.targetOffsetX, greaterThan(0.4));

    // Frames still arriving: nothing changes.
    now = now.add(const Duration(milliseconds: 500));
    expect(vision.isLocked, isTrue);

    // No frame for longer than staleAfter (screen off, app in background...).
    now = now.add(VisionService.staleAfter);
    expect(vision.isObjectDetected, isFalse);
    expect(vision.isLocked, isFalse);
    expect(vision.targetOffsetX, 0.0);
    expect(vision.targetArea, 0.0);
    expect(vision.lastDetections, isEmpty);

    // A new frame brings it back.
    vision.debugOnDetections([
      DetectionResult(boundingBox: const Rect.fromLTRB(0.5, 0.4, 0.8, 0.8), label: 'person', score: 0.9),
    ]);
    expect(vision.isObjectDetected, isTrue);
    expect(vision.isLocked, isTrue);
  });
}
