import '../models/actuator_config.dart';
import '../models/block_models.dart';

enum IssueLevel { problem, hint }

/// Something worth telling a beginner before their program runs.
class ScriptIssue {
  final IssueLevel level;
  final String message;
  const ScriptIssue(this.level, this.message);

  @override
  String toString() => '${level.name}: $message';
}

/// Static checks for a block program, in plain language for beginners.
/// Pure (no services), so it is unit-tested; the editor shows the result
/// before RUN and lets the user run anyway.
class ScriptValidator {
  ScriptValidator._();

  static List<ScriptIssue> validate(
    List<BlockInstance> roots, {
    required List<ActuatorConfig> actuators,
    required bool robotConnected,
  }) {
    final issues = <ScriptIssue>[];
    var usesHardware = false;

    void add(IssueLevel level, String message) {
      final issue = ScriptIssue(level, message);
      if (!issues.any((i) => i.message == message)) issues.add(issue);
    }

    String name(BlockInstance b) => '"${b.definition.label}"';

    void visit(BlockInstance b) {
      final id = b.definition.id;
      final n = b.nestedBlocks;
      switch (id) {
        case 'logic_if':
        case 'logic_if_else':
          if (n['condition'] == null) {
            add(IssueLevel.problem, '${name(b)} has no condition, so its "then" blocks never run.');
          }
          break;
        case 'logic_while':
          if (n['condition'] == null) {
            add(IssueLevel.problem, '${name(b)} has no condition, so it never runs.');
          } else if (n['do'] == null) {
            add(IssueLevel.hint, '${name(b)} has nothing inside "do".');
          }
          break;
        case 'logic_repeat_until':
          if (n['condition'] == null) {
            add(IssueLevel.hint, '${name(b)} has no condition, so it repeats forever.');
          }
          if (n['do'] == null) add(IssueLevel.hint, '${name(b)} has nothing inside "do".');
          break;
        case 'logic_forever':
        case 'logic_repeat':
          if (n['do'] == null) add(IssueLevel.hint, '${name(b)} has nothing inside "do".');
          break;
        case 'bool_and':
        case 'bool_or':
        case 'math_less_than':
        case 'math_greater_than':
        case 'math_equals':
          if (n['left'] == null || n['right'] == null) {
            add(IssueLevel.problem, '${name(b)} is missing something on one side.');
          }
          break;
        case 'bool_not':
          if (n['value'] == null) add(IssueLevel.problem, '${name(b)} is empty.');
          break;
        case 'act_smart_follow':
          usesHardware = true;
          if (actuators.where((a) => a.type == ActuatorType.motor).length < 2) {
            add(IssueLevel.problem,
                'Smart Follow needs two motors. Add them in Configure Hardware.');
          }
          break;
        default:
          if (id.startsWith('act_') && id != 'act_print' && id != 'act_say') {
            usesHardware = true;
            final actuatorId = id.startsWith('act_servo_track_x_')
                ? id.substring('act_servo_track_x_'.length)
                : id.split('_').skip(2).join('_');
            if (!actuators.any((a) => a.id == actuatorId)) {
              add(IssueLevel.problem,
                  '${name(b)} uses a device that was removed in Configure Hardware.');
            }
          }
      }
      for (final child in n.values.whereType<BlockInstance>()) {
        for (BlockInstance? c = child; c != null; c = c.nextBlock) {
          visit(c);
        }
      }
    }

    for (final root in roots) {
      final shape = root.definition.shape;
      if (shape == BlockShape.boolean || shape == BlockShape.expression) {
        add(IssueLevel.hint,
            '${name(root)} is not inside another block, so it does nothing on its own.');
        continue;
      }
      for (BlockInstance? b = root; b != null; b = b.nextBlock) {
        visit(b);
      }
    }

    if (usesHardware && !robotConnected) {
      add(IssueLevel.hint,
          "The robot isn't connected, so motor/LED/servo blocks won't do anything. "
          'Tap the header on the Home tab to connect.');
    }
    return issues;
  }
}
