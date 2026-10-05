import 'package:do_robotics/logic/code_generator.dart';
import 'package:do_robotics/logic/servo_tracking.dart';
import 'package:do_robotics/models/actuator_config.dart';
import 'package:do_robotics/models/block_factory.dart';
import 'package:do_robotics/models/block_models.dart';
import 'package:do_robotics/python/parser.dart';
import 'package:do_robotics/utils/execution_logger.dart';
import 'package:flutter_test/flutter_test.dart';

import 'python/robot_module_test.dart' show runRobot;

void main() {
  group('Phone on the servo (camera turns with it)', () {
    // The camera sees about ±30° (x = ±1 at the edges). A person standing at
    // [person]° (servo angle that would centre them); the servo at [angle]°
    // sees them at x = (angle - person) / 30, since a lower angle turns right.
    double offsetSeen(double angle, double person) => ((angle - person) / 30).clamp(-1.0, 1.0);

    test('settles on the person without swinging back and forth', () {
      for (final person in [40.0, 75.0, 130.0]) {
        var angle = 90.0;
        final errors = <double>[];
        for (var frame = 0; frame < 60; frame++) {
          angle = ServoTracking.next(ServoTracking.onServo, angle, offsetSeen(angle, person), 50);
          errors.add((angle - person).abs());
        }
        expect(errors.last, lessThan(ServoTracking.deadband * 30 + 0.01), reason: 'person at $person°');
        for (var i = 1; i < errors.length; i++) {
          expect(errors[i], lessThanOrEqualTo(errors[i - 1] + 1e-9), reason: 'never moves away ($person°)');
        }
      }
    });

    test('holds still when the person is (nearly) centred', () {
      expect(ServoTracking.next(ServoTracking.onServo, 70, 0.05, 50), 70);
    });

    test('person on the right lowers the angle; REVERSED raises it', () {
      expect(ServoTracking.next(ServoTracking.onServo, 90, 0.5, 50), lessThan(90));
      expect(ServoTracking.next(ServoTracking.onServo, 90, 0.5, 50, reversed: true), greaterThan(90));
    });

    test('regression: the old absolute mapping never settled with the phone on the servo', () {
      // angle = 90 - x * multiplier: once the person is centred x = 0 and the
      // servo swings back to 90°, then x grows again, over and over.
      var angle = 90.0;
      const person = 50.0;
      final seen = <double>{};
      for (var frame = 0; frame < 20; frame++) {
        angle = 90 - offsetSeen(angle, person) * 90;
        seen.add(angle.roundToDouble());
      }
      expect(seen.length, greaterThan(1), reason: 'keeps changing');
    });
  });

  group('Phone fixed (servo points on its own)', () {
    test('moves half way per picture to the matching angle', () {
      // strength 50: a person at the right edge (x = 1) means 30° right.
      var angle = 90.0;
      angle = ServoTracking.next(ServoTracking.fixed, angle, 1, 50);
      expect(angle, 75);
      for (var i = 0; i < 20; i++) {
        angle = ServoTracking.next(ServoTracking.fixed, angle, 1, 50);
      }
      expect(angle, closeTo(60, 0.01));
    });

    test('REVERSED points the other way', () {
      var angle = 90.0;
      for (var i = 0; i < 30; i++) {
        angle = ServoTracking.next(ServoTracking.fixed, angle, 1, 50, reversed: true);
      }
      expect(angle, closeTo(120, 0.01));
    });
  });

  group('Track X → Python', () {
    final arm = ActuatorConfig(
        id: 's1', name: 'Arm', type: ActuatorType.servo, pin: 9, parameters: {'minAngle': 0, 'maxAngle': 180});
    final def = BlockFactory.actuatorTrackingBlock(arm);
    String code(Map<String, dynamic> inputs) => CodeGenerator.generateCode(
        [BlockInstance(instanceId: 't', definition: def, inputValues: inputs)]);

    test('both modes convert to valid RoboPython that waits for a new picture', () {
      for (final mode in ServoTracking.modes) {
        for (final dir in ['NORMAL', 'REVERSED']) {
          final c = code({'mode': mode, 'strength': 50, 'direction': dir});
          expect(Parser.parse(c), isNotNull, reason: '$mode $dir');
          expect(c, contains('robot.vision.frame != arm_frame'));
          expect(c, contains('arm_angle, arm_frame = 90, -1'));
        }
      }
    });

    test('Python moves the servo to the same angle as the block would', () async {
      final logs = ExecutionLogger();
      for (final mode in ServoTracking.modes) {
        for (final dir in ['NORMAL', 'REVERSED']) {
          logs.clear();
          await runRobot(code({'mode': mode, 'strength': 50, 'direction': dir}), configure: (api) {
            api.detected = true; // the fake robot's servo is "Arm"
            api.offX = 0.4;
          });
          final expected =
              ServoTracking.next(mode, 90, 0.4, 50, reversed: dir == 'REVERSED').round();
          expect(logs.logs.any((l) => l.contains('Arm: angle $expected°')), isTrue,
              reason: '$mode $dir → $expected°, log: ${logs.logs}');
        }
      }
    });
  });
}
