// Regression tests for bugs found in the pre-release audit of RoboPython.
import 'dart:async';

import 'package:do_robotics/logic/python_script_runner.dart';
import 'package:do_robotics/python/interpreter.dart';
import 'package:do_robotics/python/lexer.dart';
import 'package:do_robotics/python/values.dart';
import 'package:flutter_test/flutter_test.dart';

/// Result of running a program: printed lines, the error run() threw, and any
/// *uncaught* async errors (these would bypass PythonScriptRunner's try/catch).
class Outcome {
  final List<String> out;
  final Object? error;
  final List<Object> uncaught;
  Outcome(this.out, this.error, this.uncaught);

  int? get line => switch (error) {
        PySyntaxError e => e.line,
        PyRuntimeError e => e.line,
        _ => null,
      };

  @override
  String toString() => 'out=$out error=${error.runtimeType}: $error uncaught=$uncaught';
}

Future<Outcome> run(String src, {CancelToken? cancel}) async {
  final out = <String>[];
  final uncaught = <Object>[];
  Object? error;
  final done = Completer<void>();
  runZonedGuarded(() async {
    try {
      await Interpreter(onPrint: out.add, cancel: cancel).run(src);
    } catch (e) {
      error = e;
    }
    done.complete();
  }, (e, st) => uncaught.add(e));
  await done.future.timeout(const Duration(seconds: 20));
  await Future<void>.delayed(const Duration(milliseconds: 5)); // let stray futures fail
  return Outcome(out, error, uncaught);
}

Future<void> expectOut(String src, List<String> expected) async {
  final o = await run(src);
  expect(o.error, isNull, reason: '$o');
  expect(o.uncaught, isEmpty, reason: '$o');
  expect(o.out, expected, reason: '$o');
}

/// Expects a PySyntaxError / PyRuntimeError that carries a line number.
Future<Outcome> expectPyError(String src, {int? line, Pattern? message}) async {
  final o = await run(src);
  expect(o.error, anyOf(isA<PySyntaxError>(), isA<PyRuntimeError>()), reason: '$o');
  expect(o.line, line ?? isNotNull, reason: '$o');
  expect(o.uncaught, isEmpty, reason: '$o');
  if (message != null) expect('${o.error}', contains(message), reason: '$o');
  return o;
}

// Recursion tests run the interpreter in a zone forked from Zone.root.
// flutter_test runs every test inside a package:stack_trace Chain zone, which
// roughly doubles the Dart frames per await and adds O(depth) bookkeeping, so
// stack-depth behaviour measured there does not match the app (no such zone).
// Errors that escape as *uncaught* async errors are collected, not rethrown.
Future<({bool finished, List<String> out, Object? error, List<String> uncaught})> runInRootZone(
  String src, {
  Duration cancelAfter = const Duration(days: 1),
  Duration giveUpAfter = const Duration(seconds: 15),
}) async {
  final out = <String>[];
  final uncaught = <String>[];
  final cancel = CancelToken();
  Object? error;
  var finished = false;
  Zone.root
      .fork(specification: ZoneSpecification(handleUncaughtError: (self, parent, zone, e, st) {
        uncaught.add('${e.runtimeType}: $e');
      }))
      .run(() async {
    try {
      await Interpreter(onPrint: out.add, cancel: cancel).run(src);
    } catch (e) {
      error = e;
    }
    finished = true;
  });
  final sw = Stopwatch()..start();
  while (!finished && sw.elapsed < giveUpAfter) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (sw.elapsed >= cancelAfter) cancel.cancel();
  }
  return (finished: finished, out: out, error: error, uncaught: uncaught);
}

/// Longest event-loop stall (ms) while [src] runs, i.e. how long the Flutter
/// UI would freeze.
Future<(Outcome, int)> runMeasuringStall(String src) async {
  var last = DateTime.now();
  var maxGap = 0;
  final ticker = Timer.periodic(const Duration(milliseconds: 1), (_) {
    final now = DateTime.now();
    final gap = now.difference(last).inMilliseconds;
    if (gap > maxGap) maxGap = gap;
    last = now;
  });
  final o = await run(src);
  ticker.cancel();
  return (o, maxGap);
}

const String recursion = 'def d(n):\n    if n == 0:\n        return 0\n    return 1 + d(n - 1)\nprint(d(DEPTH))\n';

void main() {
  group('recursion', () {
    test('900-deep recursion completes (no Dart stack overflow while unwinding)', () async {
      final r = await runInRootZone(recursion.replaceFirst('DEPTH', '900'));
      expect(r.uncaught, isEmpty);
      expect(r.finished, isTrue, reason: 'run() never completed');
      expect(r.out, ['900']);
    });

    test('infinite recursion raises "maximum recursion depth exceeded" with a line', () async {
      final r = await runInRootZone('def f():\n    f()\nf()\n');
      expect(r.uncaught, isEmpty);
      expect(r.finished, isTrue);
      expect(r.error, isA<PyRuntimeError>()
          .having((e) => e.message, 'message', 'maximum recursion depth exceeded')
          .having((e) => e.line, 'line', 2));
    });

    test('STOP during deep recursion completes run() with PyCancelled', () async {
      final r = await runInRootZone(
        'import time\ndef d(n):\n    if n == 0:\n        time.sleep(30)\n    return 1 + d(n - 1) if n else 0\nd(900)\n',
        cancelAfter: const Duration(seconds: 1),
      );
      expect(r.uncaught, isEmpty);
      expect(r.finished, isTrue, reason: 'run() never completed after STOP');
      expect(r.error, isA<PyCancelled>());
    });

    test('recursion limit also works inside the test zone', () async {
      await expectPyError('def f(n):\n    return f(n + 1)\nf(0)\n', line: 2, message: 'maximum recursion depth');
    });
  });

  group('lexer', () {
    test('a bracket spanning lines can be followed by more statements', () async {
      await expectOut('print(1,\n      2)\nprint(3)\n', ['1 2', '3']);
      await expectOut("moves = [\n    'fwd',\n    'left',\n]\nprint(moves)\n", ["['fwd', 'left']"]);
      await expectOut("if True:\n    x = [1,\n         2]\n    print(x)\nprint('done')\n", ['[1, 2]', 'done']);
      await expectOut('x = max(1,\n        2) + 3\nprint(x)\n', ['5']);
      await expectOut('d = {\n  "a": 1,\n  "b": 2}\nprint(d["b"])\n', ['2']);
    });

    test('line numbers stay correct after a multi-line bracket', () async {
      await expectPyError('x = [1,\n     2]\ny = undefined_name\n', line: 3);
    });

    test('CRLF line endings: continuation and triple-quoted strings', () async {
      await expectOut('x = 1 + \\\r\n    2\r\nprint(x)\r\n', ['3']);
      await expectOut("s = '''a\r\nb'''\r\nprint(len(s))\r\n", ['3']);
      await expectOut("if True:\r\n    print('a')\r\nprint('b')\r\n", ['a', 'b']);
    });

    test('bad hex literals are syntax errors, including from check()', () async {
      await expectPyError('x = 0x\n', line: 1, message: 'hexadecimal');
      await expectPyError('print(0xFFFFFFFFFFFFFFFFFF)\n', line: 1, message: 'too large');
      expect(PythonScriptRunner.check('x = 0x\n'), contains('line 1'));
    });

    test('deeply nested expressions are a syntax error, not a stack overflow', () async {
      final parens = 'x = ${'(' * 1000}1${')' * 1000}\n';
      expect(PythonScriptRunner.check(parens), contains('nested too deeply'));
      await expectPyError(parens, line: 1, message: 'nested too deeply');
      await expectPyError('x = ${'-' * 800}1\n', line: 1, message: 'nested too deeply');
      await expectPyError('x = ${'not ' * 800}True\n', line: 1, message: 'nested too deeply');
      await expectOut('print(${'(' * 50}1${')' * 50}, ${'-' * 50}1)\n', ['1 1']);
    });
  });

  group('parser: unsupported syntax gives a clear message', () {
    test('statements', () async {
      for (final kw in ['del', 'nonlocal', 'raise', 'assert']) {
        await expectPyError('x = 1\n$kw x\n', line: 2, message: "'$kw' is not supported");
      }
      await expectPyError('if True: del x\n', line: 1, message: "'del' is not supported");
    });

    test('comprehensions and set literals', () async {
      await expectPyError("d = {k: 1 for k in 'ab'}\n", line: 1, message: 'dict comprehensions are not supported');
      await expectPyError('print(sum(x for x in [1, 2]))\n', line: 1, message: 'generator expressions are not supported');
      await expectPyError('g = (x for x in [1, 2])\n', line: 1, message: 'generator expressions are not supported');
      await expectPyError('s = {1, 2}\n', line: 1, message: 'set literals are not supported');
      await expectPyError('s = {x for x in [1]}\n', line: 1, message: 'set comprehensions are not supported');
      await expectOut("print({}, {'a': 1})\n", ["{} {'a': 1}"]);
    });
  });

  group('slicing', () {
    test('slice step, including negative steps', () async {
      await expectOut("s = 'hello'\nprint(s[::-1], s[::2], s[1::2], s[-1:-4:-1], s[10::-1], s[:1:-1])\n",
          ['olleh hlo el oll olleh oll']);
      await expectOut('xs = [1, 2, 3, 4, 5]\nprint(xs[::2], xs[::-1], xs[3:0:-2], xs[::], (1, 2, 3)[::-1])\n',
          ['[1, 3, 5] [5, 4, 3, 2, 1] [4, 2] [1, 2, 3, 4, 5] (3, 2, 1)']);
      await expectOut("print('abc'[None:2], [1, 2, 3][:None])\n", ['ab [1, 2, 3]']);
      await expectPyError('print([1, 2][::0])\n', line: 1, message: 'slice step cannot be zero');
    });
  });

  group('assignment', () {
    test('tuple-unpacking errors are raised (not lost as uncaught async errors)', () async {
      final o = await expectPyError("a, b = 1, 2, 3\nprint('after')\n", line: 1, message: 'cannot unpack');
      expect(o.out, isEmpty);
      await expectPyError("a, b = 5\nprint('after')\n", line: 1, message: 'not iterable');
      await expectPyError('for a, b in [(1, 2, 3)]:\n    print(a)\n', line: 1, message: 'cannot unpack');
      await expectOut('a, (b, c) = 1, (2, 3)\nx, y, z = "abc"\nprint(a, b, c, x, y, z)\n', ['1 2 3 a b c']);
    });

    test('assigning to a global inside a function without `global` is an error', () async {
      await expectPyError('count = 0\ndef inc():\n    count += 1\ninc()\n', line: 3,
          message: "local variable 'count' referenced before assignment");
      await expectPyError('x = 5\ndef f():\n    print(x)\n    x = 3\nf()\n', line: 3, message: "'x'");
      // Still fine: `global`, reading outer names, closures, loop variables.
      await expectOut(
          'count = 0\ndef inc():\n    global count\n    count += 1\ninc()\nprint(count)\n'
          'def outer():\n    k = 10\n    def add(v):\n        return v + k\n    return add(1)\nprint(outer())\n'
          'def loop():\n    total = 0\n    for i in range(3):\n        total += i\n    return total\nprint(loop())\n',
          ['1', '11', '3']);
    });
  });

  group('imports', () {
    test('from-import and import-as bind names', () async {
      await expectOut('from math import sqrt\nprint(sqrt(16))\n', ['4.0']);
      await expectOut('from time import sleep\nsleep(0)\nprint("ok")\n', ['ok']);
      await expectOut('import math as m\nprint(round(m.pi, 2))\n', ['3.14']);
      await expectOut('from math import sqrt as root, pi\nprint(root(9), round(pi))\n', ['3.0 3']);
      await expectOut('from math import *\nprint(floor(2.5))\n', ['2']);
      await expectOut('def f():\n    from math import sqrt\n    return sqrt(4)\nprint(f())\n', ['2.0']);
      await expectPyError('from math import nope\n', line: 1, message: "cannot import name 'nope'");
      await expectPyError('import os\n', line: 1, message: "No module named 'os'");
    });
  });

  group('sandbox limits', () {
    test('`in` and indexing on huge ranges are constant time', () async {
      final (o, stall) = await runMeasuringStall('print(-1 in range(10**15), 10**14 in range(10**15), range(10**15)[-1])\n');
      expect(o.out, ['False True 999999999999999'], reason: '$o');
      expect(stall, lessThan(250));
      await expectOut(
          'r = range(10, 0, -3)\nprint(10 in r, 7 in r, 1 in r, 0 in r, 11 in r, 4.0 in r, 4.5 in r, True in range(2), "a" in r)\n',
          ['True True True False False True False True False']);
      await expectOut('print(range(0, 10, 3)[2], range(10, 0, -3)[-1])\n', ['6 1']);
      await expectPyError('print(range(5)[5])\n', line: 1, message: 'index out of range');
    });

    test('oversized sequences and strings are refused before allocating', () async {
      for (final src in [
        'x = [0] * 10**7\n',
        'x = "a" * 10**8\n',
        'x = 10**7 * [1, 2]\n',
        'x = list(range(10**7))\n',
        'x = tuple(range(10**7))\n',
        'x = sorted(range(10**7))\n',
        'x = sum(range(3 * 10**7))\n',
        'x = max(range(10**7))\n',
        'x = enumerate(range(10**7))\n',
        'x = zip(range(10**7))\n',
        'x = reversed(range(10**7))\n',
        'x = ",".join(range(10**7))\n',
        'a, b = range(10**9)\n',
        's = "ab" * 5000000\ns = s + s\n',
        's = "a" * 1000000\nt = s.replace("a", "aaaaaaaaaaaaaaaaaaaa")\n',
        'x = [0] * 1000000\nx.append(1)\n',
      ]) {
        final (o, stall) = await runMeasuringStall(src);
        expect(o.error, isA<PyRuntimeError>().having((e) => e.message, 'message', contains('too large')),
            reason: '$src -> $o');
        expect(o.line, isNotNull, reason: src);
        expect(stall, lessThan(250), reason: '$src froze the event loop for $stall ms');
      }
    });

    test('ordinary sizes still work', () async {
      await expectOut(
          'print(len([0] * 1000), "ab" * 3, len(list(range(100000))), sum(range(1000)), max(range(5)), "-".join(["a", "b"]))\n',
          ['1000 ababab 100000 499500 4 a-b']);
    });
  });

  group('no raw Dart errors escape from builtins', () {
    test('missing / out-of-range arguments give PyRuntimeError with a line', () async {
      for (final src in [
        'enumerate()\n',
        'sum()\n',
        'sorted()\n',
        "print('abc'.replace('a'))\n",
        'import math\nmath.pow(2)\n',
        'import math\nmath.atan2(1)\n',
        'import random\nrandom.randint(1)\n',
        'import random\nrandom.randint(0, 10**10)\n',
        'xs = []\nxs.insert(0)\n',
        'd = {}\nd.get()\n',
        'd = {}\nd.pop()\n',
        'print(chr(-1))\n',
        'print(chr(0x110000))\n',
        "print('{0} {1}'.format(1))\n",
        "x = 1.5\nprint(f'{x:.25f}')\n",
        "print('%.25f' % 1.0)\n",
        'import math\nround(math.inf)\n',
        'import math\nmath.floor(math.inf)\n',
        'import time, math\ntime.sleep(math.inf)\n',
        'import time\ntime.sleep(1e20)\n',
      ]) {
        final o = await run(src);
        expect(o.error, isA<PyRuntimeError>(), reason: '$src -> $o');
        expect(o.line, src.split('\n').length - 1, reason: '$src -> $o');
        expect(o.uncaught, isEmpty, reason: src);
      }
    });

    test('a list that contains itself gives a clean error', () async {
      await expectPyError('a = [1]\na.append(a)\nprint(a)\n', line: 3, message: 'contains itself');
      await expectPyError('a = []\na.append(a)\nb = a == a\n', line: 3);
    });

    test('check() never throws', () {
      for (final src in ['x = 0x\n', 'x = ${'[' * 5000}\n', 'print(0xFFFFFFFFFFFFFFFFFFFF)\n']) {
        expect(() => PythonScriptRunner.check(src), returnsNormally, reason: src);
        expect(PythonScriptRunner.check(src), isNotNull, reason: src);
      }
    });
  });

  group('integers', () {
    test('64-bit overflow raises instead of wrapping', () async {
      for (final src in [
        'print(2**64)\n',
        'print(2**63)\n',
        'print(10**20)\n',
        'print(9223372036854775807 + 1)\n',
        'print(-9223372036854775807 - 2)\n',
        'print(3037000500 * 3037000500)\n',
        'print(2 ** 10**8)\n',
        'def fact(n):\n    return 1 if n <= 1 else n * fact(n - 1)\nprint(fact(25))\n',
        'print(int(1e20))\n',
        'print(sum([9223372036854775807, 1]))\n',
      ]) {
        await expectPyError(src, message: 'integer overflow');
      }
      await expectPyError('print(99999999999999999999)\n', line: 1, message: 'integer literal is too large');
    });

    test('values up to the limit are exact', () async {
      await expectOut('print(2**62, 9223372036854775807, -9223372036854775807 - 1, (-2) ** 63)\n',
          ['4611686018427387904 9223372036854775807 -9223372036854775808 -9223372036854775808']);
      await expectOut('def fact(n):\n    return 1 if n <= 1 else n * fact(n - 1)\nprint(fact(20))\n', ['2432902008176640000']);
      await expectOut('print(12345678901234567 // 1, -12345678901234567 // 10, 7 // -2, -7 // 2, (-2) ** 63)\n',
          ['12345678901234567 -1234567890123457 -4 -4 -9223372036854775808']);
    });
  });

  group('f-strings and formatting', () {
    test('errors inside f-string fields report the f-string line', () async {
      await expectPyError("x = 1\ny = 2\nprint(f'{zz}')\n", line: 3, message: "'zz' is not defined");
      await expectPyError("x = 1\n\nprint(f'{x!r}')\n", line: 3);
      await expectPyError("x = 1\n\nprint(f'{x +}')\n", line: 3);
    });

    test('zero padding', () async {
      await expectOut("m = 5\ns = 3\nprint(f'{m:02d}:{s:02d}', f'{-5:04d}', f'{3.14159:07.2f}', '{:03}'.format(7), f'{42:05}')\n",
          ['05:03 -005 0003.14 007 00042']);
      await expectOut("print(f'{7:>3}|{7:<3}|{7:^3}|{7:3}|')\n", ['  7|7  | 7 |  7|']);
    });

    test("round() is half-to-even and returns int for int input", () async {
      // Expected values are CPython's.
      await expectOut('print(round(2.5), round(0.5), round(-2.5), round(1.5), round(3.5), round(-0.5))\n',
          ['2 0 -2 2 4 0']);
      await expectOut(
          'print(round(0.125, 2), round(0.375, 2), round(-0.125, 2), round(2.675, 2), round(2.665, 2), round(1.005, 2), round(12.345, 2), round(2.5, 0), round(1234.5, -2), round(3.14159, 3))\n',
          ['0.12 0.38 -0.12 2.67 2.67 1.0 12.35 2.0 1200.0 3.142']);
      await expectOut('print(round(5, 2), round(1234, -2), round(1250, -2), round(1350, -2), round(-1250, -2), round(3.7))\n',
          ['5 1200 1200 1400 -1200 4']);
      await expectPyError('import math\nround(math.inf)\n', line: 2, message: 'infinity');
    });

    test("float('inf'), float('-inf'), float('nan')", () async {
      await expectOut("print(float('inf'), float('-inf'), float('nan'), float(' Infinity '), float('-INF'))\n",
          ['inf -inf nan inf -inf']);
      await expectOut("best = float('inf')\nfor d in [5, 3]:\n    best = min(best, d)\nprint(best)\n", ['3']);
      await expectPyError("float('infinite')\n", line: 1, message: 'could not convert');
    });
  });

  group('builtins', () {
    test('key= and reverse= for sorted / list.sort / min / max (stable sort)', () async {
      await expectOut("print(sorted(['b', 'aa', 'c', 'dd'], key=len), sorted([3, 1, 2], reverse=True))\n",
          ["['b', 'c', 'aa', 'dd'] [3, 2, 1]"]);
      await expectOut("print(sorted(['bb', 'a', 'cc', 'd'], key=len, reverse=True))\n", ["['bb', 'cc', 'a', 'd']"]);
      await expectOut("print(max(['aa', 'b'], key=len), min(['aa', 'b'], key=len), max([], default=0))\n", ['aa b 0']);
      await expectOut('xs = [1, 3, 2]\nxs.sort(key=lambda v: -v)\nprint(xs)\nxs.sort()\nprint(xs)\n', ['[3, 2, 1]', '[1, 2, 3]']);
      await expectPyError('def k(v):\n    return undefined_name\nsorted([1, 2], key=k)\n', line: 2);
    });

    test('str.strip(chars) and int(s, base)', () async {
      await expectOut("print('xxhixx'.strip('x'), '..a..'.lstrip('.'), '..a..'.rstrip('.'), '  b  '.strip())\n",
          ['hi a.. ..a b']);
      await expectOut("print(int('101', 2), int('ff', 16), int('0xff', 16), int('-7', 8), int('z', 36), int('12', base=10))\n",
          ['5 255 255 -7 35 12']);
      await expectPyError("int('2', 2)\n", line: 1, message: 'invalid literal');
      await expectPyError('int(5, 2)\n', line: 1, message: 'explicit base');
    });

    test('dict() arguments', () async {
      await expectOut("print(dict(a=1), dict([('b', 2)]), dict({'c': 3}), dict([(1, 'x')], y=2))\n",
          ["{'a': 1} {'b': 2} {'c': 3} {1: 'x', 'y': 2}"]);
    });

    test('isinstance()', () async {
      await expectOut('print(isinstance(5, int), isinstance("a", str), isinstance(True, int), isinstance(1.5, (int, float)), isinstance([], dict))\n',
          ['True True True True False']);
      await expectPyError('isinstance(1, 2)\n', line: 1, message: 'must be a type');
    });

    test('unsupported keyword arguments are rejected, not ignored', () async {
      await expectPyError("print(len('ab', foo=1))\n", line: 1, message: "unexpected keyword argument 'foo'");
      await expectPyError("print(sorted([1], cmp=None))\n", line: 1, message: "unexpected keyword argument 'cmp'");
      await expectPyError("'a,b'.split(',', maxsplit=1)\n", line: 1, message: "unexpected keyword argument 'maxsplit'");
      await expectOut("print(1, 2, sep='-', end='!', flush=True)\n", ['1-2!']);
      await expectOut("print('{a}{b}'.format(a=1, b=2))\n", ['12']);
    });
  });

  group('dicts', () {
    test('tuple keys stay tuples', () async {
      await expectOut("d = {(1, 2): 'a'}\nprint(d)\nfor k in d:\n    print(k[0] + 10)\n", ["{(1, 2): 'a'}", '11']);
      await expectOut("d = {(1, 2): 'a'}\nprint(list(d.keys()), d.items(), (1, 2) in d, d[(1.0, 2)], d.get((1, 2)))\n",
          ["[(1, 2)] [((1, 2), 'a')] True a a"]);
      await expectOut("grid = {}\ngrid[(0, 1)] = 'X'\ngrid[(0, 0)] = 'S'\nprint(sorted(grid.keys()), len(grid))\n",
          ['[(0, 0), (0, 1)] 2']);
      await expectOut("d = {((1, 2), 3): 'nested'}\nprint(d[((1, 2), 3)], d.pop(((1, 2), 3)), d)\n", ['nested nested {}']);
    });
  });
}
