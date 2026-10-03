import 'package:do_robotics/logic/code_generator.dart';
import 'package:do_robotics/logic/smart_follow.dart';
import 'package:do_robotics/models/block_factory.dart';
import 'package:do_robotics/models/block_models.dart';
import 'package:do_robotics/python/parser.dart';
import 'package:do_robotics/utils/execution_logger.dart';
import 'package:flutter_test/flutter_test.dart';

import 'python/robot_module_test.dart' show runRobot;

void main() {
  group('SmartFollowControl.wheelSpeeds (base 150, min 100)', () {
    (int, int) w(double x) => SmartFollowControl.wheelSpeeds(x, 150, 100);

    test('centred: straight ahead at cruising speed', () {
      expect(w(0), (150, 150));
    });

    test('a little to the right: both wheels drive, the left one faster', () {
      final (l, r) = w(0.1);
      expect(l, greaterThan(r));
      expect(r, greaterThanOrEqualTo(100), reason: 'never below the min speed');
    });

    test('further right: pivots, then spins on the spot', () {
      final (l1, r1) = w(0.3);
      expect(l1, greaterThan(100));
      expect(r1, 0, reason: 'inner wheel too slow to turn: stopped, not humming');
      final (l2, r2) = w(0.8);
      expect(l2, 150);
      expect(r2, -150);
    });

    test('left is the mirror image of right', () {
      for (final x in [0.05, 0.2, 0.35, 0.5, 0.9]) {
        final (l, r) = w(x);
        expect(w(-x), (r, l), reason: 'x=$x');
      }
    });

    test('every moving wheel gets at least the min speed', () {
      for (var i = -100; i <= 100; i++) {
        final (l, r) = w(i / 100);
        for (final v in [l, r]) {
          expect(v == 0 || v.abs() >= 100, isTrue, reason: 'x=${i / 100} → $v');
          expect(v.abs(), lessThanOrEqualTo(255));
        }
      }
    });

    test('regression: no longer just one wheel at a weak speed', () {
      // The old controller drove only the outer wheel at base speed (100)
      // for 60 ms pulses once the target was 0.2 off-centre.
      final (l, r) = SmartFollowControl.wheelSpeeds(0.2, 100, 60);
      expect(l, greaterThan(0));
      expect(r, greaterThan(0), reason: 'still rolling forward while turning');
    });
  });

  group('Smart Follow → Python', () {
    final def = BlockFactory.getAllStaticBlocks().firstWhere((d) => d.id == 'act_smart_follow');
    String code(Map<String, dynamic> inputs) => CodeGenerator.generateCode(
        [BlockInstance(instanceId: 'sf', definition: def, inputValues: inputs)]);

    test('every mode converts to valid RoboPython', () {
      for (final mode in ['FETCH', 'FOLLOW']) {
        for (final steering in ['NORMAL', 'REVERSED']) {
          final c = code({'mode': mode, 'steering': steering, 'baseSpeed': 150, 'minSpeed': 100, 'arrivedPct': 30});
          expect(Parser.parse(c), isNotNull, reason: '$mode $steering');
          expect(c, contains('robot.vision.lock(robot.vision.objects[0])'),
              reason: 'locks a target, otherwise offset_x stays 0');
          expect(c, contains('${SmartFollowControl.turnGain} * x'));
        }
      }
      expect(code({'steering': 'REVERSED'}), contains('x = -robot.vision.offset_x'));
    });

    test('FETCH runs and stops once the target is close', () async {
      final c = code({'mode': 'FETCH', 'baseSpeed': 150, 'minSpeed': 100, 'arrivedPct': 30});
      final logs = ExecutionLogger();
      logs.clear();
      final (_, api) = await runRobot(c, configure: (api) {
        api.detected = true;
        api.offX = 0;
        api.sz = 50; // already close
      });
      expect(api.calls, isNot(contains(startsWith('lock'))), reason: 'already locked');
      expect(logs.logs.any((l) => l.contains('Left Wheel: STOP')), isTrue);
    });
  });
}
