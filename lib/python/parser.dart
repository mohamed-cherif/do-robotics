/// Recursive-descent parser for the RoboPython subset.
library;

import 'ast.dart';
import 'lexer.dart';

class Parser {
  final List<Token> _t;
  int _i = 0;

  /// Nesting limit for brackets / unary operators / `**` chains. The parser
  /// and evaluator are recursive; without a limit ~1000 nested brackets
  /// overflow the Dart stack instead of giving a syntax error.
  static const int maxNesting = 100;
  int _nesting = 0;

  Parser(List<Token> tokens) : _t = tokens;

  T _nested<T>(T Function() parse) {
    if (++_nesting > maxNesting) {
      throw PySyntaxError('expression is nested too deeply (limit $maxNesting)', _cur.line);
    }
    try {
      return parse();
    } finally {
      _nesting--;
    }
  }

  static Module parse(String source) {
    final tokens = Lexer(source).tokenize();
    return Parser(tokens).parseModule();
  }

  Token get _cur => _t[_i];
  Token get _peek => _i + 1 < _t.length ? _t[_i + 1] : _t.last;

  bool _isOp(String op) => _cur.type == TokenType.op && _cur.text == op;
  bool _isName(String name) => _cur.type == TokenType.name && _cur.text == name;
  bool _isKeyword(String kw) => _isName(kw);

  Token _advance() => _t[_i++];

  Token _expectOp(String op) {
    if (!_isOp(op)) {
      throw PySyntaxError("expected '$op' but found '${_describe(_cur)}'", _cur.line);
    }
    return _advance();
  }

  void _expectKeyword(String kw) {
    if (!_isKeyword(kw)) {
      throw PySyntaxError("expected '$kw' but found '${_describe(_cur)}'", _cur.line);
    }
    _advance();
  }

  String _describe(Token t) {
    switch (t.type) {
      case TokenType.newline:
        return 'end of line';
      case TokenType.indent:
        return 'indent';
      case TokenType.dedent:
        return 'dedent';
      case TokenType.eof:
        return 'end of file';
      default:
        return t.text;
    }
  }

  Module parseModule() {
    final body = <Stmt>[];
    while (_cur.type != TokenType.eof) {
      if (_cur.type == TokenType.newline) {
        _advance();
        continue;
      }
      body.addAll(_parseStatement());
    }
    return Module(body);
  }

  // A "statement" line may contain several simple statements separated by ';'.
  List<Stmt> _parseStatement() {
    if (_cur.type == TokenType.name) {
      switch (_cur.text) {
        case 'if':
          return [_parseIf()];
        case 'while':
          return [_parseWhile()];
        case 'for':
          return [_parseFor()];
        case 'def':
          return [_parseDef()];
        case 'class':
          throw PySyntaxError('classes are not supported in RoboPython', _cur.line);
        case 'try':
          throw PySyntaxError('try/except is not supported in RoboPython', _cur.line);
        case 'with':
          throw PySyntaxError("'with' is not supported in RoboPython", _cur.line);
      }
    }
    final stmts = <Stmt>[];
    stmts.add(_parseSimpleStatement());
    while (_isOp(';')) {
      _advance();
      if (_cur.type == TokenType.newline || _cur.type == TokenType.eof) break;
      stmts.add(_parseSimpleStatement());
    }
    _endOfLine();
    return stmts;
  }

  void _endOfLine() {
    if (_cur.type == TokenType.newline) {
      _advance();
    } else if (_cur.type != TokenType.eof && _cur.type != TokenType.dedent) {
      throw PySyntaxError("unexpected '${_describe(_cur)}'", _cur.line);
    }
  }

  Stmt _parseSimpleStatement() {
    final line = _cur.line;
    if (_cur.type == TokenType.name) {
      switch (_cur.text) {
        case 'del':
        case 'nonlocal':
        case 'raise':
        case 'assert':
        case 'yield':
          throw PySyntaxError("'${_cur.text}' is not supported in RoboPython", line);
        case 'return':
          _advance();
          if (_cur.type == TokenType.newline || _cur.type == TokenType.eof || _isOp(';')) {
            return Return(null, line);
          }
          return Return(_parseExprOrTuple(), line);
        case 'break':
          _advance();
          return Break(line);
        case 'continue':
          _advance();
          return Continue(line);
        case 'pass':
          _advance();
          return Pass(line);
        case 'global':
          _advance();
          final names = <String>[_expectName()];
          while (_isOp(',')) {
            _advance();
            names.add(_expectName());
          }
          return Global(names, line);
        case 'import':
          _advance();
          final mods = <String>[];
          final bindings = <String, String>{};
          do {
            if (mods.isNotEmpty) _advance(); // ','
            final mod = _parseDottedName();
            mods.add(mod);
            if (_isKeyword('as')) {
              _advance();
              bindings[_expectName()] = mod;
            } else {
              final top = mod.split('.').first;
              bindings[top] = top;
            }
          } while (_isOp(','));
          return Import(mods, line, bindings);
        case 'from':
          _advance();
          final mod = _parseDottedName();
          _expectKeyword('import');
          final bindings = <String, String>{};
          if (_isOp('*')) {
            _advance();
            bindings['*'] = mod;
          } else {
            do {
              if (bindings.isNotEmpty) _advance(); // ','
              final name = _expectName();
              var alias = name;
              if (_isKeyword('as')) {
                _advance();
                alias = _expectName();
              }
              bindings[alias] = '$mod.$name';
            } while (_isOp(','));
          }
          return Import([mod], line, bindings);
      }
    }

    final expr = _parseExprOrTuple();
    if (_isOp('=')) {
      _advance();
      var value = _parseExprOrTuple();
      // chained assignment a = b = 1
      final targets = <Expr>[expr];
      while (_isOp('=')) {
        _advance();
        targets.add(value);
        value = _parseExprOrTuple();
      }
      _checkAssignable(targets.first);
      if (targets.length == 1) return Assign(expr, value, line);
      // Desugar a = b = v into a = v; b = v is not possible with one Stmt —
      // keep the first target and nest the rest as value assignments is
      // wrong; instead reject chained assignment (rare in robot code).
      throw PySyntaxError('chained assignment is not supported', line);
    }
    for (final aug in const ['+=', '-=', '*=', '/=', '//=', '%=', '**=']) {
      if (_isOp(aug)) {
        _advance();
        _checkAssignable(expr);
        final value = _parseExprOrTuple();
        return AugAssign(expr, aug.substring(0, aug.length - 1), value, line);
      }
    }
    return ExprStmt(expr, line);
  }

  void _checkAssignable(Expr e) {
    if (e is Name || e is Attribute || e is Subscript) return;
    if (e is TupleLit || e is ListLit) {
      final elements = e is TupleLit ? e.elements : (e as ListLit).elements;
      for (final el in elements) {
        _checkAssignable(el);
      }
      return;
    }
    throw PySyntaxError('cannot assign to expression', e.line);
  }

  String _expectName() {
    if (_cur.type != TokenType.name || Lexer.keywords.contains(_cur.text)) {
      throw PySyntaxError("expected a name but found '${_describe(_cur)}'", _cur.line);
    }
    return _advance().text;
  }

  String _parseDottedName() {
    final parts = <String>[_expectName()];
    while (_isOp('.')) {
      _advance();
      parts.add(_expectName());
    }
    return parts.join('.');
  }

  List<Stmt> _parseBlock() {
    _expectOp(':');
    if (_cur.type != TokenType.newline) {
      // Single-line body: if x: do()
      final stmts = <Stmt>[];
      stmts.add(_parseSimpleStatement());
      while (_isOp(';')) {
        _advance();
        if (_cur.type == TokenType.newline || _cur.type == TokenType.eof) break;
        stmts.add(_parseSimpleStatement());
      }
      _endOfLine();
      return stmts;
    }
    _advance(); // newline
    if (_cur.type != TokenType.indent) {
      throw PySyntaxError('expected an indented block', _cur.line);
    }
    _advance();
    final body = <Stmt>[];
    while (_cur.type != TokenType.dedent && _cur.type != TokenType.eof) {
      if (_cur.type == TokenType.newline) {
        _advance();
        continue;
      }
      body.addAll(_parseStatement());
    }
    if (_cur.type == TokenType.dedent) _advance();
    return body;
  }

  Stmt _parseIf() {
    final line = _cur.line;
    _advance(); // if / elif
    final test = _parseExpr();
    final body = _parseBlock();
    List<Stmt> orelse = const [];
    if (_isKeyword('elif')) {
      orelse = [_parseIf()];
    } else if (_isKeyword('else')) {
      _advance();
      orelse = _parseBlock();
    }
    return If(test, body, orelse, line);
  }

  Stmt _parseWhile() {
    final line = _cur.line;
    _advance();
    final test = _parseExpr();
    final body = _parseBlock();
    if (_isKeyword('else')) {
      throw PySyntaxError("'while ... else' is not supported", _cur.line);
    }
    return While(test, body, line);
  }

  Stmt _parseFor() {
    final line = _cur.line;
    _advance();
    final target = _parseTargetList();
    _expectKeyword('in');
    final iter = _parseExprOrTuple();
    final body = _parseBlock();
    if (_isKeyword('else')) {
      throw PySyntaxError("'for ... else' is not supported", _cur.line);
    }
    return For(target, iter, body, line);
  }

  Expr _parseTargetList() {
    final line = _cur.line;
    final first = _parsePrimaryTarget();
    if (!_isOp(',')) return first;
    final elements = <Expr>[first];
    while (_isOp(',')) {
      _advance();
      if (_isKeyword('in')) break;
      elements.add(_parsePrimaryTarget());
    }
    return TupleLit(elements, line);
  }

  Expr _parsePrimaryTarget() {
    if (_isOp('(')) {
      _advance();
      final inner = _parseTargetList();
      _expectOp(')');
      return inner;
    }
    final e = _parsePostfix();
    _checkAssignable(e);
    return e;
  }

  Stmt _parseDef() {
    final line = _cur.line;
    _advance();
    final name = _expectName();
    _expectOp('(');
    final params = _parseParams(')');
    _expectOp(')');
    if (_isOp('->')) {
      _advance();
      _parseExpr(); // annotation ignored
    }
    final body = _parseBlock();
    return FunctionDef(name, params, body, line);
  }

  List<Param> _parseParams(String closer, {bool annotations = true}) {
    final params = <Param>[];
    while (!_isOp(closer)) {
      final name = _expectName();
      if (annotations && _isOp(':')) {
        _advance();
        _parseExpr(); // annotation ignored
      }
      Expr? def;
      if (_isOp('=')) {
        _advance();
        def = _parseExpr();
      }
      params.add(Param(name, def));
      if (_isOp(',')) {
        _advance();
      } else {
        break;
      }
    }
    return params;
  }

  // ── Expressions ────────────────────────────────────────────────────────────

  /// Expression possibly followed by ',' making a tuple (statement context).
  Expr _parseExprOrTuple() {
    final line = _cur.line;
    final first = _parseExpr();
    if (!_isOp(',')) return first;
    final elements = <Expr>[first];
    while (_isOp(',')) {
      _advance();
      if (_cur.type == TokenType.newline || _cur.type == TokenType.eof || _isOp('=') || _isOp(')') || _isOp(';')) {
        break;
      }
      elements.add(_parseExpr());
    }
    return TupleLit(elements, line);
  }

  Expr _parseExpr() => _nested(_parseExprUnchecked);

  Expr _parseExprUnchecked() {
    if (_isKeyword('lambda')) {
      final line = _cur.line;
      _advance();
      final params = _parseParams(':', annotations: false);
      _expectOp(':');
      final body = _parseExpr();
      return Lambda(params, body, line);
    }
    final line = _cur.line;
    final body = _parseOr();
    if (_isKeyword('if')) {
      _advance();
      final test = _parseOr();
      _expectKeyword('else');
      final orelse = _parseExpr();
      return IfExp(test, body, orelse, line);
    }
    return body;
  }

  Expr _parseOr() {
    final line = _cur.line;
    var left = _parseAnd();
    if (_isKeyword('or')) {
      final values = <Expr>[left];
      while (_isKeyword('or')) {
        _advance();
        values.add(_parseAnd());
      }
      left = BoolOp('or', values, line);
    }
    return left;
  }

  Expr _parseAnd() {
    final line = _cur.line;
    var left = _parseNot();
    if (_isKeyword('and')) {
      final values = <Expr>[left];
      while (_isKeyword('and')) {
        _advance();
        values.add(_parseNot());
      }
      left = BoolOp('and', values, line);
    }
    return left;
  }

  Expr _parseNot() {
    if (_isKeyword('not')) {
      final line = _cur.line;
      _advance();
      return UnaryOp('not', _nested(_parseNot), line);
    }
    return _parseComparison();
  }

  Expr _parseComparison() {
    final line = _cur.line;
    final left = _parseArith();
    final ops = <String>[];
    final comps = <Expr>[];
    while (true) {
      String? op;
      if (_cur.type == TokenType.op && const ['<', '<=', '>', '>=', '==', '!='].contains(_cur.text)) {
        op = _advance().text;
      } else if (_isKeyword('in')) {
        _advance();
        op = 'in';
      } else if (_isKeyword('not') && _peek.type == TokenType.name && _peek.text == 'in') {
        _advance();
        _advance();
        op = 'not in';
      } else if (_isKeyword('is')) {
        _advance();
        if (_isKeyword('not')) {
          _advance();
          op = 'is not';
        } else {
          op = 'is';
        }
      }
      if (op == null) break;
      ops.add(op);
      comps.add(_parseArith());
    }
    if (ops.isEmpty) return left;
    return Compare(left, ops, comps, line);
  }

  Expr _parseArith() {
    var left = _parseTerm();
    while (_cur.type == TokenType.op && (_cur.text == '+' || _cur.text == '-')) {
      final line = _cur.line;
      final op = _advance().text;
      left = BinOp(op, left, _parseTerm(), line);
    }
    return left;
  }

  Expr _parseTerm() {
    var left = _parseFactor();
    while (_cur.type == TokenType.op && const ['*', '/', '//', '%'].contains(_cur.text)) {
      final line = _cur.line;
      final op = _advance().text;
      left = BinOp(op, left, _parseFactor(), line);
    }
    return left;
  }

  Expr _parseFactor() {
    if (_cur.type == TokenType.op && (_cur.text == '-' || _cur.text == '+')) {
      final line = _cur.line;
      final op = _advance().text;
      return UnaryOp(op, _nested(_parseFactor), line);
    }
    return _parsePower();
  }

  Expr _parsePower() {
    final base = _parsePostfix();
    if (_isOp('**')) {
      final line = _cur.line;
      _advance();
      return BinOp('**', base, _nested(_parseFactor), line); // right-assoc
    }
    return base;
  }

  Expr _parsePostfix() {
    var e = _parseAtom();
    while (true) {
      if (_isOp('.')) {
        final line = _cur.line;
        _advance();
        final name = _expectName();
        e = Attribute(e, name, line);
      } else if (_isOp('(')) {
        final line = _cur.line;
        _advance();
        final args = <Expr>[];
        final kwargs = <String, Expr>{};
        while (!_isOp(')')) {
          if (_cur.type == TokenType.name && _peek.type == TokenType.op && _peek.text == '=' &&
              !Lexer.keywords.contains(_cur.text)) {
            final key = _advance().text;
            _advance(); // =
            kwargs[key] = _parseExpr();
          } else {
            if (kwargs.isNotEmpty) {
              throw PySyntaxError('positional argument follows keyword argument', _cur.line);
            }
            args.add(_parseExpr());
            if (_isKeyword('for')) {
              throw PySyntaxError('generator expressions are not supported in RoboPython', _cur.line);
            }
          }
          if (_isOp(',')) {
            _advance();
          } else {
            break;
          }
        }
        _expectOp(')');
        e = Call(e, args, kwargs, line);
      } else if (_isOp('[')) {
        final line = _cur.line;
        _advance();
        Expr index;
        final lower = _isOp(':') ? null : _parseExpr();
        if (_isOp(':')) {
          // slice: [lower:upper] or [lower:upper:step], every part optional
          _advance();
          final upper = (_isOp(']') || _isOp(':')) ? null : _parseExpr();
          Expr? step;
          if (_isOp(':')) {
            _advance();
            step = _isOp(']') ? null : _parseExpr();
          }
          index = SliceExpr(lower, upper, line, step);
        } else {
          index = lower!;
        }
        _expectOp(']');
        e = Subscript(e, index, line);
      } else {
        break;
      }
    }
    return e;
  }

  Expr _parseAtom() {
    final t = _cur;
    final line = t.line;
    switch (t.type) {
      case TokenType.number:
        _advance();
        return NumLit(_parseNumber(t.text, line), line);
      case TokenType.string:
        _advance();
        var value = t.text;
        // implicit concatenation "a" "b"
        while (_cur.type == TokenType.string) {
          value += _advance().text;
        }
        return StrLit(value, line);
      case TokenType.fstring:
        _advance();
        return _parseFString(t.text, line);
      case TokenType.name:
        switch (t.text) {
          case 'True':
            _advance();
            return BoolLit(true, line);
          case 'False':
            _advance();
            return BoolLit(false, line);
          case 'None':
            _advance();
            return NoneLit(line);
        }
        if (Lexer.keywords.contains(t.text)) {
          throw PySyntaxError("unexpected keyword '${t.text}'", line);
        }
        _advance();
        return Name(t.text, line);
      case TokenType.op:
        if (t.text == '(') {
          _advance();
          if (_isOp(')')) {
            _advance();
            return TupleLit(const [], line);
          }
          final first = _parseExpr();
          if (_isKeyword('for')) {
            throw PySyntaxError('generator expressions are not supported in RoboPython', _cur.line);
          }
          if (_isOp(',')) {
            final elements = <Expr>[first];
            while (_isOp(',')) {
              _advance();
              if (_isOp(')')) break;
              elements.add(_parseExpr());
            }
            _expectOp(')');
            return TupleLit(elements, line);
          }
          _expectOp(')');
          return first;
        }
        if (t.text == '[') {
          _advance();
          final elements = <Expr>[];
          while (!_isOp(']')) {
            elements.add(_parseExpr());
            if (_isKeyword('for')) {
              throw PySyntaxError('list comprehensions are not supported', _cur.line);
            }
            if (_isOp(',')) {
              _advance();
            } else {
              break;
            }
          }
          _expectOp(']');
          return ListLit(elements, line);
        }
        if (t.text == '{') {
          _advance();
          final keys = <Expr>[];
          final values = <Expr>[];
          while (!_isOp('}')) {
            keys.add(_parseExpr());
            if (!_isOp(':')) {
              throw PySyntaxError(
                  _isKeyword('for')
                      ? 'set comprehensions are not supported in RoboPython'
                      : 'set literals are not supported in RoboPython (use a list or a dict)',
                  _cur.line);
            }
            _advance();
            values.add(_parseExpr());
            if (_isKeyword('for')) {
              throw PySyntaxError('dict comprehensions are not supported in RoboPython', _cur.line);
            }
            if (_isOp(',')) {
              _advance();
            } else {
              break;
            }
          }
          _expectOp('}');
          return DictLit(keys, values, line);
        }
        break;
      default:
        break;
    }
    throw PySyntaxError("unexpected '${_describe(t)}'", line);
  }

  num _parseNumber(String text, int line) {
    if (text.startsWith('0x') || text.startsWith('0X')) {
      return int.tryParse(text.substring(2), radix: 16) ??
          (throw PySyntaxError('integer literal is too large', line));
    }
    final asInt = int.tryParse(text);
    if (asInt != null) return asInt;
    if (RegExp(r'^\d+$').hasMatch(text)) {
      throw PySyntaxError('integer literal is too large', line);
    }
    final asDouble = double.tryParse(text);
    if (asDouble != null) return asDouble;
    throw PySyntaxError("invalid number '$text'", line);
  }

  /// Parses the body of an f-string into literal parts and embedded expressions.
  Expr _parseFString(String text, int line) {
    final parts = <Object>[];
    final buf = StringBuffer();
    int i = 0;
    while (i < text.length) {
      final c = text[i];
      if (c == '\\' && i + 1 < text.length && (text[i + 1] == '{' || text[i + 1] == '}')) {
        buf.write(text[i + 1]);
        i += 2;
        continue;
      }
      if (c == '{') {
        if (i + 1 < text.length && text[i + 1] == '{') {
          buf.write('{');
          i += 2;
          continue;
        }
        // find matching close brace (no nesting of braces inside expr supported except strings)
        int depth = 1;
        int j = i + 1;
        while (j < text.length && depth > 0) {
          if (text[j] == '{') depth++;
          if (text[j] == '}') depth--;
          if (depth > 0) j++;
        }
        if (depth != 0) throw PySyntaxError("f-string: expecting '}'", line);
        var inner = text.substring(i + 1, j);
        String? format;
        // split off :format (but not inside brackets)
        int bracket = 0;
        for (int k = 0; k < inner.length; k++) {
          final ch = inner[k];
          if (ch == '(' || ch == '[') bracket++;
          if (ch == ')' || ch == ']') bracket--;
          if (ch == ':' && bracket == 0) {
            format = inner.substring(k + 1);
            inner = inner.substring(0, k);
            break;
          }
        }
        if (inner.trim().isEmpty) throw PySyntaxError('f-string: empty expression', line);
        if (buf.isNotEmpty) {
          parts.add(buf.toString());
          buf.clear();
        }
        // Lex from the f-string's line so syntax and runtime errors in the
        // field point at the right line.
        final exprTokens = Lexer(inner.trim(), line: line).tokenize();
        final sub = Parser(exprTokens).._nesting = _nesting;
        final expr = sub._parseExpr();
        if (sub._cur.type != TokenType.newline && sub._cur.type != TokenType.eof) {
          throw PySyntaxError('f-string: invalid expression', line);
        }
        parts.add(FStrField(expr, format));
        i = j + 1;
        continue;
      }
      if (c == '}') {
        if (i + 1 < text.length && text[i + 1] == '}') {
          buf.write('}');
          i += 2;
          continue;
        }
        throw PySyntaxError("f-string: single '}' is not allowed", line);
      }
      buf.write(c);
      i++;
    }
    if (buf.isNotEmpty) parts.add(buf.toString());
    return FStr(parts, line);
  }
}
