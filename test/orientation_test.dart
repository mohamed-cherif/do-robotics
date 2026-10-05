import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:do_robotics/services/mount_detector.dart';
import 'package:do_robotics/services/object_detector_service.dart';
import 'package:do_robotics/services/vision_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phone mount handling: the mount only turns the picture for the model;
/// steering values stay in the robot's frame.
void main() {
  group('MountDetector (automatic: upright, upside down, on its side)', () {
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

    // Gravity reaction for a portrait phone leaning back by [deg] from
    // vertical, upright (+1) or upside down (-1).
    List<double> leaning(double deg, double up) => [
          0,
          up * 9.8 * math.cos(deg * math.pi / 180),
          9.8 * math.sin(deg * math.pi / 180),
        ];

    test('upside down and leaning back on the robot is still upside down', () {
      // Regression: 60° back left only half of gravity on the long axis, and
      // the old rule (needs 60 %) kept "upright": steering came out mirrored.
      for (final deg in [30.0, 60.0, 68.0]) {
        final d = MountDetector();
        final g = leaning(deg, -1);
        d.update(g[0], g[1], g[2], at(0));
        d.update(g[0], g[1], g[2], at(900));
        expect(d.upsideDown, isTrue, reason: 'leaning $deg°');
      }
    });

    test('upright and leaning back stays upright', () {
      final d = MountDetector();
      d.update(0, -9.8, 0, at(0));
      d.update(0, -9.8, 0, at(900));
      expect(d.upsideDown, isTrue);
      final g = leaning(60, 1);
      d.update(g[0], g[1], g[2], at(1000));
      d.update(g[0], g[1], g[2], at(1900));
      expect(d.upsideDown, isFalse);
    });

    test('upside down and rolled 30° to one side is still upside down', () {
      final d = MountDetector();
      d.update(4.9, -8.49, 0, at(0));
      d.update(4.9, -8.49, 0, at(900));
      expect(d.upsideDown, isTrue);
    });

    test('nearly flat keeps the last decision', () {
      final d = MountDetector();
      d.update(0, -9.8, 0, at(0));
      d.update(0, -9.8, 0, at(900));
      expect(d.upsideDown, isTrue);
      final g = leaning(75, 1); // 15° from lying flat: too close to call
      d.update(g[0], g[1], g[2], at(1000));
      d.update(g[0], g[1], g[2], at(3000));
      expect(d.rotation, 180);
    });

    test('on its side: top edge left is 90, top edge right is 270', () {
      // Top edge to the left (seen from the screen): the right edge points
      // up, so gravity's reaction is along +X.
      final d = MountDetector();
      d.update(9.8, 0.5, 0, at(0));
      d.update(9.8, 0.5, 0, at(500));
      expect(d.rotation, 0, reason: 'not yet: could be a bump');
      d.update(9.8, 0.5, 0, at(900));
      expect(d.rotation, 90);
      d.update(-9.8, 0.5, 0, at(1000));
      d.update(-9.8, 0.5, 0, at(1900));
      expect(d.rotation, 270);
      expect(d.upsideDown, isFalse);
    });

    test('on its side and leaning back is still on its side', () {
      for (final deg in [30.0, 60.0, 68.0]) {
        final lean = deg * math.pi / 180;
        final d = MountDetector();
        d.update(9.8 * math.cos(lean), 0, 9.8 * math.sin(lean), at(0));
        d.update(9.8 * math.cos(lean), 0, 9.8 * math.sin(lean), at(900));
        expect(d.rotation, 90, reason: 'leaning $deg°');
      }
    });

    test('the axis gravity pulls along most decides', () {
      expect(MountDetector.reading(4.9, 8.49, 0), 0); // 30° from upright
      expect(MountDetector.reading(8.49, 4.9, 0), 90); // 60°: more sideways
      expect(MountDetector.reading(-8.49, -4.9, 0), 270);
      expect(MountDetector.reading(0, 0, 9.8), isNull); // flat
      expect(MountDetector.reading(0, 0.1, 0.1), isNull); // free fall / no data
    });
  });

  group('phone mount setting', () {
    test('fixed mounts give their turn; Automatic asks the detector', () {
      expect(PhoneMount.upright.fixedRotation, 0);
      expect(PhoneMount.topLeft.fixedRotation, 90);
      expect(PhoneMount.upsideDown.fixedRotation, 180);
      expect(PhoneMount.topRight.fixedRotation, 270);
      expect(PhoneMount.auto.fixedRotation, isNull);
    });

    test('the log names every turn', () {
      expect(MountDetector.describe(0), 'upright');
      expect(MountDetector.describe(90), contains('left'));
      expect(MountDetector.describe(180), 'upside down');
      expect(MountDetector.describe(270), contains('right'));
    });
  });

  group('frame rotation and boxes', () {
    test('rotation for the usual 90° back camera', () {
      expect(VisionService.frameRotation(90, 0), 90);
      expect(VisionService.frameRotation(90, 180), 270);
      expect(VisionService.frameRotation(270, 0), 270);
      // On its side with the top edge left, the (landscape) sensor picture
      // is already upright; top edge right, it is upside down.
      expect(VisionService.frameRotation(90, 90), 0);
      expect(VisionService.frameRotation(90, 270), 180);
    });

    test('screen boxes: phone turn minus screen turn', () {
      expect(VisionService.displayNet(0, 0), 0); // upright, portrait
      expect(VisionService.displayNet(180, 0), 180); // upside down, portrait
      expect(VisionService.displayNet(90, 90), 0); // sideways, camera page sideways
      expect(VisionService.displayNet(270, 270), 0);
      expect(VisionService.displayNet(90, 0), 90); // sideways on the robot, screen portrait
      expect(VisionService.displayNet(0, 90), 270); // auto-rotate on, mount fixed upright
    });

    test('screen turn comes from the orientation the preview is drawn for', () {
      const description = CameraDescription(
          name: '0', lensDirection: CameraLensDirection.back, sensorOrientation: 90);
      final value = const CameraValue.uninitialized(description);
      expect(VisionService.screenRotation(null), 0);
      expect(VisionService.screenRotation(value.copyWith(deviceOrientation: DeviceOrientation.portraitUp)), 0);
      expect(VisionService.screenRotation(value.copyWith(deviceOrientation: DeviceOrientation.landscapeLeft)), 90);
      expect(VisionService.screenRotation(value.copyWith(deviceOrientation: DeviceOrientation.landscapeRight)), 270);
      expect(VisionService.screenRotation(value.copyWith(deviceOrientation: DeviceOrientation.portraitDown)), 180);
      // A locked capture orientation wins, as in CameraPreview.
      expect(
          VisionService.screenRotation(value.copyWith(
              deviceOrientation: DeviceOrientation.landscapeLeft,
              lockedCaptureOrientation: Optional.of(DeviceOrientation.portraitUp))),
          0);
    });

    test('boxes line up with the preview for every phone and screen turn', () {
      // The model sees the sensor picture turned by frameRotation; the
      // preview shows it turned by (sensor orientation - screen turn). The
      // drawn box (the model's box turned by displayNet) must land where
      // the object is in the preview.
      Rect turn(Rect b, int deg) => ObjectDetectorService.uprightToDisplay(b, deg);
      const inSensor = Rect.fromLTRB(0.1, 0.2, 0.35, 0.6);
      for (final sensor in [90, 270]) {
        for (final phone in [0, 90, 180, 270]) {
          for (final screen in [0, 90, 180, 270]) {
            final upright = turn(inSensor, VisionService.frameRotation(sensor, phone));
            final drawn = turn(upright, VisionService.displayNet(phone, screen));
            final preview = turn(inSensor, (sensor - screen + 360) % 360);
            final where = 'sensor $sensor, phone $phone, screen $screen';
            expect(drawn.left, closeTo(preview.left, 1e-9), reason: where);
            expect(drawn.top, closeTo(preview.top, 1e-9), reason: where);
            expect(drawn.right, closeTo(preview.right, 1e-9), reason: where);
            expect(drawn.bottom, closeTo(preview.bottom, 1e-9), reason: where);
          }
        }
      }
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

  test('phone on its side: steering still uses the robot frame', () {
    final vision = VisionService();
    vision.clock = () => DateTime(2026, 1, 2);
    vision.unlock();
    // Person on the robot's right; the phone lies on its side (top edge
    // left) and the screen stays portrait, so the box is drawn turned.
    const upright = Rect.fromLTRB(0.7, 0.2, 0.9, 0.8);
    final screen = ObjectDetectorService.uprightToDisplay(upright, VisionService.displayNet(90, 0));
    vision.debugOnDetections([
      DetectionResult(boundingBox: screen, uprightBox: upright, label: 'person', score: 0.9),
    ]);
    vision.autoLockOnLabel('person');
    expect(vision.targetOffsetX, closeTo(0.6, 1e-9)); // right = positive
    expect(vision.trackedObject!.boundingBox.center.dy, greaterThan(0.5)); // drawn lower on screen
  });
}
