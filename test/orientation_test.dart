import 'dart:ui';

import 'package:do_robotics/services/mount_detector.dart';
import 'package:do_robotics/services/object_detector_service.dart';
import 'package:do_robotics/services/vision_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phone mount handling: the mount only turns the picture for the model;
/// steering values stay in the robot's frame.
void main() {
  group('MountDetector (automatic upright / upside-down)', () {
    final t0 = DateTime(2026, 1, 1);
    DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

    test('an upright phone stays upright', () {
      final d = MountDetector();
      for (var ms = 0; ms < 2000; ms += 100) {
        d.update(0, 9.8, 0.5, at(ms));
      }
      expect(d.upsideDown, isFalse);
    });

    test('upside down is adopted after it has lasted the hold time', () {
      final d = MountDetector();
      d.update(0, -9.8, 0.3, at(0));
      d.update(0, -9.8, 0.3, at(500));
      expect(d.upsideDown, isFalse, reason: 'not yet: could be a bump');
      d.update(0, -9.8, 0.3, at(900));
      expect(d.upsideDown, isTrue);
    });

    test('a short bump does not flip it', () {
      final d = MountDetector();
      d.update(0, -9.8, 0, at(0));
      d.update(0, 9.8, 0, at(300)); // back to upright before the hold time
      d.update(0, -9.8, 0, at(400)); // candidate restarts here
      d.update(0, -9.8, 0, at(1000));
      expect(d.upsideDown, isFalse);
      d.update(0, -9.8, 0, at(1300));
      expect(d.upsideDown, isTrue);
    });

    test('lying flat keeps the last decision', () {
      final d = MountDetector();
      d.update(0, -9.8, 0, at(0));
      d.update(0, -9.8, 0, at(1000));
      expect(d.upsideDown, isTrue);
      d.update(0, 0.3, 9.8, at(2000));
      d.update(0, 0.3, 9.8, at(5000));
      expect(d.upsideDown, isTrue);
    });
  });

  group('frame rotation and boxes', () {
    test('rotation for the usual 90° back camera', () {
      expect(VisionService.frameRotation(90, false), 90);
      expect(VisionService.frameRotation(90, true), 270);
      expect(VisionService.frameRotation(270, false), 270);
    });

    test('upright phone: screen box equals the robot-frame box', () {
      const box = Rect.fromLTRB(0.6, 0.2, 0.9, 0.7);
      expect(ObjectDetectorService.uprightToDisplay(box, 0), box);
    });

    test('upside-down phone: the screen shows the picture turned 180°', () {
      const box = Rect.fromLTRB(0.6, 0.2, 0.9, 0.7); // robot's right half
      final screen = ObjectDetectorService.uprightToDisplay(box, 180);
      expect(screen.left, closeTo(0.1, 1e-9));
      expect(screen.right, closeTo(0.4, 1e-9));
      expect(screen.top, closeTo(0.3, 1e-9));
      expect(screen.bottom, closeTo(0.8, 1e-9));
    });

    test('quarter turns keep the box inside 0..1 and invert each other', () {
      const box = Rect.fromLTRB(0.1, 0.2, 0.3, 0.6);
      final there = ObjectDetectorService.uprightToDisplay(box, 90);
      final back = ObjectDetectorService.uprightToDisplay(there, 270);
      expect(back.left, closeTo(box.left, 1e-9));
      expect(back.top, closeTo(box.top, 1e-9));
      expect(back.right, closeTo(box.right, 1e-9));
      expect(back.bottom, closeTo(box.bottom, 1e-9));
    });
  });

  test('steering uses the robot frame, not the (possibly flipped) screen', () {
    final vision = VisionService();
    vision.clock = () => DateTime(2026, 1, 1);
    // Person on the robot's right; the phone is upside down, so on screen
    // the box is on the left.
    const upright = Rect.fromLTRB(0.6, 0.3, 0.9, 0.9);
    final screen = ObjectDetectorService.uprightToDisplay(upright, 180);
    vision.debugOnDetections([
      DetectionResult(boundingBox: screen, uprightBox: upright, label: 'person', score: 0.9),
    ]);
    vision.autoLockOnLabel('person');
    expect(vision.targetOffsetX, closeTo(0.5, 1e-9)); // right = positive
    expect(vision.targetOffsetY, closeTo(0.2, 1e-9));
    expect(vision.targetArea, closeTo(18, 1e-6));
    expect(vision.trackedObject!.boundingBox.center.dx, lessThan(0.5)); // drawn on the left
  });
}
