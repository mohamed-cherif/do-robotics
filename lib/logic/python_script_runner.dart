import 'dart:async';

import '../python/interpreter.dart';
import '../python/lexer.dart';
import '../python/parser.dart';
import '../python/robot_module.dart';
import '../python/values.dart';
import '../utils/execution_logger.dart';
import 'block_script_runner.dart' show ExecutionState, BlockScriptRunner;
import 'robot_api.dart';

/// Runs RoboPython source with the same lifecycle as the block runner:
/// start subsystems, execute, stop everything, release the camera and mic.
class PythonScriptRunner {
  static final PythonScriptRunner _instance = PythonScriptRunner._internal();
  factory PythonScriptRunner() => _instance;
  PythonScriptRunner._internal();

  /// Override for tests.
  RobotApi Function() apiFactory = LiveRobotApi.new;

  final ExecutionLogger _logger = ExecutionLogger();
  final StreamController<ExecutionState> _stateController = StreamController.broadcast();
  final StreamController<int> _lineController = StreamController.broadcast();

  Stream<ExecutionState> get stateStream => _stateController.stream;
  /// Source line currently executing (1-based), -1 when idle. Throttled.
  Stream<int> get lineStream => _lineController.stream;

  ExecutionState _state = ExecutionState.idle;
  ExecutionState get state => _state;
  CancelToken? _cancel;
  RobotApi? _api;
  Future<void>? _teardown;
  bool _starting = false;
  bool _startCancelled = false;
  int _lastEmittedLine = -1;
  DateTime _lastLineEmit = DateTime.fromMillisecondsSinceEpoch(0);

  void _setState(ExecutionState s) {
    _state = s;
    _stateController.add(s);
  }

  /// Checks syntax without running. Returns null when OK, else "line N: msg".
  static String? check(String source) {
    try {
      Parser.parse(source);
      return null;
    } on PySyntaxError catch (e) {
      return e.toString();
    } catch (e) {
      // The Run button calls this first; nothing may escape it.
      return 'cannot check this program: $e';
    }
  }

  Future<void> run(String source) async {
    if (_state == ExecutionState.running || _starting) return;
    if (BlockScriptRunner().state == ExecutionState.running) {
      _logger.log("⚠️ A block program is already running");
      return;
    }
    // Wait for the previous run's teardown. _starting makes a second RUN
    // during this wait a no-op; stop() during it cancels this start.
    _starting = true;
    _startCancelled = false;
    try {
      await _teardown;
    } finally {
      _starting = false;
    }
    if (_startCancelled) return;

    _logger.clear();
    _logger.log("🐍 Python program started");
    _setState(ExecutionState.running);

    final api = apiFactory();
    _api = api;
    api.driver.reset();
    final cancel = CancelToken();
    _cancel = cancel;

    final interp = Interpreter(
      onPrint: _logger.log,
      onLine: _emitLine,
      cancel: cancel,
    );
    interp.globals.vars['robot'] = buildRobotModule(api, interp, log: _logger.log);

    try {
      // Pre-warm subsystems the program obviously uses so the first loop
      // iteration is not delayed by camera / mic start-up.
      if (source.contains('vision.')) {
        await api.ensureVision(
            lineMode: source.contains('line_visible') || source.contains('line_offset'));
      }
      if (source.contains('mic.')) {
        await api.ensureMic();
      }
      if (cancel.isCancelled) throw const PyCancelled();

      await interp.run(source);
      if (!cancel.isCancelled) _logger.log("🏁 Program finished");
    } on PySyntaxError catch (e) {
      _logger.log("❌ Syntax error, $e");
    } on PyRuntimeError catch (e) {
      _logger.log("❌ Error, $e");
    } on PyCancelled {
      // stopped by user
    } catch (e, st) {
      _logger.log("💥 Runtime error: $e");
      _logger.log(st.toString().split('\n').first);
    } finally {
      // Only finish *this* run. After a forced stop the user may already have
      // started a new run; finishing that one would mark it idle while its
      // interpreter keeps driving the motors.
      if (identical(_cancel, cancel) && _state == ExecutionState.running) _finish();
    }
  }

  void _emitLine(int line) {
    final now = DateTime.now();
    if (line == _lastEmittedLine) return;
    if (now.difference(_lastLineEmit).inMilliseconds < 40) return;
    _lastEmittedLine = line;
    _lastLineEmit = now;
    _lineController.add(line);
  }

  /// Stops a running program, or cancels one that is still starting. Safe to
  /// call when idle.
  void stop() {
    if (_starting) _startCancelled = true;
    if (_state != ExecutionState.running) return;
    _logger.log("⏹️ Program stopped");
    final token = _cancel;
    token?.cancel();
    // run()'s finally calls _finish once the interpreter unwinds. If a native
    // call ignores cancellation, force the stop after a grace period.
    Future.delayed(const Duration(milliseconds: 500), () {
      if (identical(_cancel, token) && _state == ExecutionState.running) _finish();
    });
  }

  void _finish() {
    final api = _api;
    _api = null;
    _setState(ExecutionState.idle);
    _lastEmittedLine = -1;
    _lineController.add(-1);
    _teardown = () async {
      if (api != null) {
        await api.driver.stopAll(api.actuators);
        await api.shutdown();
      }
    }();
  }
}
