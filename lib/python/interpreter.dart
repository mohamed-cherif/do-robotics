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

  /// For function scopes: every name the function body assigns (Python makes
  /// these local for the whole body). Reading one before it is assigned is an
  /// error instead of silently reading the outer variable.
  final Set<String> localNames;
  Scope(this.parent, [this.localNames = const {}]);

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
  final Set<String> localNames;
  PyFunction(this.name, this.params, this.body, this.closure, this.defaults,
      {this.lambdaBody, this.localNames = const {}});
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

  /// Default Python-level call depth limit (CPython's default is also 1000).
  static const int maxRecursionDepth = 1000;
  final int recursionLimit;
  int _callDepth = 0;

  Interpreter({
    required this.onPrint,
    this.onLine,
    this.recursionLimit = maxRecursionDepth,
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
    if (!seconds.isFinite || seconds > 1e9) {
      throw PyRuntimeError('sleep length must be a finite number of seconds (at most 1e9)');
    }
    if (seconds < 0) seconds = 0;
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
          scope.vars[s.name] = PyFunction(s.name, s.params, s.body, scope, defaults,
              localNames: _assignedNames(s.body));
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
          for (final b in s.bindings.entries) {
            final path = b.value.split('.');
            Object? value = globals.vars[path.first];
            for (final attr in path.skip(1)) {
              try {
                value = await getAttr(value, attr, s.line);
              } on PyRuntimeError {
                throw PyRuntimeError("cannot import name '$attr' from '${path.first}'", s.line);
              }
            }
            if (b.key == '*') {
              if (value is PyObject) {
                for (final e in value.attrs.entries) {
                  await _assign(Name(e.key, s.line), e.value, scope);
                }
              }
            } else {
              await _assign(Name(b.key, s.line), value, scope);
            }
          }
        default:
          throw PyRuntimeError('unsupported statement', s.line);
      }
    } on PyRuntimeError catch (e) {
      e.line ??= s.line;
      rethrow;
    } on PyExit {
      rethrow;
    } on PyCancelled {
      rethrow;
    } on _BreakSignal {
      rethrow;
    } on _ContinueSignal {
      rethrow;
    } on _ReturnSignal {
      rethrow;
    } catch (e) {
      // Last resort: never let a raw Dart error (RangeError, StackOverflowError
      // from a self-containing list, ...) escape without a line number.
      throw PyRuntimeError(_dartErrorReason(e), s.line);
    }
  }

  /// Names a function body assigns (its locals), minus `global` declarations.
  static Set<String> _assignedNames(List<Stmt> body) {
    final names = <String>{};
    final declaredGlobal = <String>{};
    void target(Expr t) {
      if (t is Name) {
        names.add(t.id);
      } else if (t is TupleLit) {
        t.elements.forEach(target);
      } else if (t is ListLit) {
        t.elements.forEach(target);
      }
    }

    void walk(List<Stmt> stmts) {
      for (final s in stmts) {
        switch (s) {
          case Assign():
            target(s.target);
          case AugAssign():
            target(s.target);
          case For():
            target(s.target);
            walk(s.body);
          case While():
            walk(s.body);
          case If():
            walk(s.body);
            walk(s.orelse);
          case FunctionDef():
            names.add(s.name);
          case Import():
            names.addAll(s.bindings.keys.where((k) => k != '*'));
          case Global():
            declaredGlobal.addAll(s.names);
          default:
            break;
        }
      }
    }

    walk(body);
    return names.difference(declaredGlobal);
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
        await _assignSequence(target.elements, value, scope, target.line);
      case ListLit():
        await _assignSequence(target.elements, value, scope, target.line);
      default:
        throw PyRuntimeError('cannot assign to expression', target.line);
    }
  }

  Future<void> _assignSequence(List<Expr> targets, Object? value, Scope scope, int line) async {
    final items = pyToList(value);
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
        checkStrLen(buf.length);
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
            final n = pyToNum(v);
            return n is int ? pyNegInt(n) : -n;
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
    } else if (scope.localNames.contains(n.id) && !scope.vars.containsKey(n.id)) {
      throw PyRuntimeError(
          "local variable '${n.id}' referenced before assignment "
          "(to change the variable outside the function, add 'global ${n.id}')",
          n.line);
    } else if (scope.lookup(n.id, out)) {
      return out.first;
    }
    throw PyRuntimeError("name '${n.id}' is not defined", n.line);
  }

  Future<int?> _sliceBound(Expr? e, Scope scope) async {
    if (e == null) return null;
    final v = await eval(e, scope);
    return v == null ? null : pyToInt(v);
  }

  Future<Object?> _subscript(Object? obj, Subscript e, Scope scope) async {
    if (e.index is SliceExpr) {
      final s = e.index as SliceExpr;
      final lo = await _sliceBound(s.lower, scope);
      final hi = await _sliceBound(s.upper, scope);
      final step = await _sliceBound(s.step, scope) ?? 1;
      if (step == 0) throw PyRuntimeError('slice step cannot be zero', e.line);
      List<Object?> items;
      if (obj is String) {
        if (step != 1) return [for (final i in _stepIndices(lo, hi, step, obj.length)) obj[i]].join();
        final r = _sliceRange(lo, hi, obj.length);
        return obj.substring(r.$1, r.$2);
      } else if (obj is PyList) {
        items = obj.items;
      } else if (obj is PyTuple) {
        items = obj.items;
      } else {
        throw PyRuntimeError("'${pyTypeName(obj)}' object is not subscriptable", e.line);
      }
      final List<Object?> sub;
      if (step != 1) {
        sub = [for (final i in _stepIndices(lo, hi, step, items.length)) items[i]];
      } else {
        final r = _sliceRange(lo, hi, items.length);
        sub = items.sublist(r.$1, r.$2);
      }
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
    if (obj is PyRange) return obj.at(_normIndex(i, obj.length, e.line));
    throw PyRuntimeError("'${pyTypeName(obj)}' object is not subscriptable", e.line);
  }

  /// Indices selected by a slice with a step other than 1 (CPython's rules).
  List<int> _stepIndices(int? lo, int? hi, int step, int length) {
    int start, stop;
    if (step > 0) {
      start = lo == null ? 0 : (lo < 0 ? math.max(lo + length, 0) : math.min(lo, length));
      stop = hi == null ? length : (hi < 0 ? math.max(hi + length, 0) : math.min(hi, length));
    } else {
      start = lo == null ? length - 1 : (lo < 0 ? math.max(lo + length, -1) : math.min(lo, length - 1));
      stop = hi == null ? -1 : (hi < 0 ? math.max(hi + length, -1) : math.min(hi, length - 1));
    }
    return [for (int i = start; step > 0 ? i < stop : i > stop; i += step) i];
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
      if (l is String && r is String) {
        checkStrLen(l.length + r.length);
        return l + r;
      }
      if (l is PyList && r is PyList) {
        checkSeqLen(l.items.length + r.items.length);
        return PyList([...l.items, ...r.items]);
      }
      if (l is PyTuple && r is PyTuple) {
        checkSeqLen(l.items.length + r.items.length);
        return PyTuple([...l.items, ...r.items]);
      }
      if (l is String || r is String) {
        throw PyRuntimeError('can only concatenate str (not "${pyTypeName(l is String ? r : l)}") to str');
      }
    }
    if (op == '*') {
      // Size is checked before allocating: "a" * 10**9 must not freeze the app.
      if ((l is String || l is PyList) && (r is int || r is bool)) return _repeat(l!, pyToInt(r));
      if ((r is String || r is PyList) && (l is int || l is bool)) return _repeat(r!, pyToInt(l));
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
        return pyAddNum(a, b);
      case '-':
        return (a is int && b is int) ? pySubInt(a, b) : a - b;
      case '*':
        return (a is int && b is int) ? pyMulInt(a, b) : a * b;
      case '/':
        if (b == 0) throw PyRuntimeError('division by zero');
        return a / b;
      case '//':
        return pyFloorDiv(a, b);
      case '%':
        return pyMod(a, b);
      case '**':
        if (a is int && b is int && b >= 0) return pyPowInt(a, b);
        return math.pow(a, b);
    }
    throw PyRuntimeError('unsupported operator $op');
  }

  Object _repeat(Object seq, int times) {
    if (seq is String) {
      checkRepeat(seq.length, times, string: true);
      return times <= 0 ? '' : seq * times;
    }
    final items = (seq as PyList).items;
    checkRepeat(items.length, times, string: false);
    return PyList([for (int i = 0; i < times; i++) ...items]);
  }

  String _percentFormat(String fmt, List<Object?> args) {
    int argIdx = 0;
    final re = RegExp(r'%(\.\d+)?([sdifr%])');
    final result = fmt.replaceAllMapped(re, (m) {
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
    checkStrLen(result.length);
    return result;
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
    if (container is PyRange) return container.contains(item); // O(1), not a scan
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
    final m = methodFor(obj, name, this);
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
      } on PyExit {
        rethrow;
      } on PyCancelled {
        rethrow;
      } on PySyntaxError {
        rethrow;
      } catch (e) {
        // e.g. a missing argument surfacing as a RangeError inside the builtin.
        throw PyRuntimeError('${fn.name}(): ${_dartErrorReason(e)}', line);
      }
    }
    if (fn is PyFunction) {
      if (_callDepth >= recursionLimit) {
        throw PyRuntimeError('maximum recursion depth exceeded', line);
      }
      _callDepth++;
      try {
        // Start the body on a fresh microtask. Otherwise every Python call
        // runs synchronously inside its caller's Dart frames, so recursion
        // depth becomes native stack depth; on a small stack (phones, or the
        // test zone) that overflowed long before the limit above.
        await Future<void>.value();
        return await _callFunction(fn, args, kwargs, line);
      } finally {
        _callDepth--;
        // Finishing a Python call completes the caller's future, which can
        // synchronously complete *its* caller's, and so on down the whole
        // Python stack; a few hundred frames of that overflow the Dart stack
        // (and the StackOverflowError escapes as an uncaught async error, so
        // run() never completes). One microtask hop per call breaks the chain.
        await Future<void>.value();
      }
    }
    throw PyRuntimeError("'${pyTypeName(fn)}' object is not callable ($describe)", line);
  }

  Future<Object?> _callFunction(PyFunction fn, List<Object?> args, Map<String, Object?> kwargs, int line) async {
    final scope = Scope(fn.closure, fn.localNames);
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
}

/// Short, kid-readable reason for a Dart error raised inside a builtin.
String _dartErrorReason(Object e) {
  if (e is StackOverflowError) return 'value is nested too deeply (or contains itself)';
  if (e is UnsupportedError && '${e.message}'.contains('Infinity or NaN')) {
    return 'cannot convert infinity or NaN to an integer';
  }
  if (e is RangeError || e is StateError) return 'missing argument or value out of range';
  if (e is ArgumentError) return 'invalid argument';
  if (e is FormatException) return e.message;
  return 'internal error (${e.runtimeType})';
}
