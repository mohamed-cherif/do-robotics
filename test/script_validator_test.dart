import 'package:do_robotics/logic/script_validator.dart';
import 'package:do_robotics/models/actuator_config.dart';
import 'package:do_robotics/models/block_factory.dart';
import 'package:do_robotics/models/block_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final motor = ActuatorConfig(id: 'm1', name: 'Left Wheel', type: ActuatorType.motor, pin: 5);
  final defs = [...BlockFactory.getAllStaticBlocks(), BlockFactory.actuatorBlock(motor)];
  BlockDefinition def(String id) => defs.firstWhere((d) => d.id == id);
  var n = 0;
  BlockInstance b(String id, {Map<String, BlockInstance?>? nested, BlockInstance? next}) =>
      BlockInstance(instanceId: '${n++}', definition: def(id), nestedBlocks: nested, nextBlock: next);

  List<String> check(List<BlockInstance> roots,
          {List<ActuatorConfig>? actuators, bool connected = true}) =>
      ScriptValidator.validate(roots, actuators: actuators ?? [motor], robotConnected: connected)
          .map((i) => i.toString())
          .toList();

  test('a correct program has no issues', () {
    expect(
      check([
        b('logic_forever', nested: {
          'do': b('logic_if', nested: {'condition': b('sense_shake'), 'then': b('act_motor_m1')}),
        }),
      ]),
      isEmpty,
    );
  });

  test('empty conditions and bodies are explained', () {
    final issues = check([
      b('logic_if', next: b('logic_while', next: b('logic_forever'))),
    ]);
    expect(issues, contains(contains('"If" has no condition')));
    expect(issues, contains(contains('"While" has no condition')));
    expect(issues, contains(contains('"Forever" has nothing inside')));
  });

  test('comparisons missing a side are flagged, even deep inside', () {
    final issues = check([
      b('logic_repeat', nested: {
        'do': b('logic_if', nested: {
          'condition': b('math_less_than', nested: {'left': b('sense_offset_x')}),
          'then': b('act_print'),
        }),
      }),
    ]);
    expect(issues, [contains('"Less Than <" is missing something')]);
  });

  test('blocks for removed devices and Smart Follow without motors', () {
    final issues = check([b('act_motor_m1', next: b('act_smart_follow'))], actuators: []);
    expect(issues, contains(contains('uses a device that was removed')));
    expect(issues, contains(contains('Smart Follow needs two motors')));
  });

  test('a loose sensor block and a disconnected robot are hints', () {
    final issues = ScriptValidator.validate(
      [b('sense_shake'), b('act_motor_m1')],
      actuators: [motor],
      robotConnected: false,
    );
    expect(issues.map((i) => i.level), everyElement(IssueLevel.hint));
    expect(issues.map((i) => i.message).join(' '), allOf(contains('not inside another block'), contains("isn't connected")));
  });
}
