/// Tokenizer for the RoboPython subset. Produces INDENT/DEDENT/NEWLINE tokens
/// like CPython's tokenizer so the parser can work on a flat token list.
library;

enum TokenType { name, number, string, fstring, op, newline, indent, dedent, eof }

class Token {
  final TokenType type;
  final String text;
  final int line;
  final int col;
  const Token(this.type, this.text, this.line, this.col);

  @override
  String toString() => '$type(${text.replaceAll('\n', r'\n')})@$line:$col';
}

class PySyntaxError implements Exception {
  final String message;
  final int line;
  PySyntaxError(this.message, this.line);
  @override
  String toString() => 'line $line: $message';
}

class Lexer {
  final String src;
  int _pos = 0;
  int _line;
  int _lineStart = 0;
  int _parenDepth = 0;
  bool _atLineStart = true;
  final List<int> _indents = [0];
  final List<Token> _tokens = [];

  static const Set<String> keywords = {
    'if', 'elif', 'else', 'while', 'for', 'in', 'def', 'return', 'break',
    'continue', 'pass', 'and', 'or', 'not', 'True', 'False', 'None', 'import',
    'from', 'global', 'as', 'is', 'lambda', 'class', 'try', 'except', 'with',
  };

  // Longest operators first.
  static const List<String> _ops = [
    '**=', '//=', '**', '//', '<=', '>=', '==', '!=', '+=', '-=', '*=', '/=', '%=', '->',
    '+', '-', '*', '/', '%', '<', '>', '=', '(', ')', '[', ']', '{', '}', ',', ':', '.', ';',
  ];

  /// [line] is the line number of the first character (f-string fields are
  /// lexed separately but must report the f-string's line). CRLF / CR line
  /// endings (Windows and some Android editors) are normalized to LF.
  Lexer(String src, {int line = 1})
      : src = src.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
        _line = line;

  List<Token> tokenize() {
    while (_pos < src.length) {
      if (_atLineStart && _parenDepth == 0) {
        _handleIndentation();
        if (_pos >= src.length) break;
        continue;
      }
      final c = src[_pos];
      if (c == '\n') {
        _pos++;
        // Inside brackets a newline is just whitespace; indentation is only
        // measured at the start of a logical line.
        if (_parenDepth == 0) {
          _emit(TokenType.newline, '\n');
          _atLineStart = true;
        }
        _line++;
        _lineStart = _pos;
        continue;
      }
      if (c == '\r' || c == ' ' || c == '\t') {
        _pos++;
        continue;
      }
      if (c == '#') {
        while (_pos < src.length && src[_pos] != '\n') {
          _pos++;
        }
        continue;
      }
      if (c == '\\' && _pos + 1 < src.length && src[_pos + 1] == '\n') {
        // explicit line continuation
        _pos += 2;
        _line++;
        _lineStart = _pos;
        continue;
      }
      if (_isIdentStart(c)) {
        _lexNameOrString();
        continue;
      }
      if (_isDigit(c) || (c == '.' && _pos + 1 < src.length && _isDigit(src[_pos + 1]))) {
        _lexNumber();
        continue;
      }
      if (c == '"' || c == "'") {
        _lexString(prefix: '');
        continue;
      }
      if (_lexOp()) continue;
      throw PySyntaxError("unexpected character '$c'", _line);
    }
    if (_parenDepth > 0) {
      throw PySyntaxError('unclosed bracket', _line);
    }
    if (_tokens.isNotEmpty && _tokens.last.type != TokenType.newline) {
      _emit(TokenType.newline, '\n');
    }
    while (_indents.length > 1) {
      _indents.removeLast();
      _emit(TokenType.dedent, '');
    }
    _emit(TokenType.eof, '');
    return _tokens;
  }

  void _emit(TokenType t, String text) {
    _tokens.add(Token(t, text, _line, _pos - _lineStart));
  }

  void _handleIndentation() {
    // Measure leading whitespace; tabs count as 4.
    int width = 0;
    int p = _pos;
    while (p < src.length) {
      final c = src[p];
      if (c == ' ') {
        width++;
      } else if (c == '\t') {
        width += 4;
      } else {
        break;
      }
      p++;
    }
    // Blank line or comment-only line: skip entirely, no tokens.
    if (p >= src.length || src[p] == '\n' || src[p] == '\r' || src[p] == '#') {
      while (p < src.length && src[p] != '\n') {
        p++;
      }
      if (p < src.length) {
        p++; // consume newline
        _line++;
        _lineStart = p;
      }
      _pos = p;
      return;
    }
    _pos = p;
    _atLineStart = false;
    if (width > _indents.last) {
      _indents.add(width);
      _emit(TokenType.indent, '');
    } else {
      while (width < _indents.last) {
        _indents.removeLast();
        _emit(TokenType.dedent, '');
      }
      if (width != _indents.last) {
        throw PySyntaxError('unindent does not match any outer indentation level', _line);
      }
    }
  }

  bool _isIdentStart(String c) {
    final u = c.codeUnitAt(0);
    return (u >= 65 && u <= 90) || (u >= 97 && u <= 122) || c == '_' || u > 127;
  }

  bool _isIdentPart(String c) => _isIdentStart(c) || _isDigit(c);

  bool _isDigit(String c) {
    final u = c.codeUnitAt(0);
    return u >= 48 && u <= 57;
  }

  void _lexNameOrString() {
    final start = _pos;
    while (_pos < src.length && _isIdentPart(src[_pos])) {
      _pos++;
    }
    final text = src.substring(start, _pos);
    // String prefixes: f, r, fr, rf (case-insensitive)
    if (_pos < src.length && (src[_pos] == '"' || src[_pos] == "'")) {
      final lower = text.toLowerCase();
      if (lower == 'f' || lower == 'r' || lower == 'fr' || lower == 'rf' || lower == 'b') {
        _lexString(prefix: lower);
        return;
      }
    }
    _tokens.add(Token(TokenType.name, text, _line, start - _lineStart));
  }

  void _lexNumber() {
    final start = _pos;
    bool isFloat = false;
    if (src[_pos] == '0' && _pos + 1 < src.length && (src[_pos + 1] == 'x' || src[_pos + 1] == 'X')) {
      _pos += 2;
      while (_pos < src.length && RegExp(r'[0-9a-fA-F_]').hasMatch(src[_pos])) {
        _pos++;
      }
      final text = src.substring(start, _pos).replaceAll('_', '');
      if (text.length == 2) throw PySyntaxError('invalid hexadecimal literal', _line);
      _tokens.add(Token(TokenType.number, text, _line, start - _lineStart));
      return;
    }
    while (_pos < src.length && (_isDigit(src[_pos]) || src[_pos] == '_')) {
      _pos++;
    }
    if (_pos < src.length && src[_pos] == '.') {
      isFloat = true;
      _pos++;
      while (_pos < src.length && (_isDigit(src[_pos]) || src[_pos] == '_')) {
        _pos++;
      }
    }
    if (_pos < src.length && (src[_pos] == 'e' || src[_pos] == 'E')) {
      final save = _pos;
      _pos++;
      if (_pos < src.length && (src[_pos] == '+' || src[_pos] == '-')) _pos++;
      if (_pos < src.length && _isDigit(src[_pos])) {
        isFloat = true;
        while (_pos < src.length && _isDigit(src[_pos])) {
          _pos++;
        }
      } else {
        _pos = save;
      }
    }
    var text = src.substring(start, _pos).replaceAll('_', '');
    if (isFloat && text.startsWith('.')) text = '0$text';
    _tokens.add(Token(TokenType.number, text, _line, start - _lineStart));
  }

  void _lexString({required String prefix}) {
    final startCol = _pos - _lineStart;
    final startLine = _line;
    final quote = src[_pos];
    final isRaw = prefix.contains('r');
    final isF = prefix.contains('f');
    bool triple = false;
    if (_pos + 2 < src.length && src[_pos + 1] == quote && src[_pos + 2] == quote) {
      triple = true;
      _pos += 3;
    } else {
      _pos += 1;
    }
    final buf = StringBuffer();
    while (true) {
      if (_pos >= src.length) {
        throw PySyntaxError('unterminated string', startLine);
      }
      final c = src[_pos];
      if (triple) {
        if (c == quote && _pos + 2 < src.length && src[_pos + 1] == quote && src[_pos + 2] == quote) {
          _pos += 3;
          break;
        }
      } else if (c == quote) {
        _pos++;
        break;
      } else if (c == '\n') {
        throw PySyntaxError('unterminated string', startLine);
      }
      if (c == '\\' && !isRaw && _pos + 1 < src.length) {
        final n = src[_pos + 1];
        _pos += 2;
        switch (n) {
          case 'n':
            buf.write('\n');
            break;
          case 't':
            buf.write('\t');
            break;
          case 'r':
            buf.write('\r');
            break;
          case '\\':
            buf.write('\\');
            break;
          case "'":
            buf.write("'");
            break;
          case '"':
            buf.write('"');
            break;
          case '\n':
            _line++;
            _lineStart = _pos;
            break;
          case '{':
          case '}':
            // Keep the backslash for f-string brace handling.
            buf.write('\\$n');
            break;
          default:
            buf.write('\\$n');
        }
        continue;
      }
      if (c == '\n') {
        _line++;
        _lineStart = _pos + 1;
      }
      buf.write(c);
      _pos++;
    }
    _tokens.add(Token(isF ? TokenType.fstring : TokenType.string, buf.toString(), startLine, startCol));
  }

  bool _lexOp() {
    for (final op in _ops) {
      if (src.startsWith(op, _pos)) {
        if (op == '(' || op == '[' || op == '{') _parenDepth++;
        if (op == ')' || op == ']' || op == '}') {
          _parenDepth = _parenDepth > 0 ? _parenDepth - 1 : 0;
        }
        _tokens.add(Token(TokenType.op, op, _line, _pos - _lineStart));
        _pos += op.length;
        return true;
      }
    }
    return false;
  }
}
