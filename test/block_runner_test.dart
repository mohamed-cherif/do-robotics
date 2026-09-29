import 'dart:async';

import 'package:do_robotics/logic/block_script_runner.dart';
import 'package:do_robotics/models/block_factory.dart';
import 'package:do_robotics/models/block_models.dart';
import 'package:do_robotics/utils/execution_logger.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Block-runner lifecycle tests. They only use logic and Print blocks, so no
/// camera, microphone or robot link is involved.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // sensors_plus is started by every run; answer its platform calls.
  const sensorMethods = MethodChannel('dev.fluttercommunity.plus/sensors/method');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(sensorMethods, (_) async => null);

  final defs = BlockFactory.getAllStaticBlocks();
  BlockDefinition def(String id) => defs.firstWhere((d) => d.id == id);
  var n = 0;
  BlockInstance block(String id,
          {Map<String, dynamic>? inputs, Map<String, BlockInstance?>? nested, BlockInstance? next}) =>
      BlockInstance(
          instanceId: '${id}_${n++}',
          definition: def(id),
          inputValues: inputs,
          nestedBlocks: nested,
          nextBlock: next);
  BlockInstance print(num v, {BlockInstance? next}) => block('act_print',
      nested: {'value': block('math_number', inputs: {'value': v})}, next: next);

  final runner = BlockScriptRunner();
  final logger = ExecutionLogger();
  List<String> printed() => logger.logs
      .where((l) => l.contains('🖨️'))
      .map((l) => l.split('🖨️ ').last)
      .toList();

  tearDown(() async {
    runner.stop();
    // Let the teardown (stop-all) finish before the next test.
    await Future.delayed(const Duration(milliseconds: 250));
  });

  test('blocks run in chain order, including nested then-branches', () async {
    runner.loadScript([
      block('logic_if',
          nested: {'condition': block('bool_true'), 'then': print(1, next: print(2))},
          next: print(3)),
    ]);
    await runner.play();
    expect(printed(), ['1.00', '2.00', '3.00']);
    expect(runner.state, ExecutionState.idle);
  });

  test('Stop Program ends the chain', () async {
    runner.loadScript([print(1, next: block('logic_stop', next: print(2)))]);
    await runner.play();
    expect(printed(), ['1.00']);
  });

  test('double-tapping RUN starts exactly one run', () async {
    runner.loadScript([block('logic_wait', inputs: {'seconds': 0.2}, next: print(7))]);
    final first = runner.play();
    final second = runner.play(); // second tap before the first run started
    await Future.wait([first, second]);
    expect(logger.logs.where((l) => l.contains('Program started')), hasLength(1));
    expect(printed(), ['7.00']);
  });

  test('STOP interrupts a Repeat whose body never waits', () async {
    // 10^8 iterations of pure computation. Before the fix the loop never
    // yielded to the event loop, so STOP (and the UI) could not run.
    runner.loadScript([
      block('logic_repeat', inputs: {'times': 10000}, nested: {
        'do': block('logic_repeat', inputs: {'times': 10000}, nested: {'do': print(1)}),
      }),
    ]);
    final run = runner.play();
    Timer(const Duration(milliseconds: 100), runner.stop);
    await run.timeout(const Duration(seconds: 5));
    expect(runner.state, ExecutionState.idle);
  });

  test('rapid RUN/STOP cycles never throw and always end idle', () async {
    runner.loadScript([
      block('logic_forever', nested: {'do': block('logic_wait', inputs: {'seconds': 0.05})}),
    ]);
    for (var i = 0; i < 20; i++) {
      unawaited(runner.play());
      await Future<void>.delayed(Duration(milliseconds: i.isEven ? 1 : 30));
      runner.stop();
    }
    // Let every teardown finish, then check nothing is still running.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(runner.state, ExecutionState.idle);
  });

  group('new blocks', () {
    BlockInstance number(num v) => block('math_number', inputs: {'value': v});

    test('Repeat Until stops as soon as the condition is true', () async {
      runner.loadScript([
        block('logic_repeat_until', nested: {'condition': block('bool_true'), 'do': print(1)}, next: print(2)),
      ]);
      await runner.play();
      expect(printed(), ['2.00']);
    });

    test('Forever repeats until Stop Program', () async {
      runner.loadScript([
        block('logic_forever', nested: {'do': print(1, next: block('logic_stop'))}),
      ]);
      await runner.play().timeout(const Duration(seconds: 5));
      expect(printed(), ['1.00']);
    });

    test('Equals compares numbers', () async {
      BlockInstance ifEq(num a, num b, int out) => block('logic_if', nested: {
            'condition': block('math_equals', nested: {'left': number(a), 'right': number(b)}),
            'then': print(out),
          });
      runner.loadScript([ifEq(2, 2, 1)..nextBlock = ifEq(2, 3, 2)]);
      await runner.play();
      expect(printed(), ['1.00']);
    });

    test('Random stays inside its range (either order)', () async {
      BlockInstance printRandom(int from, int to) => block('act_print', nested: {
            'value': block('math_random', inputs: {'from': from, 'to': to}),
          });
      runner.loadScript([
        block('logic_repeat', inputs: {'times': 30}, nested: {
          'do': printRandom(3, 7)..nextBlock = printRandom(9, 9),
        }),
      ]);
      await runner.play();
      final values = printed().map(double.parse).toList();
      expect(values, hasLength(60));
      expect(values.where((v) => v != 9), everyElement(inInclusiveRange(3, 7)));
      expect(values.where((v) => v == 9), hasLength(30));
    });
  });
}
