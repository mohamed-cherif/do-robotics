/// Runtime value model for the RoboPython interpreter.
///
/// Plain Dart values are used wherever they map 1:1 to Python:
///   None → null, bool, int, double, String, list → PyList, dict → PyDict.
/// Everything else is one of the classes below.
library;

import 'dart:async';

/// Thrown for Python-level runtime errors. Carries the source line.
class PyRuntimeError implements Exception {
  final String message;
  int? line;
  PyRuntimeError(this.message, [this.line]);
  @override
  String toString() => line == null ? message : 'line $line: $message';
}

/// Raised by `robot.stop()` / `exit()` to end the program cleanly.
class PyExit implements Exception {
  const PyExit();
}

/// Raised when the host cancels execution (STOP button).
class PyCancelled implements Exception {
  const PyCancelled();
}

/// Mutable Python list.
class PyList {
  final List<Object?> items;
  PyList([List<Object?>? items]) : items = items ?? [];
  @override
  String toString() => pyRepr(this);
}

/// Immutable Python tuple.
class PyTuple {
  final List<Object?> items;
  const PyTuple(this.items);
  @override
  String toString() => pyRepr(this);
}

/// Python dict with Python equality semantics on keys (via pyKey).
class PyDict {
  final Map<Object?, Object?> map = {};
  Object? operator [](Object? key) => map[pyKey(key)];
  void operator []=(Object? key, Object? value) => map[pyKey(key)] = value;
  bool containsKey(Object? key) => map.containsKey(pyKey(key));
  @override
  String toString() => pyRepr(this);
}

/// Normalizes hashable keys so 1 == 1.0 == True as in Python.
Object? pyKey(Object? k) {
  if (k is bool) return k ? 1 : 0;
  if (k is double && k == k.truncateToDouble() && k.isFinite) return k.toInt();
  if (k is PyTuple) return k.items.map(pyRepr).join('\u0000');
  return k;
}

/// A Dart-implemented callable. [call] receives positional args and keyword args.
typedef NativeFn = FutureOr<Object?> Function(List<Object?> args, Map<String, Object?> kwargs);

class PyNative {
  final String name;
  final NativeFn call;
  const PyNative(this.name, this.call);
  @override
  String toString() => '<built-in function $name>';
}

/// Lazily evaluated attribute (property) on a [PyObject].
typedef NativeGetter = FutureOr<Object?> Function();

/// A namespace-like object: modules, robot devices, etc.
class PyObject {
  final String typeName;
  final Map<String, Object?> attrs = {};
  final Map<String, NativeGetter> getters = {};
  final Map<String, FutureOr<void> Function(Object?)> setters = {};
  PyObject(this.typeName);

  void method(String name, NativeFn fn) => attrs[name] = PyNative(name, fn);
  void getter(String name, NativeGetter fn) => getters[name] = fn;

  @override
  String toString() => '<$typeName>';
}

/// Python range object (lazy).
class PyRange {
  final int start, stop, step;
  PyRange(this.start, this.stop, this.step);
  int get length {
    if (step > 0 && start < stop) return ((stop - start - 1) ~/ step) + 1;
    if (step < 0 && start > stop) return ((start - stop - 1) ~/ (-step)) + 1;
    return 0;
  }

  Iterable<int> get values sync* {
    if (step > 0) {
      for (int i = start; i < stop; i += step) {
        yield i;
      }
    } else {
      for (int i = start; i > stop; i += step) {
        yield i;
      }
    }
  }

  @override
  String toString() => step == 1 ? 'range($start, $stop)' : 'range($start, $stop, $step)';
}

// ── Conversions ──────────────────────────────────────────────────────────────

bool pyTruthy(Object? v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v.isNotEmpty;
  if (v is PyList) return v.items.isNotEmpty;
  if (v is PyTuple) return v.items.isNotEmpty;
  if (v is PyDict) return v.map.isNotEmpty;
  if (v is PyRange) return v.length > 0;
  return true;
}

String pyTypeName(Object? v) {
  if (v == null) return 'NoneType';
  if (v is bool) return 'bool';
  if (v is int) return 'int';
  if (v is double) return 'float';
  if (v is String) return 'str';
  if (v is PyList) return 'list';
  if (v is PyTuple) return 'tuple';
  if (v is PyDict) return 'dict';
  if (v is PyRange) return 'range';
  if (v is PyNative) return 'builtin_function_or_method';
  if (v is PyObject) return v.typeName;
  return 'function';
}

String _formatDouble(double d) {
  if (d.isNaN) return 'nan';
  if (d.isInfinite) return d > 0 ? 'inf' : '-inf';
  if (d == d.truncateToDouble() && d.abs() < 1e16) return '${d.toInt()}.0';
  var s = d.toString();
  return s;
}

/// str(v)
String pyStr(Object? v) {
  if (v == null) return 'None';
  if (v is bool) return v ? 'True' : 'False';
  if (v is int) return v.toString();
  if (v is double) return _formatDouble(v);
  if (v is String) return v;
  if (v is PyList || v is PyTuple || v is PyDict) return pyRepr(v);
  return v.toString();
}

/// repr(v)
String pyRepr(Object? v) {
  if (v is String) {
    final esc = v.replaceAll('\\', '\\\\').replaceAll('\n', '\\n').replaceAll('\t', '\\t');
    if (esc.contains("'") && !esc.contains('"')) return '"$esc"';
    return "'${esc.replaceAll("'", "\\'")}'";
  }
  if (v is PyList) return '[${v.items.map(pyRepr).join(', ')}]';
  if (v is PyTuple) {
    if (v.items.length == 1) return '(${pyRepr(v.items.first)},)';
    return '(${v.items.map(pyRepr).join(', ')})';
  }
  if (v is PyDict) {
    return '{${v.map.entries.map((e) => '${pyRepr(e.key)}: ${pyRepr(e.value)}').join(', ')}}';
  }
  return pyStr(v);
}

/// Python == semantics for the supported types.
bool pyEquals(Object? a, Object? b) {
  if (a is bool) a = a ? 1 : 0;
  if (b is bool) b = b ? 1 : 0;
  if (a is num && b is num) return a == b;
  if (a is PyList && b is PyList) return _seqEquals(a.items, b.items);
  if (a is PyTuple && b is PyTuple) return _seqEquals(a.items, b.items);
  if (a is PyDict && b is PyDict) {
    if (a.map.length != b.map.length) return false;
    for (final e in a.map.entries) {
      if (!b.map.containsKey(e.key) || !pyEquals(e.value, b.map[e.key])) return false;
    }
    return true;
  }
  return a == b;
}

bool _seqEquals(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (!pyEquals(a[i], b[i])) return false;
  }
  return true;
}

/// Python ordering (<) for numbers, strings, and sequences.
int pyCompare(Object? a, Object? b) {
  if (a is bool) a = a ? 1 : 0;
  if (b is bool) b = b ? 1 : 0;
  if (a is num && b is num) return a.compareTo(b);
  if (a is String && b is String) return a.compareTo(b);
  final la = a is PyList ? a.items : (a is PyTuple ? a.items : null);
  final lb = b is PyList ? b.items : (b is PyTuple ? b.items : null);
  if (la != null && lb != null) {
    for (int i = 0; i < la.length && i < lb.length; i++) {
      final c = pyCompare(la[i], lb[i]);
      if (c != 0) return c;
    }
    return la.length.compareTo(lb.length);
  }
  throw PyRuntimeError("'<' not supported between '${pyTypeName(a)}' and '${pyTypeName(b)}'");
}

/// Iterates any Python iterable.
Iterable<Object?> pyIterate(Object? v) {
  if (v is PyList) return List<Object?>.from(v.items); // snapshot: safe to mutate during loop
  if (v is PyTuple) return v.items;
  if (v is PyRange) return v.values;
  if (v is String) return v.split('');
  if (v is PyDict) return List<Object?>.from(v.map.keys);
  throw PyRuntimeError("'${pyTypeName(v)}' object is not iterable");
}

int pyLen(Object? v) {
  if (v is String) return v.length;
  if (v is PyList) return v.items.length;
  if (v is PyTuple) return v.items.length;
  if (v is PyDict) return v.map.length;
  if (v is PyRange) return v.length;
  throw PyRuntimeError("object of type '${pyTypeName(v)}' has no len()");
}

num pyToNum(Object? v, [String context = 'operand']) {
  if (v is bool) return v ? 1 : 0;
  if (v is num) return v;
  throw PyRuntimeError("unsupported $context type: '${pyTypeName(v)}'");
}

int pyToInt(Object? v) {
  if (v is bool) return v ? 1 : 0;
  if (v is int) return v;
  if (v is double) {
    if (!v.isFinite) throw PyRuntimeError('cannot convert float $v to integer');
    return v.truncate();
  }
  if (v is String) {
    final r = int.tryParse(v.trim());
    if (r == null) throw PyRuntimeError("invalid literal for int(): '$v'");
    return r;
  }
  throw PyRuntimeError("int() argument must be a string or a number, not '${pyTypeName(v)}'");
}

double pyToDouble(Object? v) {
  if (v is bool) return v ? 1.0 : 0.0;
  if (v is num) return v.toDouble();
  if (v is String) {
    final r = double.tryParse(v.trim());
    if (r == null) throw PyRuntimeError("could not convert string to float: '$v'");
    return r;
  }
  throw PyRuntimeError("float() argument must be a string or a number, not '${pyTypeName(v)}'");
}

/// Python floor-mod (sign follows the divisor).
num pyMod(num a, num b) {
  if (b == 0) throw PyRuntimeError('integer modulo by zero');
  if (a is int && b is int) {
    final r = a % b; // Dart % is already non-negative for positive b
    return (r != 0 && (b < 0)) ? r + b : r;
  }
  final r = a.toDouble() - b.toDouble() * (a.toDouble() / b.toDouble()).floorToDouble();
  return r;
}

num pyFloorDiv(num a, num b) {
  if (b == 0) throw PyRuntimeError('integer division or modulo by zero');
  if (a is int && b is int) return (a / b).floor();
  return (a.toDouble() / b.toDouble()).floorToDouble();
}
