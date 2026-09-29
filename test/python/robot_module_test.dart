import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:do_robotics/logic/actuator_driver.dart';
import 'package:do_robotics/logic/block_script_runner.dart' show ExecutionState;
import 'package:do_robotics/logic/python_script_runner.dart';
import 'package:do_robotics/logic/robot_api.dart';
import 'package:do_robotics/models/actuator_config.dart';
import 'package:do_robotics/python/interpreter.dart';
import 'package:do_robotics/python/robot_module.dart';
import 'package:do_robotics/python/values.dart';

/// Records every call so tests can assert on robot behaviour without hardware.
class FakeRobotApi implements RobotApi {
  final List<String> calls = [];
  bool detected = false;
  double offX = 0;
  double sz = 0;
  String lastWords = '';
  bool loud = false;
  double head = 0;

  @override
  final List<ActuatorConfig> actuators = [
    ActuatorConfig(id: 'm1', name: 'Left Wheel', type: ActuatorType.motor, pin: 5, parameters: {'in1': 7}),
    ActuatorConfig(id: 'm2', name: 'Right Wheel', type: ActuatorType.motor, pin: 6, parameters: {'in1': 8}),
    ActuatorConfig(id: 'l1', name: 'Headlight', type: ActuatorType.led, pin: 13),
    ActuatorConfig(id: 's1', name: 'Arm', type: ActuatorType.servo, pin: 9, parameters: {'minAngle': 0, 'maxAngle': 180}),
  ];

  // ActuatorDriver talks to ConnectivityManager, which is inert without a
  // transport, so we can use the real driver and just observe its logging by
  // recording calls in our own wrapper methods below.
  @override
  ActuatorDriver get driver => ActuatorDriver();
  @override
  bool get connected => false;

  @override
  Future<void> ensureVision({bool lineMode = false}) async => calls.add('vision:${lineMode ? 'line' : 'obj'}');
  @override
  Future<void> ensureMic() async => calls.add('mic');
  @override
  bool get visionDetected => detected;
  @override
  bool visionLock(String label) {
    calls.add('lock:$label');
    return detected;
  }

  @override
  bool get visionLocked => detected;
  @override
  String get visionLabel => detected ? 'person' : '';
  @override
  double get offsetX => offX;
  @override
  double get offsetY => 0;
  @override
  double get size => sz;
  @override
  List<String> get objects => detected ? ['person'] : [];
  @override
  bool get lineVisible => false;
  @override
  double get lineOffset => 0;
  @override
  void visionUnlock() => calls.add('unlock');
  @override
  double get pitch => 10;
  @override
  double get roll => -5;
  @override
  double get yawRate => 0;
  @override
  bool get shaking => false;
  @override
  bool get tilted => false;
  @override
  bool get spinning => false;
  @override
  double get heading => head;
  @override
  bool facing(double degrees) {
    calls.add('facing:$degrees');
    return (head - degrees).abs() < 22.5;
  }

  @override
  bool get micLoud => loud;
  @override
  bool heard(String phrase) {
    calls.add('heard:$phrase');
    final hit = lastWords.contains(phrase);
    if (hit) lastWords = '';
    return hit;
  }

  @override
  String get words => lastWords;
  @override
  Future<void> say(String text) async => calls.add('say:$text');
  @override
  Future<void> shutdown() async => calls.add('shutdown');
}

Future<(List<String>, FakeRobotApi)> runRobot(String src) async {
  final out = <String>[];
  final api = FakeRobotApi();
  final interp = Interpreter(onPrint: out.add);
  interp.globals.vars['robot'] = buildRobotModule(api, interp, log: out.add);
  await interp.run(src);
  return (out, api);
}

void main() {
  test('the Python example in README.md runs against the robot API', () async {
    // Keeps the README honest: extract every ```python block and run it with
    // a fake robot that sees a close person, so the sample's loop ends.
    final readme = File('README.md').readAsStringSync();
    final samples = RegExp(r'```python\n([\s\S]*?)```').allMatches(readme).map((m) => m.group(1)!).toList();
    expect(samples, isNotEmpty);
    for (final src in samples) {
      final out = <String>[];
      final api = FakeRobotApi()
        ..detected = true
        ..sz = 45;
      final interp = Interpreter(onPrint: out.add);
      interp.globals.vars['robot'] = buildRobotModule(api, interp, log: out.add);
      await interp.run(src).timeout(const Duration(seconds: 5));
      expect(api.calls, contains('say:Found you'));
    }
  });

  test('actuators resolve by name, case-insensitively, with helpful errors', () async {
    final (out, _) = await runRobot('''
import robot
left = robot.motor("left wheel")
print(left.name, left.pin, robot.actuators)
left.forward(200)
left.stop()
robot.led("Headlight").on()
robot.servo("Arm").angle(45)
''');
    expect(out.first, "Left Wheel 5 ['Left Wheel', 'Right Wheel', 'Headlight', 'Arm']");

    final (motorsOut, _) = await runRobot('import robot\nprint(robot.motors)\n');
    expect(motorsOut.first, "['Left Wheel', 'Right Wheel']");

    await expectLater(
      runRobot('import robot\nrobot.motor("nope")\n'),
      throwsA(isA<PyRuntimeError>().having((e) => e.message, 'message', contains('Configured: "Left Wheel"'))),
    );
    await expectLater(
      runRobot('import robot\nrobot.motor("Headlight")\n'),
      throwsA(isA<PyRuntimeError>().having((e) => e.message, 'message', contains('is a LED, not a Motor'))),
    );
  });

  test('vision getters start the camera lazily and expose tracking values', () async {
    final (out, api) = await runRobot('''
import robot
if robot.vision.detected:
    print("seen")
else:
    print("nothing")
print(robot.vision.lock("person"), robot.vision.offset_x, robot.vision.objects)
''');
    expect(out, ['nothing', 'False 0.0 []']);
    expect(api.calls.first, 'vision:obj');
    expect(api.calls, contains('lock:person'));
  });

  test('line following getters start line mode', () async {
    final (_, api) = await runRobot('import robot\nx = robot.vision.line_offset\n');
    expect(api.calls, ['vision:line']);
  });

  test('mic, compass, say and log', () async {
    final (out, api) = await runRobot('''
import robot
robot.say("hello")
print(robot.mic.heard("go"), robot.compass.facing("East"), robot.compass.facing(90))
robot.log("done", 1)
''');
    expect(api.calls, containsAll(['say:hello', 'mic', 'heard:go', 'facing:90.0']));
    expect(out, ['False False False', 'done 1']);
  });

  test('robot.stop() ends the program without error', () async {
    final (out, _) = await runRobot('import robot\nprint("a")\nrobot.stop()\nprint("b")\n');
    expect(out, ['a']);
  });

  test('PythonScriptRunner: a second RUN or a STOP during start-up never starts a stray run', () async {
    final runner = PythonScriptRunner();
    final apis = <FakeRobotApi>[];
    runner.apiFactory = () {
      final api = FakeRobotApi();
      apis.add(api);
      return api;
    };
    // A run that is stopped leaves a teardown the next start must wait for.
    final first = runner.run('import robot\nrobot.wait(5)\n');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    runner.stop();
    await first;

    // Double-tap RUN: exactly one new run.
    final a = runner.run('import robot\nrobot.wait(0.2)\n');
    final b = runner.run('import robot\nrobot.wait(0.2)\n');
    await Future.wait([a, b]);
    expect(apis, hasLength(2));

    // STOP right after RUN, while it waits for the teardown: nothing runs.
    final c = runner.run('import robot\nrobot.say("should not run")\n');
    runner.stop();
    await c;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(runner.state, ExecutionState.idle);
    expect(apis.expand((a) => a.calls), isNot(contains('say:should not run')));
  });

  test('robot.wait is cancellable', () async {
    final api = FakeRobotApi();
    final cancel = CancelToken();
    final interp = Interpreter(onPrint: (_) {}, cancel: cancel);
    interp.globals.vars['robot'] = buildRobotModule(api, interp);
    final f = interp.run('import robot\nrobot.wait(30)\n');
    await Future.delayed(const Duration(milliseconds: 20));
    cancel.cancel();
    await expectLater(f, throwsA(isA<PyCancelled>()));
  });
}
