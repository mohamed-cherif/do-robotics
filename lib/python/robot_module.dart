/// Builds the `robot` Python module over a [RobotApi].
library;

import '../logic/robot_api.dart';
import '../models/actuator_config.dart';
import 'interpreter.dart';
import 'values.dart';

const Map<String, double> _compassPoints = {
  'north': 0, 'northeast': 45, 'east': 90, 'southeast': 135,
  'south': 180, 'southwest': 225, 'west': 270, 'northwest': 315,
  'n': 0, 'ne': 45, 'e': 90, 'se': 135, 's': 180, 'sw': 225, 'w': 270, 'nw': 315,
};

PyObject buildRobotModule(RobotApi api, Interpreter interp, {void Function(String)? log}) {
  final robot = PyObject('module robot');

  ActuatorConfig find(String name, {ActuatorType? type}) {
    final n = name.trim().toLowerCase();
    final all = api.actuators;
    ActuatorConfig? found;
    for (final a in all) {
      if (a.name.toLowerCase() == n || a.id == name) {
        found = a;
        break;
      }
    }
    if (found == null) {
      final names = all.map((a) => '"${a.name}"').join(', ');
      throw PyRuntimeError('no actuator named "$name". Configured: ${names.isEmpty ? '(none — add hardware first)' : names}');
    }
    if (type != null && found.type != type) {
      throw PyRuntimeError('"${found.name}" is a ${found.type.displayName}, not a ${type.displayName}');
    }
    return found;
  }

  int argInt(List<Object?> a, int i, int def) => a.length > i ? pyToInt(a[i]) : def;
  double argDouble(List<Object?> a, int i, double def) => a.length > i ? pyToDouble(a[i]) : def;
  String argStr(List<Object?> a, int i, String fn) {
    if (a.length <= i) throw PyRuntimeError('$fn() needs an argument');
    return pyStr(a[i]);
  }

  PyObject motorObj(ActuatorConfig a) {
    final o = PyObject('Motor');
    o.attrs['name'] = a.name;
    o.attrs['pin'] = a.pin;
    o.method('forward', (args, kw) => api.driver.driveMotor(a, 'FORWARD', argInt(args, 0, pyToInt(kw['speed'] ?? 200))));
    o.method('backward', (args, kw) => api.driver.driveMotor(a, 'BACKWARD', argInt(args, 0, pyToInt(kw['speed'] ?? 200))));
    o.method('stop', (args, kw) => api.driver.driveMotor(a, 'STOP', 0));
    // speed(v): positive forward, negative backward, 0 stop
    o.method('speed', (args, kw) {
      final v = argInt(args, 0, 0);
      return api.driver.driveMotor(a, v == 0 ? 'STOP' : (v > 0 ? 'FORWARD' : 'BACKWARD'), v.abs());
    });
    return o;
  }

  PyObject servoObj(ActuatorConfig a) {
    final o = PyObject(a.isContinuous ? 'ContinuousServo' : 'Servo');
    o.attrs['name'] = a.name;
    o.attrs['pin'] = a.pin;
    o.attrs['continuous'] = a.isContinuous;
    o.method('angle', (args, kw) {
      if (a.isContinuous) throw PyRuntimeError('"${a.name}" is a continuous servo; use forward()/backward()/stop()');
      return api.driver.servoAngle(a, argInt(args, 0, 90));
    });
    o.method('forward', (args, kw) => api.driver.servoContinuous(a, 'FORWARD', argInt(args, 0, 75)));
    o.method('backward', (args, kw) => api.driver.servoContinuous(a, 'BACKWARD', argInt(args, 0, 75)));
    o.method('stop', (args, kw) => api.driver.servoContinuous(a, 'STOP', 0));
    return o;
  }

  PyObject switchObj(ActuatorConfig a) {
    final o = PyObject(a.type.displayName);
    o.attrs['name'] = a.name;
    o.attrs['pin'] = a.pin;
    o.method('on', (args, kw) => api.driver.setDigital(a, true));
    o.method('off', (args, kw) => api.driver.setDigital(a, false));
    o.method('toggle', (args, kw) => api.driver.toggle(a));
    o.method('set', (args, kw) => api.driver.setDigital(a, pyTruthy(args.isEmpty ? true : args[0])));
    o.getter('is_on', () => api.driver.isOn(a));
    return o;
  }

  PyObject deviceObj(ActuatorConfig a) {
    switch (a.type) {
      case ActuatorType.motor:
        return motorObj(a);
      case ActuatorType.servo:
        return servoObj(a);
      case ActuatorType.led:
      case ActuatorType.buzzer:
      case ActuatorType.switchPin:
        return switchObj(a);
    }
  }

  robot.method('motor', (a, _) => motorObj(find(argStr(a, 0, 'motor'), type: ActuatorType.motor)));
  robot.method('servo', (a, _) => servoObj(find(argStr(a, 0, 'servo'), type: ActuatorType.servo)));
  robot.method('led', (a, _) => switchObj(find(argStr(a, 0, 'led'), type: ActuatorType.led)));
  robot.method('buzzer', (a, _) => switchObj(find(argStr(a, 0, 'buzzer'), type: ActuatorType.buzzer)));
  robot.method('switch', (a, _) => switchObj(find(argStr(a, 0, 'switch'), type: ActuatorType.switchPin)));
  robot.method('device', (a, _) => deviceObj(find(argStr(a, 0, 'device'))));
  robot.getter('actuators', () => PyList(api.actuators.map((a) => a.name).toList()));
  robot.getter('connected', () => api.connected);

  robot.method('say', (a, _) async {
    await api.say(argStr(a, 0, 'say'));
    return null;
  });
  robot.method('wait', (a, _) async {
    await interp.sleep(argDouble(a, 0, 0));
    return null;
  });
  robot.method('log', (a, _) {
    (log ?? interp.onPrint)(a.map(pyStr).join(' '));
    return null;
  });
  robot.method('stop_all', (a, _) => api.driver.stopAll(api.actuators));
  robot.method('stop', (a, _) => throw const PyExit());

  // ── vision ────────────────────────────────────────────────────────────────
  final vision = PyObject('robot.vision');
  vision.getter('detected', () async {
    await api.ensureVision();
    return api.visionDetected;
  });
  vision.method('lock', (a, _) async {
    await api.ensureVision();
    return api.visionLock(argStr(a, 0, 'lock'));
  });
  vision.getter('locked', () => api.visionLocked);
  vision.getter('label', () => api.visionLabel);
  vision.getter('offset_x', () => api.offsetX);
  vision.getter('offset_y', () => api.offsetY);
  vision.getter('size', () => api.size);
  vision.getter('objects', () async {
    await api.ensureVision();
    return PyList(List<Object?>.from(api.objects));
  });
  vision.getter('line_visible', () async {
    await api.ensureVision(lineMode: true);
    return api.lineVisible;
  });
  vision.getter('line_offset', () async {
    await api.ensureVision(lineMode: true);
    return api.lineOffset;
  });
  vision.method('unlock', (a, _) {
    api.visionUnlock();
    return null;
  });
  vision.method('start', (a, kw) async {
    await api.ensureVision(lineMode: kw['line'] == true);
    return null;
  });
  robot.attrs['vision'] = vision;

  // ── imu / compass ─────────────────────────────────────────────────────────
  final imu = PyObject('robot.imu');
  imu.getter('pitch', () => api.pitch);
  imu.getter('roll', () => api.roll);
  imu.getter('yaw_rate', () => api.yawRate);
  imu.getter('shaking', () => api.shaking);
  imu.getter('tilted', () => api.tilted);
  imu.getter('spinning', () => api.spinning);
  robot.attrs['imu'] = imu;

  final compass = PyObject('robot.compass');
  compass.getter('heading', () => api.heading);
  compass.method('facing', (a, _) {
    if (a.isEmpty) throw PyRuntimeError('facing() needs a direction, e.g. "North" or 90');
    final v = a[0];
    double deg;
    if (v is num) {
      deg = v.toDouble();
    } else {
      final key = pyStr(v).toLowerCase().trim();
      final d = _compassPoints[key];
      if (d == null) throw PyRuntimeError('unknown direction "$v" (use North/East/South/West or degrees)');
      deg = d;
    }
    return api.facing(deg);
  });
  robot.attrs['compass'] = compass;

  // ── mic ───────────────────────────────────────────────────────────────────
  final mic = PyObject('robot.mic');
  mic.getter('loud', () async {
    await api.ensureMic();
    return api.micLoud;
  });
  mic.method('heard', (a, _) async {
    await api.ensureMic();
    return api.heard(argStr(a, 0, 'heard'));
  });
  mic.getter('words', () async {
    await api.ensureMic();
    return api.words;
  });
  mic.method('start', (a, _) async {
    await api.ensureMic();
    return null;
  });
  robot.attrs['mic'] = mic;

  // ── raw pins ──────────────────────────────────────────────────────────────
  final pin = PyObject('robot.pin');
  pin.method('digital', (a, _) => api.driver.rawDigital(argInt(a, 0, 0), argInt(a, 1, 0)));
  pin.method('pwm', (a, _) => api.driver.rawPwm(argInt(a, 0, 0), argInt(a, 1, 0)));
  pin.method('servo', (a, _) => api.driver.rawServo(argInt(a, 0, 0), argInt(a, 1, 90)));
  robot.attrs['pin'] = pin;

  return robot;
}
