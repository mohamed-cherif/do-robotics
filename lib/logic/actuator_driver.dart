import '../models/actuator_config.dart';
import '../services/connectivity/connectivity_manager.dart';
import '../services/connectivity/robot_protocol.dart';
import '../utils/execution_logger.dart';

/// Translates high-level actuator intents (motor forward at 200, servo to
/// 90°) into protocol packets, with per-pin de-duplication so an unchanged
/// value is never re-sent. Shared by the block runner and the Python runner.
class ActuatorDriver {
  static final ActuatorDriver _instance = ActuatorDriver._internal();
  factory ActuatorDriver() => _instance;
  ActuatorDriver._internal();

  final ConnectivityManager _connectivity = ConnectivityManager();
  final ExecutionLogger _logger = ExecutionLogger();

  /// Last value sent per key ("pin_9", "pwm_5", or an actuator id).
  final Map<String, int> _states = {};

  /// Forget every cached value (call at program start and after stop-all).
  void reset() => _states.clear();

  Future<void> _send(int cmd, int pin, int value) =>
      _connectivity.sendCommand(cmd, pin, value.clamp(0, 255));

  Future<void> _writePin(int pin, int value) async {
    if (_states['pin_$pin'] == value) return;
    _states['pin_$pin'] = value;
    await _send(RobotProtocol.cmdDigitalWrite, pin, value);
  }

  Future<void> _writePwm(int pin, int value) async {
    if (_states['pwm_$pin'] == value) return;
    _states['pwm_$pin'] = value;
    await _send(RobotProtocol.cmdAnalogWrite, pin, value);
  }

  // ── Raw pin access (Python `robot.pin.*`) ──────────────────────────────────

  Future<void> rawDigital(int pin, int value) => _writePin(pin, value == 0 ? 0 : 1);
  Future<void> rawPwm(int pin, int value) => _writePwm(pin, value);
  Future<void> rawServo(int pin, int angle) =>
      _send(RobotProtocol.cmdServoWrite, pin, angle.clamp(0, 180));

  // ── LED / buzzer / switch ─────────────────────────────────────────────────

  bool isOn(ActuatorConfig a) => (_states[a.id] ?? 0) != 0;

  Future<void> setDigital(ActuatorConfig a, bool on) async {
    final v = on ? 1 : 0;
    if (_states[a.id] == v) return;
    _states[a.id] = v;
    _logger.log("${a.type == ActuatorType.led ? '💡' : a.type == ActuatorType.buzzer ? '🔊' : '🔌'} ${a.name}: ${on ? 'ON' : 'OFF'}");
    await _send(RobotProtocol.cmdDigitalWrite, a.pin, v);
  }

  Future<void> toggle(ActuatorConfig a) => setDigital(a, !isOn(a));

  // ── Motors ────────────────────────────────────────────────────────────────

  /// [direction] is FORWARD, BACKWARD or STOP; [speed] 0..255.
  Future<void> driveMotor(ActuatorConfig a, String direction, int speed) async {
    var dir = direction.toUpperCase();
    if (a.invertedDirection && dir != 'STOP') {
      dir = dir == 'FORWARD' ? 'BACKWARD' : 'FORWARD';
    }
    final maxSpeed = a.maxSpeed.clamp(0, 255);
    final s = dir == 'STOP' ? 0 : speed.clamp(0, maxSpeed);
    _logger.log("⚙️ ${a.name}: $dir @ $s");

    final in1 = a.parameters['in1'] as int?;
    final in2 = a.parameters['in2'] as int?;

    if (in1 == null && in2 == null) {
      // PWM-only motor: no direction pins, reverse impossible.
      if (dir == 'BACKWARD') {
        _logger.log("ℹ️ ${a.name}: no direction pins, BACKWARD → FORWARD");
      }
      await _writePwm(a.pin, s);
      return;
    }
    if (in1 != null) await _writePin(in1, (s > 0 && dir == 'FORWARD') ? 1 : 0);
    if (in2 != null) await _writePin(in2, (s > 0 && dir == 'BACKWARD') ? 1 : 0);
    await _writePwm(a.pin, s);
  }

  // ── Servos ────────────────────────────────────────────────────────────────

  Future<void> servoAngle(ActuatorConfig a, int angle) async {
    final minA = a.minAngle.clamp(0, 180);
    final maxA = a.maxAngle.clamp(minA, 180);
    final v = angle.clamp(minA, maxA);
    if (_states[a.id] == v) return;
    _states[a.id] = v;
    _logger.log("🔄 ${a.name}: angle $v°");
    await _send(RobotProtocol.cmdServoWrite, a.pin, v);
  }

  /// Continuous-rotation servo. [direction] FORWARD/BACKWARD/STOP, [percent] 0..100.
  Future<void> servoContinuous(ActuatorConfig a, String direction, int percent) async {
    var dir = direction.toUpperCase();
    if (a.invertedDirection && dir != 'STOP') {
      dir = dir == 'FORWARD' ? 'BACKWARD' : 'FORWARD';
    }
    final stopVal = RobotProtocol.usToServoValue(a.continuousStopPwm);
    final pct = percent.clamp(0, 100);
    final int v;
    if (dir == 'STOP') {
      v = stopVal;
    } else if (dir == 'FORWARD') {
      v = (stopVal + pct).clamp(0, 200);
    } else {
      v = (stopVal - pct).clamp(0, 200);
    }
    if (_states[a.id] == v) return;
    _states[a.id] = v;
    _logger.log("🔄 ${a.name}: ${RobotProtocol.servoValueToUs(v)} µs");
    await _send(RobotProtocol.cmdServoWriteUs, a.pin, v);
  }

  // ── Stop everything ───────────────────────────────────────────────────────

  Future<void> stopAll(Iterable<ActuatorConfig> actuators) async {
    _states.clear();
    for (final a in actuators) {
      try {
        switch (a.type) {
          case ActuatorType.led:
          case ActuatorType.buzzer:
          case ActuatorType.switchPin:
            await _send(RobotProtocol.cmdDigitalWrite, a.pin, 0);
            break;
          case ActuatorType.motor:
            final in1 = a.parameters['in1'] as int?;
            final in2 = a.parameters['in2'] as int?;
            if (in1 != null) await _send(RobotProtocol.cmdDigitalWrite, in1, 0);
            if (in2 != null) await _send(RobotProtocol.cmdDigitalWrite, in2, 0);
            await _send(RobotProtocol.cmdAnalogWrite, a.pin, 0);
            break;
          case ActuatorType.servo:
            if (a.isContinuous) {
              await _send(RobotProtocol.cmdServoWriteUs, a.pin,
                  RobotProtocol.usToServoValue(a.continuousStopPwm));
            }
            break;
        }
      } catch (e) {
        _logger.log("⚠️ Error stopping ${a.name}: $e");
      }
    }
    // Firmware-side stop of every pin it has ever driven.
    await _connectivity.stopAll();
    _states.clear();
  }
}
