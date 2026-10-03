import 'dart:ui';

import 'package:do_robotics/services/object_detector_service.dart';
import 'package:do_robotics/services/vision_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keeping a lock on a target through short dips in detection confidence.
/// The confidence threshold is the default 0.35.
void main() {
  final vision = VisionService();
  var now = DateTime(2026, 1, 1, 12);
  vision.clock = () => now;

  DetectionResult person(double left, double score) => DetectionResult(
      boundingBox: Rect.fromLTWH(left, 0.3, 0.3, 0.5), label: 'person', score: score);

  /// One processed frame, [ms] after the previous one.
  void frame(List<DetectionResult> results, {int ms = 40}) {
    now = now.add(Duration(milliseconds: ms));
    vision.debugOnDetections(results);
  }

  setUp(() {
    vision.unlock();
    frame(const []);
  });

  test('a locked target survives frames where it is seen only weakly', () {
    frame([person(0.5, 0.9)]);
    vision.autoLockOnLabel('person');
    expect(vision.isLocked, isTrue);

    for (var i = 1; i <= 30; i++) {
      frame([person(0.5 + i * 0.005, 0.25)]); // blurred: below the threshold
    }
    expect(vision.isLocked, isTrue);
    expect(vision.trackedObject!.boundingBox.left, closeTo(0.65, 1e-9),
        reason: 'follows the weak box, not the last confident one');
    // Weak detections don't count as "seen" anywhere else.
    expect(vision.isObjectDetected, isFalse);
    expect(vision.lastDetections, isEmpty);
  });

  test('weak detections never start a lock', () {
    frame([person(0.5, 0.25)]);
    vision.autoLockOnLabel('person');
    vision.autoLockOnBestDetection();
    vision.lockOn(const Rect.fromLTWH(0.6, 0.5, 0.1, 0.1));
    expect(vision.isLocked, isFalse);
  });

  test('a weak detection elsewhere does not keep the lock', () {
    frame([person(0.0, 0.9)]);
    vision.autoLockOnLabel('person');
    frame([person(0.6, 0.25)], ms: 500); // no overlap with the target
    expect(vision.isLocked, isTrue, reason: 'still within the grace period');
    expect(vision.trackedObject!.boundingBox.left, 0.0, reason: 'holds the last position');
    frame([person(0.6, 0.25)], ms: 600);
    expect(vision.isLocked, isFalse);
  });

  test('without any detection the lock is held for a second, then dropped', () {
    frame([person(0.6, 0.9)]);
    vision.autoLockOnLabel('person');
    final offset = vision.targetOffsetX;
    for (var i = 0; i < 24; i++) {
      frame(const []); // 960 ms
    }
    expect(vision.isLocked, isTrue);
    expect(vision.targetOffsetX, offset);
    frame(const [], ms: 80);
    expect(vision.isLocked, isFalse);
  });

  test('a confident detection of the target resets the grace period', () {
    frame([person(0.4, 0.9)]);
    vision.autoLockOnLabel('person');
    for (var i = 0; i < 3; i++) {
      frame(const [], ms: 900);
      frame([person(0.4, 0.8)]);
    }
    expect(vision.isLocked, isTrue);
  });

  test('the detector reports weak detections down to the tracking floor only', () {
    expect(ObjectDetectorService.trackingFloor, lessThan(0.35));
    expect(ObjectDetectorService.trackingFloor, greaterThanOrEqualTo(0.2));
  });
}
