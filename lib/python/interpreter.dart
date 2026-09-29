/// Async tree-walking interpreter for the RoboPython subset.
///
/// Every statement awaits, so native robot calls (BLE writes, waits, TTS) can
/// be awaited transparently and the host can cancel between statements.
library;

import 'dart:async';
import 'dart:math' as math;

import 'ast.dart';
import 'builtins.dart';
import 'lexer.dart';
import 'parser.dart';
import 'values.dart';

class _BreakSignal implements Exception {
  const _BreakSignal();
}

class _ContinueSignal implements Exception {
  const _ContinueSignal();
}

class _ReturnSignal implements Exception {
  final Object? value;
  const _ReturnSignal(this.value);
}

/// Lexical scope.
class Scope {
  final Map<String, Object?> vars = {};
  final Scope? parent;
  final Set<String> globalNames = {};
  Scope(this.parent);

  Scope get root {
    var s = this;
    while (s.parent != null) {
      s = s.parent!;
    }
    return s;
  }

  bool lookup(String name, List<Object?> out) {
    if (vars.containsKey(name)) {
      out.add(vars[name]);
      return true;
    }
    return parent?.lookup(name, out) ?? false;
  }
}

/// User-defined function (closure over its defining scope).
class PyFunction {
  final String name;
  final List<Param> params;
  final List<Stmt> body;
  final Scope closure;
  final Expr? lambdaBody;
  final Map<String, Object?> defaults;
  PyFunction(this.name, this.params, this.body, this.closure, this.defaults, {this.lambdaBody});
  @override
  String toString() => '<function $name>';
}

class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class Interpreter {
  final Scope globals = Scope(null);
  final CancelToken cancel;
  final void Function(String text) onPrint;
  /// Called when execution moves to a new source line (statement granularity).
  final void Function(int line)? onLine;

  int _stepsSinceYield = 0;
  int _currentLine = 0;
  int get currentLine => _currentLine;

  Interpreter({
    required this.onPrint,
    this.onLine,
    CancelToken? cancel,
    Map<String, Object?> extraGlobals = const {},
  }) : cancel = cancel ?? CancelToken() {
    installBuiltins(this);
    globals.vars.addAll(extraGlobals);
  }

  /// Parse and run [source]. Throws [PySyntaxError], [PyRuntimeError],
  /// [PyCancelled]; returns normally on completion or [PyExit].
  Future<void> run(String source) async {
    final module = Parser.parse(source);
    try {
      await execBlock(module.body, globals);
    } on PyExit {
      // normal termination
    } on _ReturnSignal {
      // 'return' at module level: treat as exit
    } on _BreakSignal {
      throw PyRuntimeError("'break' outside loop", _currentLine);
    } on _ContinueSignal {
      throw PyRuntimeError("'continue' outside loop", _currentLine);
    }
  }

  // ── Cooperative scheduling ─────────────────────────────────────────────────

  Future<void> _checkpoint() async {
    if (cancel.isCancelled) throw const PyCancelled();
    if (++_stepsSinceYield >= 200) {
      _stepsSinceYield = 0;
      await Future.delayed(Duration.zero);
      if (cancel.isCancelled) throw const PyCancelled();
    }
  }

  /// Yield to the event loop unconditionally (used once per loop iteration so
  /// sensor streams and the UI keep running inside `while True:`).
  Future<void> yieldToHost() async {
    _stepsSinceYield = 0;
    await Future.delayed(Duration.zero);
    if (cancel.isCancelled) throw const PyCancelled();
  }

  /// Cancellable sleep.
  Future<void> sleep(double seconds) async {
    final deadline = DateTime.now().add(Duration(microseconds: (seconds * 1e6).round()));
    while (true) {
      if (cancel.isCancelled) throw const PyCancelled();
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      await Future.delayed(remaining < const Duration(milliseconds: 50) ? remaining : const Duration(milliseconds: 50));
    }
    if (cancel.isCancelled) throw const PyCancelled();
  }

  // ── Statements ─────────────────────────────────────────────────────────────

  Future<void> execBlock(List<Stmt> stmts, Scope scope) async {
    for (final s in stmts) {
      await exec(s, scope);
    }
  }

  Future<void> exec(Stmt s, Scope scope) async {
    _currentLine = s.line;
    onLine?.call(s.line);
    await _checkpoint();
    try {
      switch (s) {
        case ExprStmt():
          await eval(s.expr, scope);
        case Assign():
          final v = await eval(s.value, scope);
          await _assign(s.target, v, scope);
        case AugAssign():
          final cur = await eval(s.target, scope);
          final rhs = await eval(s.value, scope);
          await _assign(s.target, _binary(s.op, cur, rhs), scope);
        case If():
          if (pyTruthy(await eval(s.test, scope))) {
            await execBlock(s.body, scope);
          } else if (s.orelse.isNotEmpty) {
            await execBlock(s.orelse, scope);
          }
        case While():
          while (pyTruthy(await eval(s.test, scope))) {
            try {
              await execBlock(s.body, scope);
            } on _BreakSignal {
              break;
            } on _ContinueSignal {
              // fallthrough to next iteration
            }
            await yieldToHost();
          }
        case For():
          final iterable = pyIterate(await eval(s.iter, scope));
          for (final item in iterable) {
            await _assign(s.target, item, scope);
            try {
              await execBlock(s.body, scope);
            } on _BreakSignal {
              break;
            } on _ContinueSignal {
              // next
            }
            await yieldToHost();
          }
        case FunctionDef():
          final defaults = <String, Object?>{};
          for (final p in s.params) {
            if (p.defaultValue != null) defaults[p.name] = await eval(p.defaultValue!, scope);
          }
          scope.vars[s.name] = PyFunction(s.name, s.params, s.body, scope, defaults);
        case Return():
          throw _ReturnSignal(s.value == null ? null : await eval(s.value!, scope));
        case Break():
          throw const _BreakSignal();
        case Continue():
          throw const _ContinueSignal();
        case Pass():
          break;
        case Global():
          scope.globalNames.addAll(s.names);
        case Import():
          for (final m in s.modules) {
            final top = m.split('.').first;
            if (!globals.vars.containsKey(top)) {
              throw PyRuntimeError("No module named '$m' (available: robot, time, math, random)", s.line);
            }
          }
        default:
          throw PyRuntimeError('unsupported statement', s.line);
      }
    } on PyRuntimeError catch (e) {
      e.line ??= s.line;
      rethrow;
    }
  }

  Future<void> _assign(Expr target, Object? value, Scope scope) async {
    switch (target) {
      case Name():
        if (scope.globalNames.contains(target.id)) {
          scope.root.vars[target.id] = value;
        } else {
          scope.vars[target.id] = value;
        }
      case Attribute():
        final obj = await eval(target.object, scope);
        if (obj is PyObject) {
          final setter = obj.setters[target.name];
          if (setter != null) {
            await setter(value);
          } else if (obj.getters.containsKey(target.name)) {
            throw PyRuntimeError("attribute '${target.name}' of ${obj.typeName} is read-only", target.line);
          } else {
            obj.attrs[target.name] = value;
          }
        } else {
          throw PyRuntimeError("'${pyTypeName(obj)}' object has no attribute '${target.name}'", target.line);
        }
      case Subscript():
        final obj = await eval(target.object, scope);
        if (target.index is SliceExpr) {
          throw PyRuntimeError('slice assignment is not supported', target.line);
        }
        final idx = await eval(target.index, scope);
        if (obj is PyList) {
          obj.items[_normIndex(pyToInt(idx), obj.items.length, target.line)] = value;
        } else if (obj is PyDict) {
          obj[idx] = value;
        } else {
          throw PyRuntimeError("'${pyTypeName(obj)}' object does not support item assignment", target.line);
        }
      case TupleLit():
        _assignSequence(target.elements, value, scope, target.line);
      case ListLit():
        _assignSequence(target.elements, value, scope, target.line);
      default:
        throw PyRuntimeError('cannot assign to expression', target.line);
    }
  }

  Future<void> _assignSequence(List<Expr> targets, Object? value, Scope scope, int line) async {
    final items = pyIterate(value).toList();
    if (items.length != targets.length) {
      throw PyRuntimeError(
          'cannot unpack ${items.length} values into ${targets.length} targets', line);
    }
    for (int i = 0; i < targets.length; i++) {
      await _assign(targets[i], items[i], scope);
    }
  }

  int _normIndex(int i, int length, int line) {
    final n = i < 0 ? i + length : i;
    if (n < 0 || n >= length) throw PyRuntimeError('index out of range', line);
    return n;
  }

  // ── Expressions ────────────────────────────────────────────────────────────

  Future<Object?> eval(Expr e, Scope scope) async {
    switch (e) {
      case NumLit():
        return e.value;
      case StrLit():
        return e.value;
      case BoolLit():
        return e.value;
      case NoneLit():
        return null;
      case Name():
        return _lookup(e, scope);
      case FStr():
        final buf = StringBuffer();
        for (final part in e.parts) {
          if (part is String) {
            buf.write(part);
          } else if (part is FStrField) {
            final v = await eval(part.expr, scope);
            buf.write(formatValue(v, part.format, e.line));
          }
        }
        return buf.toString();
      case ListLit():
        final items = <Object?>[];
        for (final el in e.elements) {
          items.add(await eval(el, scope));
        }
        return PyList(items);
      case TupleLit():
        final items = <Object?>[];
        for (final el in e.elements) {
          items.add(await eval(el, scope));
        }
        return PyTuple(items);
      case DictLit():
        final d = PyDict();
        for (int i = 0; i < e.keys.length; i++) {
          d[await eval(e.keys[i], scope)] = await eval(e.values[i], scope);
        }
        return d;
      case Attribute():
        final obj = await eval(e.object, scope);
        return getAttr(obj, e.name, e.line);
      case Subscript():
        final obj = await eval(e.object, scope);
        return _subscript(obj, e, scope);
      case Call():
        final fn = await eval(e.func, scope);
        final args = <Object?>[];
        for (final a in e.args) {
          args.add(await eval(a, scope));
        }
        final kwargs = <String, Object?>{};
        for (final entry in e.kwargs.entries) {
          kwargs[entry.key] = await eval(entry.value, scope);
        }
        return callValue(fn, args, kwargs, e.line, describe: _describeCallee(e.func));
      case UnaryOp():
        final v = await eval(e.operand, scope);
        switch (e.op) {
          case 'not':
            return !pyTruthy(v);
          case '-':
            return -pyToNum(v);
          case '+':
            return pyToNum(v);
        }
        throw PyRuntimeError('bad unary operator ${e.op}', e.line);
      case BinOp():
        final l = await eval(e.left, scope);
        final r = await eval(e.right, scope);
        try {
          return _binary(e.op, l, r);
        } on PyRuntimeError catch (err) {
          err.line ??= e.line;
          rethrow;
        }
      case Compare():
        var left = await eval(e.left, scope);
        for (int i = 0; i < e.ops.length; i++) {
          final right = await eval(e.comparators[i], scope);
          if (!_compare(e.ops[i], left, right, e.line)) return false;
          left = right;
        }
        return true;
      case BoolOp():
        Object? last;
        for (final v in e.values) {
          last = await eval(v, scope);
          if (e.op == 'and' && !pyTruthy(last)) return last;
          if (e.op == 'or' && pyTruthy(last)) return last;
        }
        return last;
      case IfExp():
        return pyTruthy(await eval(e.test, scope))
            ? await eval(e.body, scope)
            : await eval(e.orelse, scope);
      case Lambda():
        return PyFunction('<lambda>', e.params, const [], scope, const {}, lambdaBody: e.body);
      case SliceExpr():
        throw PyRuntimeError('slice outside of subscript', e.line);
      default:
        throw PyRuntimeError('unsupported expression', e.line);
    }
  }

  String _describeCallee(Expr f) {
    if (f is Name) return f.id;
    if (f is Attribute) return '${_describeCallee(f.object)}.${f.name}';
    return 'expression';
  }

  Object? _lookup(Name n, Scope scope) {
    final out = <Object?>[];
    if (scope.globalNames.contains(n.id)) {
      if (scope.root.vars.containsKey(n.id)) return scope.root.vars[n.id];
    } else if (scope.lookup(n.id, out)) {
      return out.first;
    }
    throw PyRuntimeError("name '${n.id}' is not defined", n.line);
  }

  Future<Object?> _subscript(Object? obj, Subscript e, Scope scope) async {
    if (e.index is SliceExpr) {
      final s = e.index as SliceExpr;
      final lo = s.lower == null ? null : pyToInt(await eval(s.lower!, scope));
      final hi = s.upper == null ? null : pyToInt(await eval(s.upper!, scope));
      List<Object?> items;
      if (obj is String) {
        final r = _sliceRange(lo, hi, obj.length);
        return obj.substring(r.$1, r.$2);
      } else if (obj is PyList) {
        items = obj.items;
      } else if (obj is PyTuple) {
        items = obj.items;
      } else {
        throw PyRuntimeError("'${pyTypeName(obj)}' object is not subscriptable", e.line);
      }
      final r = _sliceRange(lo, hi, items.length);
      final sub = items.sublist(r.$1, r.$2);
      return obj is PyTuple ? PyTuple(sub) : PyList(sub);
    }
    final idx = await eval(e.index, scope);
    if (obj is PyDict) {
      if (!obj.containsKey(idx)) throw PyRuntimeError('KeyError: ${pyRepr(idx)}', e.line);
      return obj[idx];
    }
    final i = pyToInt(idx);
    if (obj is String) return obj[_normIndex(i, obj.length, e.line)];
    if (obj is PyList) return obj.items[_normIndex(i, obj.items.length, e.line)];
    if (obj is PyTuple) return obj.items[_normIndex(i, obj.items.length, e.line)];
    if (obj is PyRange) {
      final vals = obj.values.toList();
      return vals[_normIndex(i, vals.length, e.line)];
    }
    throw PyRuntimeError("'${pyTypeName(obj)}' object is not subscriptable", e.line);
  }

  (int, int) _sliceRange(int? lo, int? hi, int length) {
    int a = lo ?? 0;
    int b = hi ?? length;
    if (a < 0) a += length;
    if (b < 0) b += length;
    a = a.clamp(0, length);
    b = b.clamp(0, length);
    if (b < a) b = a;
    return (a, b);
  }

  Object? _binary(String op, Object? l, Object? r) {
    // String / list operators
    if (op == '+') {
      if (l is String && r is String) return l + r;
      if (l is PyList && r is PyList) return PyList([...l.items, ...r.items]);
      if (l is PyTuple && r is PyTuple) return PyTuple([...l.items, ...r.items]);
      if (l is String || r is String) {
        throw PyRuntimeError('can only concatenate str (not "${pyTypeName(l is String ? r : l)}") to str');
      }
    }
    if (op == '*') {
      if (l is String && (r is int || r is bool)) return l * pyToInt(r);
      if (r is String && (l is int || l is bool)) return r * pyToInt(l);
      if (l is PyList && (r is int || r is bool)) {
        return PyList([for (int i = 0; i < pyToInt(r); i++) ...l.items]);
      }
      if (r is PyList && (l is int || l is bool)) {
        return PyList([for (int i = 0; i < pyToInt(l); i++) ...r.items]);
      }
    }
    if (op == '%' && l is String) {
      // printf-style formatting: "%d apples" % 3  or  "%s %s" % (a, b)
      final args = r is PyTuple ? r.items : [r];
      return _percentFormat(l, args);
    }
    final a = pyToNum(l, 'operand');
    final b = pyToNum(r, 'operand');
    switch (op) {
      case '+':
        return a + b;
      case '-':
        return a - b;
      case '*':
        return a * b;
      case '/':
        if (b == 0) throw PyRuntimeError('division by zero');
        return a / b;
      case '//':
        return pyFloorDiv(a, b);
      case '%':
        return pyMod(a, b);
      case '**':
        if (a is int && b is int && b >= 0) {
          return math.pow(a, b).toInt();
        }
        return math.pow(a, b);
    }
    throw PyRuntimeError('unsupported operator $op');
  }

  String _percentFormat(String fmt, List<Object?> args) {
    int argIdx = 0;
    final re = RegExp(r'%(\.\d+)?([sdifr%])');
    return fmt.replaceAllMapped(re, (m) {
      final conv = m.group(2)!;
      if (conv == '%') return '%';
      if (argIdx >= args.length) throw PyRuntimeError('not enough arguments for format string');
      final v = args[argIdx++];
      final prec = m.group(1);
      switch (conv) {
        case 'd':
        case 'i':
          return pyToInt(v).toString();
        case 'f':
          final p = prec == null ? 6 : int.parse(prec.substring(1));
          return pyToDouble(v).toStringAsFixed(p);
        case 'r':
          return pyRepr(v);
        default:
          return pyStr(v);
      }
    });
  }

  bool _compare(String op, Object? l, Object? r, int line) {
    switch (op) {
      case '==':
        return pyEquals(l, r);
      case '!=':
        return !pyEquals(l, r);
      case 'is':
        return identical(l, r) || (l == null && r == null) || (l is bool && r is bool && l == r);
      case 'is not':
        return !_compare('is', l, r, line);
      case 'in':
        return _contains(r, l, line);
      case 'not in':
        return !_contains(r, l, line);
    }
    try {
      final c = pyCompare(l, r);
      switch (op) {
        case '<':
          return c < 0;
        case '<=':
          return c <= 0;
        case '>':
          return c > 0;
        case '>=':
          return c >= 0;
      }
    } on PyRuntimeError catch (e) {
      e.line ??= line;
      rethrow;
    }
    throw PyRuntimeError('bad comparison $op', line);
  }

  bool _contains(Object? container, Object? item, int line) {
    if (container is String) {
      if (item is! String) throw PyRuntimeError("'in <string>' requires string as left operand", line);
      return container.contains(item);
    }
    if (container is PyDict) return container.containsKey(item);
    for (final v in pyIterate(container)) {
      if (pyEquals(v, item)) return true;
    }
    return false;
  }

  /// Attribute lookup on any value: PyObject attrs/getters, str/list methods.
  FutureOr<Object?> getAttr(Object? obj, String name, int line) {
    if (obj is PyObject) {
      if (obj.attrs.containsKey(name)) return obj.attrs[name];
      final g = obj.getters[name];
      if (g != null) return g();
      throw PyRuntimeError("'${obj.typeName}' has no attribute '$name'", line);
    }
    final m = methodFor(obj, name);
    if (m != null) return m;
    throw PyRuntimeError("'${pyTypeName(obj)}' object has no attribute '$name'", line);
  }

  /// Invokes a callable value.
  Future<Object?> callValue(Object? fn, List<Object?> args, Map<String, Object?> kwargs, int line,
      {String describe = 'object'}) async {
    if (fn is PyNative) {
      try {
        return await fn.call(args, kwargs);
      } on PyRuntimeError catch (e) {
        e.line ??= line;
        rethrow;
      }
    }
    if (fn is PyFunction) {
      final scope = Scope(fn.closure);
      // bind params
      final params = fn.params;
      if (args.length > params.length) {
        throw PyRuntimeError(
            '${fn.name}() takes ${params.length} positional argument${params.length == 1 ? '' : 's'} but ${args.length} were given',
            line);
      }
      for (int i = 0; i < params.length; i++) {
        final p = params[i];
        if (i < args.length) {
          scope.vars[p.name] = args[i];
        } else if (kwargs.containsKey(p.name)) {
          scope.vars[p.name] = kwargs[p.name];
        } else if (fn.defaults.containsKey(p.name)) {
          scope.vars[p.name] = fn.defaults[p.name];
        } else {
          throw PyRuntimeError("${fn.name}() missing required argument: '${p.name}'", line);
        }
      }
      for (final k in kwargs.keys) {
        if (!params.any((p) => p.name == k)) {
          throw PyRuntimeError("${fn.name}() got an unexpected keyword argument '$k'", line);
        }
      }
      if (fn.lambdaBody != null) return eval(fn.lambdaBody!, scope);
      try {
        await execBlock(fn.body, scope);
      } on _ReturnSignal catch (r) {
        return r.value;
      }
      return null;
    }
    throw PyRuntimeError("'${pyTypeName(fn)}' object is not callable ($describe)", line);
  }
}
