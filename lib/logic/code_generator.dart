import '../models/block_models.dart';
import 'smart_follow.dart';

/// Converts a block program into runnable RoboPython (the same API the
/// Python tab executes). One-way: the result is meant to be edited further.
class CodeGenerator {
  static String generateCode(List<BlockInstance> script) {
    if (script.isEmpty) return "# No blocks yet.\n# Drag blocks onto the canvas, then convert.\n";
    return _Gen(script).generate();
  }
}

class _Gen {
  final List<BlockInstance> script;
  final Map<String, String> _varForActuator = {}; // block id prefix → variable name
  final Set<String> _usedVars = {};
  final List<String> _declarations = [];
  final Set<String> _imports = {'robot'};
  _Gen(this.script);

  String generate() {
    final body = StringBuffer();
    for (final block in script) {
      body.write(_stmt(block, 0));
      body.writeln();
    }
    final out = StringBuffer();
    for (final m in _imports.toList()..sort()) {
      out.writeln("import $m");
    }
    if (_declarations.isNotEmpty) {
      out.writeln();
      for (final d in _declarations) {
        out.writeln(d);
      }
    }
    out.writeln();
    out.write(body.toString().trimRight());
    out.writeln();
    return out.toString();
  }

  // ── Actuator variables ─────────────────────────────────────────────────────

  /// Returns the Python variable bound to this actuator block, declaring it on
  /// first use, e.g. `left_wheel = robot.motor("Left Wheel")`.
  String _actuatorVar(BlockInstance block) {
    final id = block.definition.id;
    final key = id.startsWith('act_servo_track_x_')
        ? 'act_servo_${id.substring('act_servo_track_x_'.length)}'
        : id;
    final existing = _varForActuator[key];
    if (existing != null) return existing;

    final label = block.definition.label
        .replaceAll(RegExp(r'^Track X: '), '')
        .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '')
        .toLowerCase();
    var name = label.isEmpty || RegExp(r'^\d').hasMatch(label) ? 'device_$label' : label;
    if (_pyKeywords.contains(name)) name = '${name}_';
    var candidate = name;
    int n = 2;
    while (_usedVars.contains(candidate)) {
      candidate = '$name$n';
      n++;
    }
    _usedVars.add(candidate);
    _varForActuator[key] = candidate;

    final kind = key.startsWith('act_motor_')
        ? 'motor'
        : key.startsWith('act_servo_')
            ? 'servo'
            : key.startsWith('act_led_')
                ? 'led'
                : key.startsWith('act_buzzer_')
                    ? 'buzzer'
                    : 'switch';
    final displayName = block.definition.label.replaceAll(RegExp(r'^Track X: '), '');
    _declarations.add('$candidate = robot.$kind(${_str(displayName)})');
    return candidate;
  }

  static const Set<String> _pyKeywords = {
    'if', 'else', 'while', 'for', 'in', 'def', 'return', 'and', 'or', 'not', 'import', 'from', 'pass',
    'break', 'continue', 'global', 'lambda', 'class', 'robot', 'time', 'math', 'random', 'print',
  };

  // ── Statements ─────────────────────────────────────────────────────────────

  String _ind(int level) => '    ' * level;

  String _body(BlockInstance? block, int level) {
    if (block == null) return '${_ind(level)}pass\n';
    return _stmt(block, level);
  }

  String _stmt(BlockInstance block, int level) {
    final ind = _ind(level);
    final out = StringBuffer();
    final id = block.definition.id;

    switch (id) {
      case 'logic_if':
        out.writeln('${ind}if ${_bool(block.nestedBlocks['condition'])}:');
        out.write(_body(block.nestedBlocks['then'], level + 1));
        break;
      case 'logic_if_else':
        out.writeln('${ind}if ${_bool(block.nestedBlocks['condition'])}:');
        out.write(_body(block.nestedBlocks['then'], level + 1));
        out.writeln('${ind}else:');
        out.write(_body(block.nestedBlocks['else'], level + 1));
        break;
      case 'logic_while':
        out.writeln('${ind}while ${_bool(block.nestedBlocks['condition'])}:');
        out.write(_body(block.nestedBlocks['do'], level + 1));
        if (block.nestedBlocks['do'] != null) {
          out.writeln('${_ind(level + 1)}robot.wait(0.02)');
        }
        break;
      case 'logic_forever':
        out.writeln('${ind}while True:');
        out.write(_body(block.nestedBlocks['do'], level + 1));
        out.writeln('${_ind(level + 1)}robot.wait(0.02)');
        break;
      case 'logic_repeat_until':
        final cond = block.nestedBlocks['condition'];
        out.writeln(cond == null ? '${ind}while True:' : '${ind}while not ${_bool(cond)}:');
        out.write(_body(block.nestedBlocks['do'], level + 1));
        out.writeln('${_ind(level + 1)}robot.wait(0.02)');
        break;
      case 'logic_repeat':
        out.writeln('${ind}for i in range(${_numLit(block.inputValues['times'], 3)}):');
        out.write(_body(block.nestedBlocks['do'], level + 1));
        break;
      case 'logic_wait':
        out.writeln('${ind}robot.wait(${_numLit(block.inputValues['seconds'], 1)})');
        break;
      case 'logic_stop':
        out.writeln('${ind}robot.stop()');
        break;
      case 'act_print':
        out.writeln('${ind}print(${_expr(block.nestedBlocks['value'])})');
        break;
      case 'act_say':
        out.writeln('${ind}robot.say(${_str(block.inputValues['text']?.toString() ?? '')})');
        break;
      case 'act_smart_follow':
        out.write(_smartFollow(block, level));
        break;
      default:
        if (id.startsWith('act_')) {
          out.write(_actuatorStmt(block, level));
        } else {
          out.writeln('$ind# ${block.definition.label}');
        }
    }

    if (block.nextBlock != null) {
      out.write(_stmt(block.nextBlock!, level));
    }
    return out.toString();
  }

  String _actuatorStmt(BlockInstance block, int level) {
    final ind = _ind(level);
    final id = block.definition.id;
    final v = _actuatorVar(block);
    final inputs = block.definition.inputs;

    if (id.startsWith('act_servo_track_x_')) {
      final multi = _numLit(block.inputValues['multiplier'], 90);
      return '$ind$v.angle(int(90 - robot.vision.offset_x * $multi))\n';
    }
    if (inputs.any((i) => i.id == 'direction')) {
      final dir = (block.inputValues['direction'] ?? 'FORWARD').toString().toUpperCase();
      final isServo = id.startsWith('act_servo_');
      final speed = _numLit(block.inputValues['speed'], isServo ? 75 : 128);
      if (dir == 'STOP') return '$ind$v.stop()\n';
      return '$ind$v.${dir.toLowerCase()}($speed)\n';
    }
    if (inputs.any((i) => i.id == 'state')) {
      final state = (block.inputValues['state'] ?? 'ON').toString().toUpperCase();
      return '$ind$v.${state.toLowerCase()}()\n';
    }
    if (inputs.any((i) => i.id == 'angle')) {
      final angleBlock = block.nestedBlocks['angle'];
      final angle = angleBlock != null ? 'int(${_expr(angleBlock)})' : _numLit(block.inputValues['angle'], 90);
      return '$ind$v.angle($angle)\n';
    }
    return '$ind# ${block.definition.label}\n';
  }

  // Same behaviour as the block runner (SmartFollowControl): chase the target
  // in small steps, turning harder the further off-centre it is; stand still
  // while there is no target.
  String _smartFollow(BlockInstance block, int level) {
    String ind(int extra) => _ind(level + extra);
    final mode = (block.inputValues['mode'] ?? 'FETCH').toString().toUpperCase();
    final speed = _numLit(block.inputValues['baseSpeed'], 150);
    final low = _numLit(block.inputValues['minSpeed'], 100);
    final arrived = _numLit(block.inputValues['arrivedPct'], 30);
    final sign = (block.inputValues['steering'] ?? 'NORMAL').toString() == 'REVERSED' ? '-' : '';
    final fetch = mode != 'FOLLOW';
    String secs(int ms) => (ms / 1000).toString();
    final out = StringBuffer();
    void line(int extra, String code) => out.writeln('${ind(extra)}$code');
    line(0, '# Smart Follow ($mode): uses the first two motors as left / right');
    line(0, 'left, right = robot.motor(robot.motors[0]), robot.motor(robot.motors[1])');
    line(0, 'base, low = $speed, $low      # cruising speed, lowest speed that turns a wheel');
    line(0, 'step, pause = ${secs(SmartFollowControl.stepMs)}, ${secs(SmartFollowControl.pauseMs)}'
        '  # seconds: drive one small step, then stand still');
    line(0, fetch ? 'near = 0' : 'hold = False');
    line(0, 'while True:');
    line(1, 'if not robot.vision.locked and robot.vision.detected:');
    line(2, 'robot.vision.lock(robot.vision.objects[0])');
    line(1, 'if not robot.vision.locked:');
    line(2, '# no target: stand still and keep watching');
    line(2, 'left.stop(); right.stop()');
    line(2, 'robot.wait(0.05)');
    line(2, 'continue');
    line(1, 'x = ${sign}robot.vision.offset_x   # -1 (left) .. 1 (right)');
    if (fetch) {
      line(1, 'near = near + 1 if robot.vision.size > $arrived else 0');
      line(1, 'if near >= 3:');
      line(2, 'left.stop(); right.stop()');
      line(2, 'break');
    } else {
      line(1, 'if robot.vision.size > $arrived: hold = True');
      line(1, 'elif robot.vision.size < $arrived * 0.8: hold = False');
      line(1, 'if hold:');
      line(2, 'left.stop(); right.stop()');
      line(2, 'robot.wait(0.05)');
      line(2, 'continue');
    }
    line(1, 'fwd = base * max(0, 1 - abs(x) / ${SmartFollowControl.spinOffset})');
    line(1, 'turn = base * max(-1, min(1, ${SmartFollowControl.turnGain} * x))');
    line(1, 'speeds = []');
    line(1, 'for v in [fwd + turn, fwd - turn]:');
    line(2, '# gear motors need a minimum power to turn at all');
    line(2, 'if abs(v) < low / 2: v = 0');
    line(2, 'elif abs(v) < low: v = low if v > 0 else -low');
    line(2, 'speeds.append(int(round(max(-255, min(255, v)))))');
    line(1, 'left.speed(speeds[0]); right.speed(speeds[1])');
    line(1, 'robot.wait(step)');
    line(1, 'left.stop(); right.stop()');
    line(1, 'robot.wait(pause)');
    return out.toString();
  }

  // ── Expressions ────────────────────────────────────────────────────────────

  String _str(String v) => "'${v.replaceAll('\\', '\\\\').replaceAll("'", "\\'")}'";

  String _numLit(dynamic v, num fallback) {
    if (v is num) return v == v.truncateToDouble() && v is! int ? v.toInt().toString() : v.toString();
    if (v is String) {
      final n = num.tryParse(v.trim());
      if (n != null) return _numLit(n, fallback);
    }
    return fallback.toString();
  }

  String _bool(BlockInstance? block) {
    if (block == null) return 'False';
    if (block.definition.shape == BlockShape.expression) return _expr(block);
    switch (block.definition.id) {
      case 'bool_true':
        return 'True';
      case 'bool_false':
        return 'False';
      case 'logic_expression':
        return (block.inputValues['expression'] ?? 'True').toString();
      case 'sense_object_detected':
        return 'robot.vision.detected';
      case 'sense_object_locked':
        return 'robot.vision.lock(${_str((block.inputValues['target'] ?? 'person').toString().toLowerCase())})';
      case 'sense_locked':
        return 'robot.vision.locked';
      case 'sense_line_detected':
        return 'robot.vision.line_visible';
      case 'sense_shake':
        return 'robot.imu.shaking';
      case 'sense_tilt':
        return 'robot.imu.tilted';
      case 'sense_rotating':
        return 'robot.imu.spinning';
      case 'sense_facing':
        return 'robot.compass.facing(${_str(block.inputValues['direction']?.toString() ?? 'North')})';
      case 'sense_loud':
        return 'robot.mic.loud';
      case 'sense_voice':
        return 'robot.mic.heard(${_str(block.inputValues['phrase']?.toString() ?? '')})';
      case 'bool_and':
        return '(${_bool(block.nestedBlocks['left'])} and ${_bool(block.nestedBlocks['right'])})';
      case 'bool_or':
        return '(${_bool(block.nestedBlocks['left'])} or ${_bool(block.nestedBlocks['right'])})';
      case 'bool_not':
        return 'not ${_bool(block.nestedBlocks['value'])}';
      case 'math_less_than':
        return '${_expr(block.nestedBlocks['left'])} < ${_expr(block.nestedBlocks['right'])}';
      case 'math_greater_than':
        return '${_expr(block.nestedBlocks['left'])} > ${_expr(block.nestedBlocks['right'])}';
      case 'math_equals':
        return '(${_expr(block.nestedBlocks['left'])} == ${_expr(block.nestedBlocks['right'])})';
      default:
        return 'False';
    }
  }

  String _expr(BlockInstance? block) {
    if (block == null) return '0';
    switch (block.definition.id) {
      case 'sense_offset_x':
        return 'robot.vision.offset_x';
      case 'sense_offset_y':
        return 'robot.vision.offset_y';
      case 'sense_target_size':
        return 'robot.vision.size';
      case 'sense_line_offset_x':
        return 'robot.vision.line_offset';
      case 'sense_rotation_rate':
        return 'robot.imu.yaw_rate';
      case 'sense_tilt_angle_x':
        return 'robot.imu.pitch';
      case 'sense_tilt_angle_y':
        return 'robot.imu.roll';
      case 'sense_heading':
        return 'robot.compass.heading';
      case 'math_number':
        return _numLit(block.inputValues['value'], 0);
      case 'math_random':
        _imports.add('random');
        return 'random.randint(${_numLit(block.inputValues['from'], 1)}, ${_numLit(block.inputValues['to'], 10)})';
      case 'math_add':
        return '(${_expr(block.nestedBlocks['left'])} + ${_expr(block.nestedBlocks['right'])})';
      case 'math_subtract':
        return '(${_expr(block.nestedBlocks['left'])} - ${_expr(block.nestedBlocks['right'])})';
      case 'math_multiply':
        return '(${_expr(block.nestedBlocks['left'])} * ${_expr(block.nestedBlocks['right'])})';
      case 'math_divide':
        return '(${_expr(block.nestedBlocks['left'])} / ${_expr(block.nestedBlocks['right'])})';
      default:
        if (block.definition.shape == BlockShape.boolean) return _bool(block);
        return _numLit(block.inputValues['value'], 0);
    }
  }
}
