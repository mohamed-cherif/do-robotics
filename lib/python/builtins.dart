/// Built-in functions, str/list methods, and the `time`, `math`, `random`
/// modules for the RoboPython interpreter.
library;

import 'dart:math' as math;

import 'interpreter.dart';
import 'values.dart';

final _rng = math.Random();

void installBuiltins(Interpreter interp) {
  final g = interp.globals.vars;

  void fn(String name, NativeFn f) => g[name] = PyNative(name, f);

  fn('print', (args, kw) {
    final sep = kw.containsKey('sep') ? pyStr(kw['sep']) : ' ';
    final end = kw.containsKey('end') ? pyStr(kw['end']) : '';
    interp.onPrint(args.map(pyStr).join(sep) + end);
    return null;
  });
  fn('len', (a, _) => pyLen(_one(a, 'len')));
  fn('abs', (a, _) => pyToNum(_one(a, 'abs')).abs());
  fn('int', (a, _) {
    if (a.isEmpty) return 0;
    return pyToInt(a.first);
  });
  fn('float', (a, _) {
    if (a.isEmpty) return 0.0;
    return pyToDouble(a.first);
  });
  fn('str', (a, _) => a.isEmpty ? '' : pyStr(a.first));
  fn('repr', (a, _) => pyRepr(_one(a, 'repr')));
  fn('bool', (a, _) => a.isEmpty ? false : pyTruthy(a.first));
  fn('list', (a, _) => a.isEmpty ? PyList() : PyList(pyIterate(a.first).toList()));
  fn('tuple', (a, _) => a.isEmpty ? const PyTuple([]) : PyTuple(pyIterate(a.first).toList()));
  fn('dict', (a, _) => PyDict());
  fn('type', (a, _) => "<class '${pyTypeName(_one(a, 'type'))}'>");
  fn('round', (a, _) {
    if (a.isEmpty) throw PyRuntimeError('round() missing argument');
    final v = pyToNum(a[0]);
    if (a.length > 1 && a[1] != null) {
      final nd = pyToInt(a[1]);
      final f = math.pow(10, nd);
      return (v * f).round() / f;
    }
    return v.round();
  });
  fn('min', (a, _) => _minMax(a, (c) => c < 0, 'min'));
  fn('max', (a, _) => _minMax(a, (c) => c > 0, 'max'));
  fn('sum', (a, _) {
    num total = a.length > 1 ? pyToNum(a[1]) : 0;
    for (final v in pyIterate(_one([a.first], 'sum'))) {
      total += pyToNum(v);
    }
    return total;
  });
  fn('range', (a, _) {
    if (a.isEmpty || a.length > 3) throw PyRuntimeError('range expected 1 to 3 arguments');
    final ints = a.map(pyToInt).toList();
    if (ints.length == 1) return PyRange(0, ints[0], 1);
    if (ints.length == 2) return PyRange(ints[0], ints[1], 1);
    if (ints[2] == 0) throw PyRuntimeError('range() arg 3 must not be zero');
    return PyRange(ints[0], ints[1], ints[2]);
  });
  fn('enumerate', (a, kw) {
    int i = kw.containsKey('start') ? pyToInt(kw['start']) : (a.length > 1 ? pyToInt(a[1]) : 0);
    return PyList([for (final v in pyIterate(_one([a.first], 'enumerate'))) PyTuple([i++, v])]);
  });
  fn('zip', (a, _) {
    final lists = a.map((x) => pyIterate(x).toList()).toList();
    final n = lists.isEmpty ? 0 : lists.map((l) => l.length).reduce(math.min);
    return PyList([for (int i = 0; i < n; i++) PyTuple([for (final l in lists) l[i]])]);
  });
  fn('reversed', (a, _) => PyList(pyIterate(_one(a, 'reversed')).toList().reversed.toList()));
  fn('sorted', (a, kw) {
    final items = pyIterate(_one([a.first], 'sorted')).toList();
    items.sort(pyCompare);
    if (kw['reverse'] == true) return PyList(items.reversed.toList());
    return PyList(items);
  });
  fn('isinstance', (a, _) => false);
  fn('input', (a, _) => throw PyRuntimeError('input() is not available on the robot'));
  fn('exit', (a, _) => throw const PyExit());
  fn('quit', (a, _) => throw const PyExit());
  fn('chr', (a, _) => String.fromCharCode(pyToInt(_one(a, 'chr'))));
  fn('ord', (a, _) {
    final s = _one(a, 'ord');
    if (s is! String || s.length != 1) throw PyRuntimeError('ord() expected a character');
    return s.codeUnitAt(0);
  });

  // time
  final timeMod = PyObject('module time');
  timeMod.method('sleep', (a, _) async {
    await interp.sleep(pyToDouble(_one(a, 'sleep')));
    return null;
  });
  timeMod.method('time', (a, _) => DateTime.now().millisecondsSinceEpoch / 1000.0);
  timeMod.method('monotonic', (a, _) => DateTime.now().millisecondsSinceEpoch / 1000.0);
  timeMod.method('ticks_ms', (a, _) => DateTime.now().millisecondsSinceEpoch);
  g['time'] = timeMod;

  // math
  final mathMod = PyObject('module math');
  mathMod.attrs['pi'] = math.pi;
  mathMod.attrs['e'] = math.e;
  mathMod.attrs['inf'] = double.infinity;
  double d1(List<Object?> a, String n) => pyToDouble(_one(a, n));
  mathMod.method('sqrt', (a, _) {
    final v = d1(a, 'sqrt');
    if (v < 0) throw PyRuntimeError('math domain error');
    return math.sqrt(v);
  });
  mathMod.method('sin', (a, _) => math.sin(d1(a, 'sin')));
  mathMod.method('cos', (a, _) => math.cos(d1(a, 'cos')));
  mathMod.method('tan', (a, _) => math.tan(d1(a, 'tan')));
  mathMod.method('asin', (a, _) => math.asin(d1(a, 'asin')));
  mathMod.method('acos', (a, _) => math.acos(d1(a, 'acos')));
  mathMod.method('atan', (a, _) => math.atan(d1(a, 'atan')));
  mathMod.method('atan2', (a, _) => math.atan2(pyToDouble(a[0]), pyToDouble(a[1])));
  mathMod.method('degrees', (a, _) => d1(a, 'degrees') * 180 / math.pi);
  mathMod.method('radians', (a, _) => d1(a, 'radians') * math.pi / 180);
  mathMod.method('floor', (a, _) => d1(a, 'floor').floor());
  mathMod.method('ceil', (a, _) => d1(a, 'ceil').ceil());
  mathMod.method('fabs', (a, _) => d1(a, 'fabs').abs());
  mathMod.method('pow', (a, _) => math.pow(pyToDouble(a[0]), pyToDouble(a[1])));
  mathMod.method('hypot', (a, _) => math.sqrt(a.fold<double>(0, (s, v) => s + pyToDouble(v) * pyToDouble(v))));
  mathMod.method('log', (a, _) => a.length > 1 ? math.log(pyToDouble(a[0])) / math.log(pyToDouble(a[1])) : math.log(d1(a, 'log')));
  mathMod.method('exp', (a, _) => math.exp(d1(a, 'exp')));
  g['math'] = mathMod;

  // random
  final randomMod = PyObject('module random');
  randomMod.method('random', (a, _) => _rng.nextDouble());
  randomMod.method('randint', (a, _) {
    final lo = pyToInt(a[0]), hi = pyToInt(a[1]);
    if (hi < lo) throw PyRuntimeError('empty range for randint()');
    return lo + _rng.nextInt(hi - lo + 1);
  });
  randomMod.method('uniform', (a, _) {
    final lo = pyToDouble(a[0]), hi = pyToDouble(a[1]);
    return lo + _rng.nextDouble() * (hi - lo);
  });
  randomMod.method('choice', (a, _) {
    final items = pyIterate(_one(a, 'choice')).toList();
    if (items.isEmpty) throw PyRuntimeError('cannot choose from an empty sequence');
    return items[_rng.nextInt(items.length)];
  });
  g['random'] = randomMod;
}

Object? _one(List<Object?> a, String name) {
  if (a.length != 1) throw PyRuntimeError('$name() takes exactly one argument (${a.length} given)');
  return a.first;
}

Object? _minMax(List<Object?> a, bool Function(int) pick, String name) {
  final items = a.length == 1 ? pyIterate(a.first).toList() : a;
  if (items.isEmpty) throw PyRuntimeError('$name() arg is an empty sequence');
  Object? best = items.first;
  for (final v in items.skip(1)) {
    if (pick(pyCompare(v, best))) best = v;
  }
  return best;
}

/// Methods available on str / list / dict values, bound to the receiver.
PyNative? methodFor(Object? obj, String name) {
  if (obj is String) {
    switch (name) {
      case 'lower':
        return PyNative(name, (a, _) => obj.toLowerCase());
      case 'upper':
        return PyNative(name, (a, _) => obj.toUpperCase());
      case 'strip':
        return PyNative(name, (a, _) => obj.trim());
      case 'lstrip':
        return PyNative(name, (a, _) => obj.trimLeft());
      case 'rstrip':
        return PyNative(name, (a, _) => obj.trimRight());
      case 'split':
        return PyNative(name, (a, _) {
          if (a.isEmpty || a.first == null) {
            return PyList(obj.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList());
          }
          return PyList(obj.split(pyStr(a.first)));
        });
      case 'join':
        return PyNative(name, (a, _) => pyIterate(_one(a, 'join')).map(pyStr).join(obj));
      case 'startswith':
        return PyNative(name, (a, _) => obj.startsWith(pyStr(_one(a, name))));
      case 'endswith':
        return PyNative(name, (a, _) => obj.endsWith(pyStr(_one(a, name))));
      case 'replace':
        return PyNative(name, (a, _) => obj.replaceAll(pyStr(a[0]), pyStr(a[1])));
      case 'find':
        return PyNative(name, (a, _) => obj.indexOf(pyStr(_one(a, name))));
      case 'count':
        return PyNative(name, (a, _) => pyStr(_one(a, name)).allMatches(obj).length);
      case 'isdigit':
        return PyNative(name, (a, _) => obj.isNotEmpty && RegExp(r'^\d+$').hasMatch(obj));
      case 'capitalize':
        return PyNative(name, (a, _) => obj.isEmpty ? obj : obj[0].toUpperCase() + obj.substring(1).toLowerCase());
      case 'format':
        return PyNative(name, (a, kw) {
          int i = 0;
          return obj.replaceAllMapped(RegExp(r'\{(\w*)(?::([^}]*))?\}'), (m) {
            final key = m.group(1)!;
            final fmt = m.group(2);
            Object? v;
            if (key.isEmpty) {
              if (i >= a.length) throw PyRuntimeError('not enough arguments for format()');
              v = a[i++];
            } else if (int.tryParse(key) != null) {
              v = a[int.parse(key)];
            } else {
              v = kw[key];
            }
            return formatValue(v, fmt, null);
          });
        });
    }
  }
  if (obj is PyList) {
    switch (name) {
      case 'append':
        return PyNative(name, (a, _) {
          obj.items.add(_one(a, name));
          return null;
        });
      case 'extend':
        return PyNative(name, (a, _) {
          obj.items.addAll(pyIterate(_one(a, name)));
          return null;
        });
      case 'pop':
        return PyNative(name, (a, _) {
          if (obj.items.isEmpty) throw PyRuntimeError('pop from empty list');
          if (a.isEmpty) return obj.items.removeLast();
          var i = pyToInt(a.first);
          if (i < 0) i += obj.items.length;
          if (i < 0 || i >= obj.items.length) throw PyRuntimeError('pop index out of range');
          return obj.items.removeAt(i);
        });
      case 'insert':
        return PyNative(name, (a, _) {
          var i = pyToInt(a[0]);
          if (i < 0) i += obj.items.length;
          obj.items.insert(i.clamp(0, obj.items.length), a[1]);
          return null;
        });
      case 'remove':
        return PyNative(name, (a, _) {
          final v = _one(a, name);
          final i = obj.items.indexWhere((x) => pyEquals(x, v));
          if (i < 0) throw PyRuntimeError('list.remove(x): x not in list');
          obj.items.removeAt(i);
          return null;
        });
      case 'index':
        return PyNative(name, (a, _) {
          final v = _one(a, name);
          final i = obj.items.indexWhere((x) => pyEquals(x, v));
          if (i < 0) throw PyRuntimeError('${pyRepr(v)} is not in list');
          return i;
        });
      case 'count':
        return PyNative(name, (a, _) {
          final v = _one(a, name);
          return obj.items.where((x) => pyEquals(x, v)).length;
        });
      case 'clear':
        return PyNative(name, (a, _) {
          obj.items.clear();
          return null;
        });
      case 'reverse':
        return PyNative(name, (a, _) {
          final r = obj.items.reversed.toList();
          obj.items
            ..clear()
            ..addAll(r);
          return null;
        });
      case 'sort':
        return PyNative(name, (a, kw) {
          obj.items.sort(pyCompare);
          if (kw['reverse'] == true) {
            final r = obj.items.reversed.toList();
            obj.items
              ..clear()
              ..addAll(r);
          }
          return null;
        });
      case 'copy':
        return PyNative(name, (a, _) => PyList(List.of(obj.items)));
    }
  }
  if (obj is PyDict) {
    switch (name) {
      case 'get':
        return PyNative(name, (a, _) => obj.containsKey(a[0]) ? obj[a[0]] : (a.length > 1 ? a[1] : null));
      case 'keys':
        return PyNative(name, (a, _) => PyList(obj.map.keys.toList()));
      case 'values':
        return PyNative(name, (a, _) => PyList(obj.map.values.toList()));
      case 'items':
        return PyNative(name, (a, _) => PyList([for (final e in obj.map.entries) PyTuple([e.key, e.value])]));
      case 'pop':
        return PyNative(name, (a, _) {
          final k = pyKey(a[0]);
          if (!obj.map.containsKey(k)) {
            if (a.length > 1) return a[1];
            throw PyRuntimeError('KeyError: ${pyRepr(a[0])}');
          }
          return obj.map.remove(k);
        });
      case 'clear':
        return PyNative(name, (a, _) {
          obj.map.clear();
          return null;
        });
    }
  }
  return null;
}

/// Applies a Python format spec subset: `.2f`, `d`, `5d`, `>8`, `<8`, `^8`, `%`.
String formatValue(Object? v, String? spec, int? line) {
  if (spec == null || spec.isEmpty) return pyStr(v);
  final m = RegExp(r'^([<>^])?(\d+)?(?:\.(\d+))?([fdse%])?$').firstMatch(spec);
  if (m == null) throw PyRuntimeError("invalid format spec '$spec'", line);
  final align = m.group(1);
  final width = m.group(2) == null ? 0 : int.parse(m.group(2)!);
  final prec = m.group(3) == null ? null : int.parse(m.group(3)!);
  final type = m.group(4);
  String s;
  switch (type) {
    case 'f':
      s = pyToDouble(v).toStringAsFixed(prec ?? 6);
      break;
    case 'd':
      s = pyToInt(v).toString();
      break;
    case 'e':
      s = pyToDouble(v).toStringAsExponential(prec ?? 6);
      break;
    case '%':
      s = '${(pyToDouble(v) * 100).toStringAsFixed(prec ?? 6)}%';
      break;
    default:
      s = pyStr(v);
      if (prec != null && v is String) s = s.substring(0, math.min(prec, s.length));
      if (prec != null && v is num) s = pyToDouble(v).toStringAsFixed(prec);
  }
  if (s.length < width) {
    final pad = width - s.length;
    switch (align ?? (v is num ? '>' : '<')) {
      case '>':
        s = ' ' * pad + s;
        break;
      case '^':
        s = ' ' * (pad ~/ 2) + s + ' ' * (pad - pad ~/ 2);
        break;
      default:
        s = s + ' ' * pad;
    }
  }
  return s;
}
