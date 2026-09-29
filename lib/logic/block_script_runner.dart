import 'dart:async';
import 'dart:math' as math;
import '../models/block_models.dart';
import '../models/actuator_config.dart';
import '../services/vision_service.dart';
import '../services/sensor_service.dart';
import '../services/voice_service.dart';
import '../services/actuator_service.dart';
import '../utils/execution_logger.dart';
import 'actuator_driver.dart';
import 'python_script_runner.dart';

enum ExecutionState { idle, running, paused }

/// Identity of one program run. [BlockScriptRunner.stop] cancels it; code from
/// a previous run that is still unwinding checks its own token, never the
/// shared state, so it can neither keep executing inside the next run nor tear
/// that run down.
class _Run {
  bool _active = true;
  bool get active => _active;
  void cancel() => _active = false;
}

/// Pure helpers used by the runners, exposed for unit tests.
class ScriptUtils {
  ScriptUtils._();

  static final RegExp _nonWordRegex = RegExp(r'[^\w\s]');
  static final RegExp _whitespace = RegExp(r'\s+');

  /// Normalizes speech for matching: lowercase, punctuation stripped,
  /// whitespace collapsed.
  static String normalizeSpeech(String s) =>
      s.replaceAll(_nonWordRegex, '').toLowerCase().trim().replaceAll(_whitespace, ' ');

  /// True when every word of [phrase] appears as a whole word, in order, in
  /// [heard]. "stop" no longer matches "stopwatch"; "go forward" matches
  /// "please go forward now".
  static bool matchesPhrase(String heard, String phrase) {
    final h = normalizeSpeech(heard);
    final p = normalizeSpeech(phrase);
    if (h.isEmpty || p.isEmpty) return false;
    final pattern = RegExp(r'\b' + RegExp.escape(p).replaceAll(' ', r'\s+') + r'\b');
    return pattern.hasMatch(h);
  }

  /// Walks a block tree (nested slots + next chain) and returns true if any
  /// block satisfies [test].
  static bool anyBlock(Iterable<BlockInstance> roots, bool Function(BlockInstance) test) {
    for (final b in roots) {
      if (test(b)) return true;
      if (anyBlock(b.nestedBlocks.values.whereType<BlockInstance>(), test)) return true;
      if (b.nextBlock != null && anyBlock([b.nextBlock!], test)) return true;
    }
    return false;
  }

  static bool usesVision(Iterable<BlockInstance> roots) => anyBlock(roots, (b) {
        final id = b.definition.id;
        return id.startsWith('sense_object') ||
            id.startsWith('sense_locked') ||
            id.startsWith('sense_offset') ||
            id.startsWith('sense_target') ||
            id.startsWith('sense_line') ||
            id.startsWith('act_servo_track_x_') ||
            id == 'act_smart_follow';
      });

  static bool usesLineFollowing(Iterable<BlockInstance> roots) =>
      anyBlock(roots, (b) => b.definition.id.startsWith('sense_line'));

  static bool usesVoice(Iterable<BlockInstance> roots) =>
      anyBlock(roots, (b) => b.definition.id == 'sense_voice' || b.definition.id == 'sense_loud');

  static bool usesSpeech(Iterable<BlockInstance> roots) =>
      anyBlock(roots, (b) => b.definition.id == 'act_say');

  /// Lenient numeric parse for block input values (num, String, null).
  static double toDouble(dynamic v, double fallback) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  static int toInt(dynamic v, int fallback) => toDouble(v, fallback.toDouble()).round();
}

class BlockScriptRunner {
  static final BlockScriptRunner _instance = BlockScriptRunner._internal();
  factory BlockScriptRunner() => _instance;
  BlockScriptRunner._internal();

  ExecutionState _state = ExecutionState.idle;
  int _currentBlockIndex = -1;
  List<BlockInstance> _script = [];

  final StreamController<int> _executingBlockController = StreamController<int>.broadcast();
  final StreamController<ExecutionState> _stateController = StreamController<ExecutionState>.broadcast();

  Stream<int> get executingBlockStream => _executingBlockController.stream;
  Stream<ExecutionState> get stateStream => _stateController.stream;
  /// Latest recognized speech while running ('' when idle or consumed).
  Stream<String> get voiceStream => _voice.wordsStream;
  ExecutionState get state => _state;
  int get currentBlockIndex => _currentBlockIndex;

  // Service references
  final VisionService _visionService = VisionService();
  final SensorService _sensorService = SensorService();
  final VoiceService _voice = VoiceService();
  final ActuatorService _actuatorService = ActuatorService();
  final ActuatorDriver _driver = ActuatorDriver();
  final ExecutionLogger _logger = ExecutionLogger();
  final math.Random _random = math.Random();

  bool _visionStarted = false;
  bool _voiceStarted = false;
  Future<void>? _teardown;
  _Run? _run;
  bool _starting = false;

  void loadScript(List<BlockInstance> script) {
    _script = List.from(script);
  }

  Future<void> play() async {
    if (_script.isEmpty) return;
    if (_state == ExecutionState.running || _starting) return;
    if (PythonScriptRunner().state == ExecutionState.running) {
      _logger.log("⚠️ A Python program is already running — stop it first");
      return;
    }

    // Wait for a previous run's teardown (camera release) to finish so we
    // never re-open the camera while it is still being disposed. _starting
    // makes a double-tap during this wait a no-op instead of a second run.
    _starting = true;
    try {
      await _teardown;
    } finally {
      _starting = false;
    }

    final run = _Run();
    _run = run;
    _logger.clear();
    _logger.log("🟢 Program started");
    _state = ExecutionState.running;
    _stateController.add(_state);
    _currentBlockIndex = -1;
    _driver.reset();

    await _startSensorListening(run);
    await _executeScript(run);
  }

  /// Stops the running program. Safe to call more than once.
  void stop() {
    if (_state == ExecutionState.idle) return;
    _run?.cancel();
    _logger.log("⏹️ Program stopped");
    _state = ExecutionState.idle;
    _stateController.add(_state);
    _currentBlockIndex = -1;
    _executingBlockController.add(-1);
    _teardown = _finishRun();
  }

  Future<void> _finishRun() async {
    await _stopSensorListening();
    // Let any in-flight block command finish so our stop commands arrive last.
    await Future.delayed(const Duration(milliseconds: 150));
    _logger.log("🧹 Stopping all actuators...");
    await _driver.stopAll(_actuatorService.actuators);
  }

  Future<void> _startSensorListening(_Run run) async {
    // Phone IMU (tilt / shake / gyro / compass). Idempotent.
    _sensorService.startListening();

    if (ScriptUtils.usesVoice(_script)) {
      // Mark as held *before* awaiting, so a STOP during the permission
      // dialog or engine start-up still releases the mic.
      _voiceStarted = true;
      await _voice.startListening();
    }

    if (run.active && ScriptUtils.usesVision(_script)) {
      _visionStarted = true; // balanced by stopStream() even if start fails
      try {
        final lineMode = ScriptUtils.usesLineFollowing(_script);
        _visionService.lineMode = lineMode;
        // Wait (briefly) for the first processed frame so a program that
        // starts with `While <sensor>` doesn't see "nothing detected" just
        // because the camera hasn't delivered a frame yet.
        await _visionService.startStream();
        await _visionService.nextFrame();
        _logger.log(lineMode
            ? "🛤️ Vision: line-following mode (Sobel)"
            : "👁️ Vision: ${_visionService.loadedModelName}");
      } catch (e) {
        _logger.log("⚠️ Vision Init Error: $e");
      }
    }
  }

  Future<void> _stopSensorListening() async {
    if (_voiceStarted) {
      _voiceStarted = false;
      await _voice.stopListening();
    }
    await _voice.stopSpeaking();

    _visionService.unlock();
    if (_visionStarted) {
      _visionStarted = false;
      _visionService.lineMode = false;
      // Ref-counted: only actually disposes the camera if no page is using it.
      await _visionService.stopStream();
    }
    // The dashboard keeps the IMU alive; nothing to stop here.
  }

  Future<void> _executeScript(_Run run) async {
    try {
      for (int i = 0; i < _script.length; i++) {
        if (!run.active) break;

        _currentBlockIndex = i;
        _executingBlockController.add(i);

        await _executeChain(_script[i], run);
        await Future.delayed(const Duration(milliseconds: 30));
      }
    } catch (e, st) {
      _logger.log("💥 Runtime error: $e");
      _logger.log(st.toString().split('\n').first);
    }

    if (run.active) {
      _logger.log("🏁 Program finished");
      stop();
    }
  }

  /// Executes [first] and every block chained after it via `nextBlock`.
  Future<void> _executeChain(BlockInstance? first, _Run run) async {
    for (var block = first; block != null && run.active; block = block.nextBlock) {
      await _executeBlock(block, run);
    }
  }

  /// Executes a single block (its nested slots included, not its `nextBlock`).
  Future<void> _executeBlock(BlockInstance block, _Run run) async {
    final blockId = block.definition.id;

    if (blockId.startsWith('sense_') || blockId.startsWith('bool_') || blockId.startsWith('math_')) {
      // Value blocks are evaluated by their parent, never executed directly.
      return;
    }

    switch (blockId) {
      case 'logic_if':
        final condition = block.nestedBlocks['condition'];
        if (condition != null && _evaluateBoolean(condition)) {
          await _executeChain(block.nestedBlocks['then'], run);
        }
        break;

      case 'logic_if_else':
        final condition = block.nestedBlocks['condition'];
        final branch = (condition != null && _evaluateBoolean(condition))
            ? block.nestedBlocks['then']
            : block.nestedBlocks['else'];
        await _executeChain(branch, run);
        break;

      case 'logic_while':
        final condition = block.nestedBlocks['condition'];
        final doBlock = block.nestedBlocks['do'];
        while (run.active && condition != null && _evaluateBoolean(condition)) {
          await _executeChain(doBlock, run);
          if (!run.active) break;
          // Yield so sensors/vision streams get CPU time between iterations.
          await Future.delayed(const Duration(milliseconds: 20));
        }
        break;

      case 'logic_forever':
      case 'logic_repeat_until':
        final until = blockId == 'logic_repeat_until' ? block.nestedBlocks['condition'] : null;
        final doBlock = block.nestedBlocks['do'];
        // Repeat Until with an empty condition repeats forever (as in Scratch).
        while (run.active && !(until != null && _evaluateBoolean(until))) {
          await _executeChain(doBlock, run);
          if (!run.active) break;
          // Yield so sensors/vision streams get CPU time between iterations.
          await Future.delayed(const Duration(milliseconds: 20));
        }
        break;

      case 'logic_repeat':
        final times = ScriptUtils.toInt(block.inputValues['times'], 3).clamp(0, 10000);
        final doBlock = block.nestedBlocks['do'];
        for (int i = 0; i < times; i++) {
          if (!run.active) break;
          await _executeChain(doBlock, run);
          // Yield to the event loop so STOP and the UI stay responsive even
          // for a Repeat whose body never waits (e.g. only Print blocks).
          await Future.delayed(Duration.zero);
        }
        break;

      case 'logic_wait':
        final seconds = ScriptUtils.toDouble(block.inputValues['seconds'], 1.0).clamp(0.0, 3600.0);
        final millis = (seconds * 1000).round();
        // Sleep in slices so STOP is honoured promptly during long waits.
        final deadline = DateTime.now().add(Duration(milliseconds: millis));
        while (run.active) {
          final remaining = deadline.difference(DateTime.now()).inMilliseconds;
          if (remaining <= 0) break;
          await Future.delayed(Duration(milliseconds: remaining < 100 ? remaining : 100));
        }
        break;

      case 'logic_stop':
        _logger.log("🛑 Stop block reached");
        stop();
        return;

      default:
        if (blockId.startsWith('act_')) {
          await _executeActuatorBlock(block, run);
        }
    }
  }

  bool _evaluateBoolean(BlockInstance block) {
    switch (block.definition.id) {
      case 'bool_true':
        return true;
      case 'bool_false':
        return false;
      case 'logic_expression':
        final expr = block.inputValues['expression']?.toString().toLowerCase().trim() ?? '';
        return expr == 'true' || expr == '1';
      case 'sense_object_detected':
        final detected = _visionService.isObjectDetected;
        // Establish a tracking lock so targetOffsetX/targetArea are valid
        // for steering blocks in the same loop body.
        if (detected && !_visionService.isLocked) {
          _visionService.autoLockOnBestDetection();
        }
        return detected;
      case 'sense_object_locked':
        final targetType = (block.inputValues['target'] ?? 'person').toString().toLowerCase();
        if (!_visionService.isLocked || _visionService.targetLabel.toLowerCase() != targetType) {
          _visionService.autoLockOnLabel(targetType);
        }
        return _visionService.isLocked && _visionService.targetLabel.toLowerCase() == targetType;
      case 'sense_locked':
        return _visionService.isLocked;
      case 'sense_shake':
        return _sensorService.isShaking;
      case 'sense_tilt':
        return _sensorService.isTilted;
      case 'sense_line_detected':
        return _visionService.lineDetected;
      case 'sense_rotating':
        return _sensorService.isRotating;
      case 'sense_facing':
        final dir = (block.inputValues['direction'] ?? 'North').toString();
        const directionDegrees = {
          'North': 0.0, 'Northeast': 45.0, 'East': 90.0, 'Southeast': 135.0,
          'South': 180.0, 'Southwest': 225.0, 'West': 270.0, 'Northwest': 315.0,
        };
        return _sensorService.isFacing(directionDegrees[dir] ?? 0.0);
      case 'sense_loud':
        return _voice.isLoud;
      case 'sense_voice':
        final phrase = block.inputValues['phrase']?.toString() ?? '';
        if (ScriptUtils.matchesPhrase(_voice.lastWords, phrase)) {
          _voice.consume(); // so it doesn't trigger again continuously
          return true;
        }
        return false;
      case 'bool_and':
        final left = block.nestedBlocks['left'];
        final right = block.nestedBlocks['right'];
        return (left != null && _evaluateBoolean(left)) &&
            (right != null && _evaluateBoolean(right));
      case 'bool_or':
        final left = block.nestedBlocks['left'];
        final right = block.nestedBlocks['right'];
        return (left != null && _evaluateBoolean(left)) ||
            (right != null && _evaluateBoolean(right));
      case 'bool_not':
        final value = block.nestedBlocks['value'];
        return value != null ? !_evaluateBoolean(value) : false;
      case 'math_less_than':
        return _numOrZero(block.nestedBlocks['left']) < _numOrZero(block.nestedBlocks['right']);
      case 'math_greater_than':
        return _numOrZero(block.nestedBlocks['left']) > _numOrZero(block.nestedBlocks['right']);
      case 'math_equals':
        return (_numOrZero(block.nestedBlocks['left']) - _numOrZero(block.nestedBlocks['right'])).abs() < 1e-9;
      default:
        return false;
    }
  }

  double _numOrZero(BlockInstance? b) => b == null ? 0.0 : _evaluateNumber(b);

  double _evaluateNumber(BlockInstance block) {
    switch (block.definition.id) {
      case 'sense_offset_x':
        return _visionService.targetOffsetX;
      case 'sense_offset_y':
        return _visionService.targetOffsetY;
      case 'sense_target_size':
        return _visionService.targetArea;
      case 'sense_rotation_rate':
        return _sensorService.rotationRateDegS;
      case 'sense_tilt_angle_x':
        return _sensorService.tiltX;
      case 'sense_tilt_angle_y':
        return _sensorService.tiltY;
      case 'sense_line_offset_x':
        return _visionService.lineOffsetX;
      case 'sense_heading':
        return _sensorService.compassHeading;
      case 'math_number':
        return ScriptUtils.toDouble(block.inputValues['value'], 0.0);
      case 'math_random':
        var lo = ScriptUtils.toInt(block.inputValues['from'], 1);
        var hi = ScriptUtils.toInt(block.inputValues['to'], 10);
        if (lo > hi) (lo, hi) = (hi, lo);
        return (lo + _random.nextInt(hi - lo + 1)).toDouble();
      case 'math_add':
        return _numOrZero(block.nestedBlocks['left']) + _numOrZero(block.nestedBlocks['right']);
      case 'math_subtract':
        return _numOrZero(block.nestedBlocks['left']) - _numOrZero(block.nestedBlocks['right']);
      case 'math_multiply':
        return _numOrZero(block.nestedBlocks['left']) * _numOrZero(block.nestedBlocks['right']);
      case 'math_divide':
        final divisor = block.nestedBlocks['right'] == null ? 1.0 : _numOrZero(block.nestedBlocks['right']);
        return _numOrZero(block.nestedBlocks['left']) / (divisor == 0 ? 1.0 : divisor);
      default:
        return ScriptUtils.toDouble(block.inputValues['value'], 0.0);
    }
  }

  Future<void> _executeActuatorBlock(BlockInstance block, _Run run) async {
    final blockId = block.definition.id;

    if (blockId == 'act_print') {
      final valueBlock = block.nestedBlocks['value'];
      final value = valueBlock != null ? _evaluateNumber(valueBlock) : 0.0;
      _logger.log("🖨️ ${value.toStringAsFixed(2)}");
      return;
    }

    if (blockId == 'act_say') {
      final text = block.inputValues['text']?.toString() ?? '';
      if (text.trim().isEmpty) return;
      _logger.log("💬 \"$text\"");
      await _voice.say(text);
      return;
    }

    // Smart Follow — native controller; handled before generic actuator
    // parsing because it does not map to a single ActuatorConfig entry.
    if (blockId == 'act_smart_follow') {
      await _executeSmartFollow(block, run);
      return;
    }

    final parts = blockId.split('_');
    if (parts.length < 3) return;

    final String actuatorId = blockId.startsWith('act_servo_track_x_')
        ? blockId.substring('act_servo_track_x_'.length)
        : parts.sublist(2).join('_');

    final actuator = _actuatorService.getActuator(actuatorId);
    if (actuator == null) {
      _logger.log("⚠️ Actuator not found: $actuatorId (block: $blockId)");
      return;
    }

    switch (actuator.type) {
      case ActuatorType.led:
        final action = (block.inputValues['state'] ?? 'ON').toString();
        if (action == 'TOGGLE') {
          await _driver.toggle(actuator);
        } else {
          await _driver.setDigital(actuator, action == 'ON');
        }
        break;

      case ActuatorType.motor:
        final direction = (block.inputValues['direction'] ?? 'FORWARD').toString();
        final speed = ScriptUtils.toInt(block.inputValues['speed'], 128);
        await _driver.driveMotor(actuator, direction, speed);
        break;

      case ActuatorType.servo:
        if (blockId.startsWith('act_servo_track_x_')) {
          final multi = ScriptUtils.toDouble(block.inputValues['multiplier'], 90.0);
          final offset = _visionService.targetOffsetX; // -1 .. +1
          await _driver.servoAngle(actuator, ((offset * -multi) + 90).round());
        } else if (actuator.isContinuous) {
          final direction = (block.inputValues['direction'] ?? 'STOP').toString();
          final pct = ScriptUtils.toInt(block.inputValues['speed'], 75);
          await _driver.servoContinuous(actuator, direction, pct);
        } else {
          final angleBlock = block.nestedBlocks['angle'];
          final raw = angleBlock != null
              ? _evaluateNumber(angleBlock)
              : ScriptUtils.toDouble(block.inputValues['angle'], 90.0);
          await _driver.servoAngle(actuator, raw.round());
        }
        break;

      case ActuatorType.buzzer:
      case ActuatorType.switchPin:
        final stateStr = (block.inputValues['state'] ?? 'ON').toString();
        await _driver.setDigital(actuator, stateStr == 'ON');
        break;
    }
  }

  // ── Smart Follow: native pulsed bang-bang follower ─────────────────────────
  //
  // Tight control loop for object tracking. Bypasses block interpretation
  // (no IF chains, no per-block yields) so reaction time is ~1 frame.
  //
  // Uses the first two motors registered in ActuatorService as left + right.
  // Half H-bridge compatible (FORWARD-only — drops in2 if unconfigured).
  Future<void> _executeSmartFollow(BlockInstance block, _Run run) async {
    final mode = (block.inputValues['mode'] ?? 'FETCH').toString().toUpperCase();
    final baseSpeed = ScriptUtils.toInt(block.inputValues['baseSpeed'], 100).clamp(0, 255);
    final arrivedPct = ScriptUtils.toDouble(block.inputValues['arrivedPct'], 30.0);
    // Flip sign of offset so all downstream logic (search spin, correction)
    // reverses consistently. Covers swapped motor wiring, inverted mount, etc.
    final steerSign = (block.inputValues['steering'] ?? 'NORMAL').toString() == 'REVERSED' ? -1.0 : 1.0;

    // Pulsed drive: drive for pulseMs, coast for pauseMs so momentum dies and
    // the camera gets a stable frame. Overridable through inputValues.
    final int pulseMs = ScriptUtils.toInt(block.inputValues['pulseMs'], 60).clamp(10, 1000);
    final int pauseMs = ScriptUtils.toInt(block.inputValues['pauseMs'], 80).clamp(0, 1000);
    final double deadzone = ScriptUtils.toDouble(block.inputValues['deadzone'], 0.20).clamp(0.0, 1.0);

    final motors = _actuatorService.actuators.where((a) => a.type == ActuatorType.motor).toList();
    if (motors.length < 2) {
      _logger.log("⚠️ Smart Follow needs 2 motors configured");
      return;
    }
    final leftM = motors[0];
    final rightM = motors[1];
    if (leftM.parameters['in1'] == null || rightM.parameters['in1'] == null) {
      _logger.log("⚠️ Smart Follow: motor in1 pins not configured");
      return;
    }

    double lastOffsetSign = 1; // default search direction: right

    Future<void> drive(int left, int right) async {
      await _driver.driveMotor(leftM, left > 0 ? 'FORWARD' : 'STOP', left);
      await _driver.driveMotor(rightM, right > 0 ? 'FORWARD' : 'STOP', right);
    }

    Future<void> stopMotors() => drive(0, 0);

    _logger.log("🎯 Smart Follow [$mode]: base=$baseSpeed arrived=$arrivedPct%");

    try {
      while (run.active) {
        final detected = _visionService.isObjectDetected;
        if (detected && !_visionService.isLocked) {
          _visionService.autoLockOnBestDetection();
        }

        if (!detected) {
          if (mode == 'FOLLOW') {
            // Stay still and wait for the target to reappear.
            await stopMotors();
            await Future.delayed(Duration(milliseconds: pulseMs + pauseMs));
            continue;
          }
          // FETCH: pivot toward the direction we last saw the target.
          if (lastOffsetSign >= 0) {
            await drive(baseSpeed, 0);
          } else {
            await drive(0, baseSpeed);
          }
          await Future.delayed(Duration(milliseconds: pulseMs));
          await stopMotors();
          await Future.delayed(Duration(milliseconds: pauseMs));
          continue;
        }

        final area = _visionService.targetArea; // 0..100
        if (area > arrivedPct) {
          await stopMotors();
          _logger.log("🎯 Arrived (size=${area.toStringAsFixed(1)}%)");
          break;
        }

        final rawOffset = _visionService.targetOffsetX * steerSign; // -1..+1
        if (rawOffset.abs() > 0.05) {
          lastOffsetSign = rawOffset.sign;
        }

        if (rawOffset > deadzone) {
          await drive(baseSpeed, 0); // target right → steer right
        } else if (rawOffset < -deadzone) {
          await drive(0, baseSpeed); // target left → steer left
        } else {
          await drive(baseSpeed, baseSpeed);
        }

        await Future.delayed(Duration(milliseconds: pulseMs));
        await stopMotors();
        await Future.delayed(Duration(milliseconds: pauseMs));
      }
    } finally {
      await stopMotors();
    }
  }
}
