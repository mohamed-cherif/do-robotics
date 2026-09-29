/// Built-in functions, str/list methods, and the `time`, `math`, `random`
/// modules for the RoboPython interpreter.
library;

import 'dart:math' as math;

import 'interpreter.dart';
import 'values.dart';

final _rng = math.Random();

void installBuiltins(Interpreter interp) {
  final g = interp.globals.vars;

  /// Registers a builtin. Keyword arguments not listed in [kw] are rejected
  /// instead of being silently ignored.
  void fn(String name, NativeFn f, {Set<String> kw = const {}, bool anyKw = false}) =>
      g[name] = PyNative(name, _checkedKw(name, f, kw, anyKw: anyKw));

  fn('print', (args, kw) {
    final sep = kw.containsKey('sep') ? pyStr(kw['sep']) : ' ';
    final end = kw.containsKey('end') ? pyStr(kw['end']) : '';
    interp.onPrint(args.map(pyStr).join(sep) + end);
    return null;
  }, kw: {'sep', 'end', 'flush'});
  fn('len', (a, _) => pyLen(_one(a, 'len')));
  fn('abs', (a, _) {
    final v = pyToNum(_one(a, 'abs'));
    return v is int && v < 0 ? pyNegInt(v) : v.abs();
  });
  fn('int', (a, kw) {
    if (a.isEmpty) return 0;
    final base = a.length > 1 ? a[1] : kw['base'];
    if (base != null) return pyParseIntBase(a.first, pyToInt(base));
    return pyToInt(a.first);
  }, kw: {'base'});
  fn('float', (a, _) {
    if (a.isEmpty) return 0.0;
    return pyToDouble(a.first);
  });
  fn('str', (a, _) => a.isEmpty ? '' : pyStr(a.first));
  fn('repr', (a, _) => pyRepr(_one(a, 'repr')));
  fn('bool', (a, _) => a.isEmpty ? false : pyTruthy(a.first));
  fn('list', (a, _) => a.isEmpty ? PyList() : PyList(pyToList(a.first)));
  fn('tuple', (a, _) => a.isEmpty ? const PyTuple([]) : PyTuple(pyToList(a.first)));
  fn('dict', (a, kw) {
    final d = PyDict();
    if (a.isNotEmpty) {
      final src = _one(a, 'dict');
      if (src is PyDict) {
        d.map.addAll(src.map);
      } else {
        for (final pair in pyToList(src)) {
          final kv = pyToList(pair);
          if (kv.length != 2) throw PyRuntimeError('dict() needs pairs like (key, value)');
          d[kv[0]] = kv[1];
        }
      }
    }
    kw.forEach((k, v) => d[k] = v);
    return d;
  }, anyKw: true);
  fn('type', (a, _) => "<class '${pyTypeName(_one(a, 'type'))}'>");
  fn('round', (a, kw) {
    if (a.isEmpty) throw PyRuntimeError('round() missing argument');
    final v = pyToNum(a[0]);
    final ndArg = a.length > 1 ? a[1] : kw['ndigits'];
    final nd = ndArg == null ? null : pyToInt(ndArg);
    if (v is int) return nd == null || nd >= 0 ? v : _roundIntHalfEven(v, -nd);
    final d = v.toDouble();
    if (nd == null) return pyDoubleToInt(_roundHalfEven(d));
    return _roundDigits(d, nd);
  }, kw: {'ndigits'});
  fn('min', (a, kw) => _minMax(interp, a, kw, (c) => c < 0, 'min'), kw: {'key', 'default'});
  fn('max', (a, kw) => _minMax(interp, a, kw, (c) => c > 0, 'max'), kw: {'key', 'default'});
  fn('sum', (a, kw) {
    if (a.isEmpty) throw PyRuntimeError('sum() takes at least 1 argument (0 given)');
    final start = a.length > 1 ? a[1] : kw['start'];
    num total = start == null ? 0 : pyToNum(start);
    final it = a.first;
    if (it is PyRange) checkSeqLen(it.length);
    for (final v in pyIterate(it)) {
      total = pyAddNum(total, pyToNum(v));
    }
    return total;
  }, kw: {'start'});
  fn('range', (a, _) {
    if (a.isEmpty || a.length > 3) throw PyRuntimeError('range expected 1 to 3 arguments');
    final ints = a.map(pyToInt).toList();
    if (ints.length == 1) return PyRange(0, ints[0], 1);
    if (ints.length == 2) return PyRange(ints[0], ints[1], 1);
    if (ints[2] == 0) throw PyRuntimeError('range() arg 3 must not be zero');
    return PyRange(ints[0], ints[1], ints[2]);
  });
  fn('enumerate', (a, kw) {
    if (a.isEmpty) throw PyRuntimeError('enumerate() missing required argument');
    int i = kw.containsKey('start') ? pyToInt(kw['start']) : (a.length > 1 ? pyToInt(a[1]) : 0);
    return PyList([for (final v in pyToList(a.first)) PyTuple([i++, v])]);
  }, kw: {'start'});
  fn('zip', (a, _) {
    final lists = a.map(pyToList).toList();
    final n = lists.isEmpty ? 0 : lists.map((l) => l.length).reduce(math.min);
    return PyList([for (int i = 0; i < n; i++) PyTuple([for (final l in lists) l[i]])]);
  });
  fn('reversed', (a, _) => PyList(pyToList(_one(a, 'reversed')).reversed.toList()));
  fn('sorted', (a, kw) async {
    return PyList(await _sorted(interp, pyToList(_one(a, 'sorted')), kw));
  }, kw: {'key', 'reverse'});
  fn('isinstance', (a, _) {
    if (a.length != 2) throw PyRuntimeError('isinstance() takes exactly 2 arguments');
    final types = a[1] is PyTuple ? (a[1] as PyTuple).items : [a[1]];
    final actual = pyTypeName(a[0]);
    for (final t in types) {
      if (t is! PyNative || !_typeNames.contains(t.name)) {
        throw PyRuntimeError('isinstance() arg 2 must be a type such as int, float, str, list or dict');
      }
      if (t.name == actual || (t.name == 'int' && actual == 'bool')) return true;
    }
    return false;
  });
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
  mathMod.method('floor', (a, _) => pyDoubleToInt(d1(a, 'floor').floorToDouble()));
  mathMod.method('ceil', (a, _) => pyDoubleToInt(d1(a, 'ceil').ceilToDouble()));
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

const Set<String> _typeNames = {'int', 'float', 'str', 'bool', 'list', 'tuple', 'dict', 'range'};

NativeFn _checkedKw(String name, NativeFn f, Set<String> allowed, {bool anyKw = false}) {
  if (anyKw) return f;
  return (args, kwargs) {
    for (final k in kwargs.keys) {
      if (!allowed.contains(k)) throw PyRuntimeError("$name() got an unexpected keyword argument '$k'");
    }
    return f(args, kwargs);
  };
}

PyNative _native(String name, NativeFn f, [Set<String> kw = const {}]) => PyNative(name, _checkedKw(name, f, kw));

/// Rounds half to even, like Python's round().
double _roundHalfEven(double x) {
  final r = x.roundToDouble();
  if ((r - x).abs() == 0.5) return 2.0 * (x / 2.0).roundToDouble();
  return r;
}

/// round(d, nd) for floats. Like CPython it rounds the exact binary value
/// (round(2.675, 2) == 2.67) and sends exact ties to the even neighbour.
double _roundDigits(double d, int nd) {
  if (!d.isFinite || d.abs() >= 1e21) return d;
  if (nd < 0 || nd > 19) {
    final f = math.pow(10.0, nd).toDouble();
    final scaled = d * f;
    return scaled.isFinite && f != 0 ? _roundHalfEven(scaled) / f : d;
  }
  // toStringAsFixed rounds the exact value, but exact ties away from zero.
  final away = d.toStringAsFixed(nd);
  // d is an exact tie at nd decimals iff d * 2^(nd+1) is an odd integer.
  final y = d * math.pow(2.0, nd + 1);
  final isTie = y == y.truncateToDouble() && y.abs() < 9e15 && y.toInt().isOdd;
  if (!isTie || (away.codeUnitAt(away.length - 1) - 48).isEven) return double.parse(away);
  final exact = d.toStringAsFixed(nd + 1); // e.g. "0.125" -> keep "0.12"
  return double.parse(exact.substring(0, exact.length - 1));
}

/// round(v, -digits) for ints: nearest multiple of 10**digits, ties to even.
int _roundIntHalfEven(int v, int digits) {
  if (digits > 18) return 0;
  final p = pyPowInt(10, digits);
  var q = pyFloorDiv(v, p) as int;
  final r = v - q * p;
  if (2 * r > p || (2 * r == p && q.isOdd)) q++;
  return pyMulInt(q, p);
}

/// Python's stable sort with optional key= and reverse=.
Future<List<Object?>> _sorted(Interpreter interp, List<Object?> items, Map<String, Object?> kw) async {
  final key = kw['key'];
  final reverse = pyTruthy(kw['reverse']);
  final keys = key == null
      ? items
      : [for (final v in items) await interp.callValue(key, [v], const {}, interp.currentLine, describe: 'key')];
  final order = List<int>.generate(items.length, (i) => i);
  order.sort((i, j) {
    final c = pyCompare(keys[i], keys[j]);
    if (c != 0) return reverse ? -c : c;
    return i - j; // stable
  });
  return [for (final i in order) items[i]];
}

Future<Object?> _minMax(
    Interpreter interp, List<Object?> a, Map<String, Object?> kw, bool Function(int) pick, String name) async {
  final items = a.length == 1 ? pyToList(a.first) : a;
  if (items.isEmpty) {
    if (kw.containsKey('default')) return kw['default'];
    throw PyRuntimeError('$name() arg is an empty sequence');
  }
  final key = kw['key'];
  Future<Object?> keyOf(Object? v) async =>
      key == null ? v : await interp.callValue(key, [v], const {}, interp.currentLine, describe: 'key');
  Object? best = items.first;
  Object? bestKey = await keyOf(best);
  for (final v in items.skip(1)) {
    final k = await keyOf(v);
    if (pick(pyCompare(k, bestKey))) {
      best = v;
      bestKey = k;
    }
  }
  return best;
}

/// Python's str.strip family: [chars] null means whitespace.
String _strip(String s, Object? chars, {bool left = true, bool right = true}) {
  if (chars == null) {
    if (left && right) return s.trim();
    return left ? s.trimLeft() : s.trimRight();
  }
  final set = pyStr(chars);
  var start = 0;
  var end = s.length;
  if (left) {
    while (start < end && set.contains(s[start])) {
      start++;
    }
  }
  if (right) {
    while (end > start && set.contains(s[end - 1])) {
      end--;
    }
  }
  return s.substring(start, end);
}

/// Methods available on str / list / dict values, bound to the receiver.
PyNative? methodFor(Object? obj, String name, [Interpreter? interp]) {
  if (obj is String) {
    switch (name) {
      case 'lower':
        return _native(name, (a, _) => obj.toLowerCase());
      case 'upper':
        return _native(name, (a, _) => obj.toUpperCase());
      case 'strip':
        return _native(name, (a, _) => _strip(obj, a.isEmpty ? null : a.first));
      case 'lstrip':
        return _native(name, (a, _) => _strip(obj, a.isEmpty ? null : a.first, right: false));
      case 'rstrip':
        return _native(name, (a, _) => _strip(obj, a.isEmpty ? null : a.first, left: false));
      case 'split':
        return _native(name, (a, _) {
          if (a.isEmpty || a.first == null) {
            return PyList(obj.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList());
          }
          return PyList(obj.split(pyStr(a.first)));
        });
      case 'join':
        return _native(name, (a, _) {
          final parts = pyToList(_one(a, 'join')).map(pyStr).toList();
          checkStrLen(parts.fold<int>(obj.length * (parts.length - 1).clamp(0, maxSeqLen), (n, p) => n + p.length));
          return parts.join(obj);
        });
      case 'startswith':
        return _native(name, (a, _) => obj.startsWith(pyStr(_one(a, name))));
      case 'endswith':
        return _native(name, (a, _) => obj.endsWith(pyStr(_one(a, name))));
      case 'replace':
        return _native(name, (a, _) {
          final from = pyStr(a[0]), to = pyStr(a[1]);
          final hits = from.isEmpty ? obj.length + 1 : from.allMatches(obj).length;
          checkStrLen(obj.length + hits * (to.length - from.length));
          return obj.replaceAll(from, to);
        });
      case 'find':
        return _native(name, (a, _) => obj.indexOf(pyStr(_one(a, name))));
      case 'count':
        return _native(name, (a, _) => pyStr(_one(a, name)).allMatches(obj).length);
      case 'isdigit':
        return _native(name, (a, _) => obj.isNotEmpty && RegExp(r'^\d+$').hasMatch(obj));
      case 'capitalize':
        return _native(name, (a, _) => obj.isEmpty ? obj : obj[0].toUpperCase() + obj.substring(1).toLowerCase());
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
        return _native(name, (a, _) {
          checkSeqLen(obj.items.length + 1);
          obj.items.add(_one(a, name));
          return null;
        });
      case 'extend':
        return _native(name, (a, _) {
          final more = pyToList(_one(a, name));
          checkSeqLen(obj.items.length + more.length);
          obj.items.addAll(more);
          return null;
        });
      case 'pop':
        return _native(name, (a, _) {
          if (obj.items.isEmpty) throw PyRuntimeError('pop from empty list');
          if (a.isEmpty) return obj.items.removeLast();
          var i = pyToInt(a.first);
          if (i < 0) i += obj.items.length;
          if (i < 0 || i >= obj.items.length) throw PyRuntimeError('pop index out of range');
          return obj.items.removeAt(i);
        });
      case 'insert':
        return _native(name, (a, _) {
          if (a.length != 2) throw PyRuntimeError('insert() takes exactly 2 arguments');
          checkSeqLen(obj.items.length + 1);
          var i = pyToInt(a[0]);
          if (i < 0) i += obj.items.length;
          obj.items.insert(i.clamp(0, obj.items.length), a[1]);
          return null;
        });
      case 'remove':
        return _native(name, (a, _) {
          final v = _one(a, name);
          final i = obj.items.indexWhere((x) => pyEquals(x, v));
          if (i < 0) throw PyRuntimeError('list.remove(x): x not in list');
          obj.items.removeAt(i);
          return null;
        });
      case 'index':
        return _native(name, (a, _) {
          final v = _one(a, name);
          final i = obj.items.indexWhere((x) => pyEquals(x, v));
          if (i < 0) throw PyRuntimeError('${pyRepr(v)} is not in list');
          return i;
        });
      case 'count':
        return _native(name, (a, _) {
          final v = _one(a, name);
          return obj.items.where((x) => pyEquals(x, v)).length;
        });
      case 'clear':
        return _native(name, (a, _) {
          obj.items.clear();
          return null;
        });
      case 'reverse':
        return _native(name, (a, _) {
          final r = obj.items.reversed.toList();
          obj.items
            ..clear()
            ..addAll(r);
          return null;
        });
      case 'sort':
        return _native(name, (a, kw) async {
          final sorted = interp == null ? ([...obj.items]..sort(pyCompare)) : await _sorted(interp, obj.items, kw);
          obj.items
            ..clear()
            ..addAll(sorted);
          return null;
        }, {'key', 'reverse'});
      case 'copy':
        return _native(name, (a, _) => PyList(List.of(obj.items)));
    }
  }
  if (obj is PyDict) {
    switch (name) {
      case 'get':
        return _native(name, (a, _) => obj.containsKey(a[0]) ? obj[a[0]] : (a.length > 1 ? a[1] : null));
      case 'keys':
        return _native(name, (a, _) => PyList(obj.keys));
      case 'values':
        return _native(name, (a, _) => PyList(obj.map.values.toList()));
      case 'items':
        return _native(name, (a, _) => PyList([for (final e in obj.map.entries) PyTuple([pyUnkey(e.key), e.value])]));
      case 'pop':
        return _native(name, (a, _) {
          final k = pyKey(a[0]);
          if (!obj.map.containsKey(k)) {
            if (a.length > 1) return a[1];
            throw PyRuntimeError('KeyError: ${pyRepr(a[0])}');
          }
          return obj.map.remove(k);
        });
      case 'clear':
        return _native(name, (a, _) {
          obj.map.clear();
          return null;
        });
    }
  }
  return null;
}

/// Applies a Python format spec subset: `.2f`, `d`, `5d`, `05d`, `>8`, `<8`, `^8`, `%`.
String formatValue(Object? v, String? spec, int? line) {
  if (spec == null || spec.isEmpty) return pyStr(v);
  final m = RegExp(r'^([<>^])?(0)?(\d+)?(?:\.(\d+))?([fdse%])?$').firstMatch(spec);
  if (m == null) throw PyRuntimeError("invalid format spec '$spec'", line);
  final align = m.group(1);
  final zeroPad = m.group(2) != null;
  final width = m.group(3) == null ? 0 : int.parse(m.group(3)!);
  final prec = m.group(4) == null ? null : int.parse(m.group(4)!);
  final type = m.group(5);
  checkStrLen(width);
  if (prec != null && prec > 20 && (type != null || v is num)) {
    throw PyRuntimeError('format precision is too large (the limit is 20)', line);
  }
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
    if (zeroPad && align == null && (v is num || type != null)) {
      // f'{7:02d}' -> '07', f'{-5:04d}' -> '-005': zeros go after the sign.
      final signed = s.startsWith('-') || s.startsWith('+');
      return signed ? s[0] + '0' * pad + s.substring(1) : '0' * pad + s;
    }
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
