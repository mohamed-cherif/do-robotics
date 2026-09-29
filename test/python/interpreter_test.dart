import 'package:flutter_test/flutter_test.dart';
import 'package:do_robotics/python/interpreter.dart';
import 'package:do_robotics/python/lexer.dart';
import 'package:do_robotics/python/values.dart';

Future<List<String>> run(String src, {CancelToken? cancel}) async {
  final out = <String>[];
  final interp = Interpreter(onPrint: out.add, cancel: cancel);
  await interp.run(src);
  return out;
}

void main() {
  group('arithmetic and printing', () {
    test('ints, floats, precedence, python division', () async {
      final out = await run('''
print(1 + 2 * 3)
print(7 / 2, 7 // 2, 7 % 3, -7 // 2, -7 % 3)
print(2 ** 10, 2 ** 0.5 > 1.41)
print(10 / 5)
x = 5
x += 2.5
print(x, int(x), round(3.14159, 2))
print(True + 1, not 0)
''');
      expect(out, ['7', '3.5 3 1 -4 2', '1024 True', '2.0', '7.5 7 3.14', '2 True']);
    });

    test('strings and f-strings', () async {
      final out = await run('''
name = "robot"
print(f"hi {name.upper()}!", f"{3.14159:.2f}", f"{{literal}}", "a" + "b" * 3)
print("go forward".split(), "x,y".split(","), "-".join(["a", "b"]))
print("%d items at %.1f%%" % (3, 99.5))
print(name[0], name[-1], name[1:3], len(name), "bot" in name)
print(str(1.0), str(True), str(None), repr("it's"))
''');
      expect(out, [
        "hi ROBOT! 3.14 {literal} abbb",
        "['go', 'forward'] ['x', 'y'] a-b",
        '3 items at 99.5%',
        'r t ob 5 True',
        "1.0 True None \"it's\"",
      ]);
    });

    test('lists, tuples, dicts', () async {
      final out = await run('''
xs = [3, 1, 2]
xs.append(5)
xs.sort()
print(xs, xs[-1], xs[1:], len(xs), sum(xs), min(xs), max(xs))
a, b = (1, 2)
a, b = b, a
print(a, b)
d = {"k": 1}
d["j"] = 2
print(d["k"] + d["j"], "k" in d, d.get("zz", 0), sorted(d.keys()))
for i, v in enumerate(["p", "q"]):
    print(i, v)
''');
      expect(out, [
        '[1, 2, 3, 5] 5 [2, 3, 5] 4 11 1 5',
        '2 1',
        "3 True 0 ['j', 'k']",
        '0 p',
        '1 q',
      ]);
    });
  });

  group('control flow and functions', () {
    test('if/elif/else, while, for, break, continue', () async {
      final out = await run('''
total = 0
for i in range(10):
    if i % 2 == 0:
        continue
    if i > 7:
        break
    total += i
print(total)
n = 3
while n > 0:
    n -= 1
if n == 0: print("zero")
elif n < 0:
    print("neg")
else:
    print("pos")
for c in "ab": print(c, end="")
print()
''');
      expect(out, ['16', 'zero', 'a', 'b', '']);
    });

    test('def, defaults, kwargs, recursion, closures, global', () async {
      final out = await run('''
def fact(n):
    return 1 if n <= 1 else n * fact(n - 1)

def greet(name, punct="!"):
    return "hi " + name + punct

count = 0
def bump():
    global count
    count += 1

def make_adder(k):
    def add(x):
        return x + k
    return add

bump(); bump()
print(fact(5), greet("bo"), greet("al", punct="?"), count, make_adder(10)(5))
sq = lambda v: v * v
print(sq(4))
''');
      expect(out, ['120 hi bo! hi al? 2 15', '16']);
    });

    test('chained comparisons, and/or short circuit, ternary', () async {
      final out = await run('''
x = 5
print(1 < x < 10, 1 < x > 10, x == 5.0, x != 5)
print(0 or "fallback", 1 and 2, None or 0)
print("big" if x > 3 else "small")
''');
      expect(out, ['True False True False', 'fallback 2 0', 'big']);
    });

    test('modules: time and math', () async {
      final out = await run('''
import time, math
t = time.time()
time.sleep(0.01)
print(time.time() - t >= 0.009, round(math.sqrt(16)), round(math.degrees(math.pi)))
''');
      expect(out, ['True 4 180']);
    });
  });

  group('errors', () {
    test('syntax errors carry the line number', () {
      expect(
        () => run('x = 1\nif x\n    print(x)\n'),
        throwsA(isA<PySyntaxError>().having((e) => e.line, 'line', 2)),
      );
      expect(
        () => run('def f():\nprint(1)\n'),
        throwsA(isA<PySyntaxError>().having((e) => e.line, 'line', 2)),
      );
    });

    test('runtime errors carry the line number', () async {
      await expectLater(
        run('a = 1\nb = a / 0\n'),
        throwsA(isA<PyRuntimeError>()
            .having((e) => e.line, 'line', 2)
            .having((e) => e.message, 'message', contains('division by zero'))),
      );
      await expectLater(
        run('print(undefined_name)\n'),
        throwsA(isA<PyRuntimeError>().having((e) => e.message, 'message', contains("'undefined_name' is not defined"))),
      );
      await expectLater(
        run('xs = [1]\nxs[3]\n'),
        throwsA(isA<PyRuntimeError>().having((e) => e.line, 'line', 2)),
      );
    });

    test('unsupported features fail early with a clear message', () {
      expect(() => run('class A:\n    pass\n'), throwsA(isA<PySyntaxError>()));
      expect(() => run('try:\n    pass\nexcept:\n    pass\n'), throwsA(isA<PySyntaxError>()));
    });
  });

  group('cancellation', () {
    test('STOP interrupts an infinite loop and a long sleep', () async {
      final cancel = CancelToken();
      final f = run('import time\nwhile True:\n    time.sleep(10)\n', cancel: cancel);
      await Future.delayed(const Duration(milliseconds: 30));
      cancel.cancel();
      await expectLater(f, throwsA(isA<PyCancelled>()));

      final cancel2 = CancelToken();
      final f2 = run('n = 0\nwhile True:\n    n += 1\n', cancel: cancel2);
      await Future.delayed(const Duration(milliseconds: 30));
      cancel2.cancel();
      await expectLater(f2, throwsA(isA<PyCancelled>()));
    });

    test('exit() ends the program normally', () async {
      final out = await run('print("a")\nexit()\nprint("b")\n');
      expect(out, ['a']);
    });
  });
}
