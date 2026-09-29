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
/// [map] holds normalized keys; use [pyUnkey] to get the Python value back.
class PyDict {
  final Map<Object?, Object?> map = {};
  Object? operator [](Object? key) => map[pyKey(key)];
  void operator []=(Object? key, Object? value) => map[pyKey(key)] = value;
  bool containsKey(Object? key) => map.containsKey(pyKey(key));
  /// Keys as Python values (tuples restored).
  List<Object?> get keys => [for (final k in map.keys) pyUnkey(k)];
  @override
  String toString() => pyRepr(this);
}

/// Normalizes hashable keys so 1 == 1.0 == True as in Python.
Object? pyKey(Object? k) {
  if (k is bool) return k ? 1 : 0;
  if (k is double && k == k.truncateToDouble() && k.isFinite) return k.toInt();
  if (k is PyTuple) return _TupleKey(k);
  return k;
}

/// Inverse of [pyKey] for tuple keys.
Object? pyUnkey(Object? k) => k is _TupleKey ? k.tuple : k;

/// Hashable wrapper so tuple keys compare by (normalized) value but can be
/// handed back to the program as the original tuple.
class _TupleKey {
  final PyTuple tuple;
  final List<Object?> _parts;
  _TupleKey(this.tuple) : _parts = [for (final v in tuple.items) pyKey(v)];

  @override
  bool operator ==(Object other) {
    if (other is! _TupleKey || other._parts.length != _parts.length) return false;
    for (int i = 0; i < _parts.length; i++) {
      if (_parts[i] != other._parts[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_parts);
}

// ── Resource limits ──────────────────────────────────────────────────────────

/// Largest list/tuple a program may build in one operation. Everything below
/// runs synchronously on the UI thread, so these also bound how long a single
/// builtin can freeze the app.
const int maxSeqLen = 1000000;

/// Largest string a program may build (~10 MB).
const int maxStrLen = 10 * 1024 * 1024;

void checkSeqLen(int n) {
  if (n > maxSeqLen) throw PyRuntimeError('sequence too large (the limit is $maxSeqLen items)');
}

void checkStrLen(int n) {
  if (n > maxStrLen) throw PyRuntimeError('string too large (the limit is $maxStrLen characters)');
}

/// `count` copies of something `unit` long, without overflowing the product.
void checkRepeat(int unit, int count, {required bool string}) {
  if (unit == 0 || count <= 0) return;
  final limit = string ? maxStrLen : maxSeqLen;
  if (count > limit ~/ unit) {
    string ? checkStrLen(limit + 1) : checkSeqLen(limit + 1);
  }
}

/// Materializes any iterable as a Dart list, refusing oversized ranges and
/// strings before allocating.
List<Object?> pyToList(Object? v) {
  if (v is PyRange) checkSeqLen(v.length);
  if (v is String) checkSeqLen(v.length);
  return pyIterate(v).toList();
}

// ── Checked 64-bit integer arithmetic ────────────────────────────────────────
// Dart ints silently wrap at 64 bits; Python ints never overflow. Raise
// instead of printing a wrong answer.

const int _minInt = -0x8000000000000000;

PyRuntimeError _intOverflow() =>
    PyRuntimeError('integer overflow: the result is too big (RoboPython integers must stay within about ±9.2e18)');

int pyAddInt(int a, int b) {
  final r = a + b;
  if (((a ^ r) & (b ^ r)) < 0) throw _intOverflow();
  return r;
}

int pySubInt(int a, int b) {
  final r = a - b;
  if (((a ^ b) & (a ^ r)) < 0) throw _intOverflow();
  return r;
}

int pyMulInt(int a, int b) {
  if (a == 0 || b == 0) return 0;
  if ((a == -1 && b == _minInt) || (b == -1 && a == _minInt)) throw _intOverflow();
  final r = a * b;
  if (r ~/ b != a) throw _intOverflow();
  return r;
}

int pyNegInt(int a) {
  if (a == _minInt) throw _intOverflow();
  return -a;
}

/// base ** exp for exp >= 0, by squaring; overflows within ~64 steps.
int pyPowInt(int base, int exp) {
  var result = 1;
  var b = base;
  var e = exp;
  while (true) {
    if (e & 1 == 1) result = pyMulInt(result, b);
    e >>= 1;
    if (e == 0) return result;
    b = pyMulInt(b, b);
  }
}

/// a + b with overflow checking when both are ints.
num pyAddNum(num a, num b) => (a is int && b is int) ? pyAddInt(a, b) : a + b;

/// Truncates a float to an int, like Python's int(x).
int pyDoubleToInt(double v) {
  if (v.isNaN) throw PyRuntimeError('cannot convert float nan to integer');
  if (v.isInfinite) throw PyRuntimeError('cannot convert float infinity to integer');
  if (v >= 9223372036854775808.0 || v < -9223372036854775808.0) throw _intOverflow();
  return v.truncate();
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

  /// Constant-time `x in range(...)`.
  bool contains(Object? v) {
    int i;
    if (v is bool) {
      i = v ? 1 : 0;
    } else if (v is int) {
      i = v;
    } else if (v is double && v.isFinite && v == v.truncateToDouble() && v.abs() < 9e18) {
      i = v.toInt();
    } else {
      return false;
    }
    if (step > 0 ? (i < start || i >= stop) : (i > start || i <= stop)) return false;
    return (i - start) % step == 0;
  }

  /// Constant-time `range(...)[i]` for an already normalized index.
  int at(int i) => start + i * step;

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
    return '{${v.map.entries.map((e) => '${pyRepr(pyUnkey(e.key))}: ${pyRepr(e.value)}').join(', ')}}';
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
  if (v is PyDict) return v.keys;
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
  if (v is double) return pyDoubleToInt(v);
  if (v is String) {
    final r = int.tryParse(v.trim());
    if (r == null) throw PyRuntimeError("invalid literal for int(): '$v'");
    return r;
  }
  throw PyRuntimeError("int() argument must be a string or a number, not '${pyTypeName(v)}'");
}

/// int(s, base) for 2 <= base <= 36.
int pyParseIntBase(Object? v, int base) {
  if (v is! String) throw PyRuntimeError("int() can't convert non-string with explicit base");
  if (base < 2 || base > 36) throw PyRuntimeError('int() base must be >= 2 and <= 36');
  var s = v.trim().replaceAll('_', '');
  var sign = '';
  if (s.startsWith('-') || s.startsWith('+')) {
    sign = s[0];
    s = s.substring(1);
  }
  final prefix = const {16: '0x', 8: '0o', 2: '0b'}[base];
  if (prefix != null && s.toLowerCase().startsWith(prefix)) s = s.substring(2);
  final r = s.isEmpty ? null : int.tryParse('$sign$s', radix: base);
  if (r == null) throw PyRuntimeError("invalid literal for int() with base $base: '$v'");
  return r;
}

double pyToDouble(Object? v) {
  if (v is bool) return v ? 1.0 : 0.0;
  if (v is num) return v.toDouble();
  if (v is String) {
    switch (v.trim().toLowerCase()) {
      case 'inf':
      case '+inf':
      case 'infinity':
      case '+infinity':
        return double.infinity;
      case '-inf':
      case '-infinity':
        return double.negativeInfinity;
      case 'nan':
      case '+nan':
      case '-nan':
        return double.nan;
    }
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
  if (a is int && b is int) {
    if (a == _minInt && b == -1) throw _intOverflow();
    // Exact integer division (going through a double loses precision above 2^53).
    final q = a ~/ b;
    return (q * b != a && (a < 0) != (b < 0)) ? q - 1 : q;
  }
  return (a.toDouble() / b.toDouble()).floorToDouble();
}
