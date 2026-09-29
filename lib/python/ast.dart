/// AST node classes for the RoboPython subset.
library;

abstract class Node {
  final int line;
  const Node(this.line);
}

// ── Expressions ──────────────────────────────────────────────────────────────

abstract class Expr extends Node {
  const Expr(super.line);
}

class NumLit extends Expr {
  final num value;
  const NumLit(this.value, int line) : super(line);
}

class StrLit extends Expr {
  final String value;
  const StrLit(this.value, int line) : super(line);
}

/// f-string: parts are either String (literal) or FStrField.
class FStr extends Expr {
  final List<Object> parts;
  const FStr(this.parts, int line) : super(line);
}

class FStrField {
  final Expr expr;
  final String? format; // e.g. ".2f"
  const FStrField(this.expr, this.format);
}

class BoolLit extends Expr {
  final bool value;
  const BoolLit(this.value, int line) : super(line);
}

class NoneLit extends Expr {
  const NoneLit(super.line);
}

class Name extends Expr {
  final String id;
  const Name(this.id, int line) : super(line);
}

class ListLit extends Expr {
  final List<Expr> elements;
  const ListLit(this.elements, int line) : super(line);
}

class TupleLit extends Expr {
  final List<Expr> elements;
  const TupleLit(this.elements, int line) : super(line);
}

class DictLit extends Expr {
  final List<Expr> keys;
  final List<Expr> values;
  const DictLit(this.keys, this.values, int line) : super(line);
}

class Attribute extends Expr {
  final Expr object;
  final String name;
  const Attribute(this.object, this.name, int line) : super(line);
}

class Subscript extends Expr {
  final Expr object;
  final Expr index;
  const Subscript(this.object, this.index, int line) : super(line);
}

class SliceExpr extends Expr {
  final Expr? lower;
  final Expr? upper;
  final Expr? step;
  const SliceExpr(this.lower, this.upper, int line, [this.step]) : super(line);
}

class Call extends Expr {
  final Expr func;
  final List<Expr> args;
  final Map<String, Expr> kwargs;
  const Call(this.func, this.args, this.kwargs, int line) : super(line);
}

class UnaryOp extends Expr {
  final String op; // '-', '+', 'not'
  final Expr operand;
  const UnaryOp(this.op, this.operand, int line) : super(line);
}

class BinOp extends Expr {
  final String op; // + - * / // % **
  final Expr left;
  final Expr right;
  const BinOp(this.op, this.left, this.right, int line) : super(line);
}

class Compare extends Expr {
  final Expr left;
  final List<String> ops; // < <= > >= == != in not-in is is-not
  final List<Expr> comparators;
  const Compare(this.left, this.ops, this.comparators, int line) : super(line);
}

class BoolOp extends Expr {
  final String op; // 'and' | 'or'
  final List<Expr> values;
  const BoolOp(this.op, this.values, int line) : super(line);
}

class IfExp extends Expr {
  final Expr test;
  final Expr body;
  final Expr orelse;
  const IfExp(this.test, this.body, this.orelse, int line) : super(line);
}

class Lambda extends Expr {
  final List<Param> params;
  final Expr body;
  const Lambda(this.params, this.body, int line) : super(line);
}

// ── Statements ───────────────────────────────────────────────────────────────

abstract class Stmt extends Node {
  const Stmt(super.line);
}

class ExprStmt extends Stmt {
  final Expr expr;
  const ExprStmt(this.expr, int line) : super(line);
}

class Assign extends Stmt {
  final Expr target; // Name, Attribute, Subscript, TupleLit of those
  final Expr value;
  const Assign(this.target, this.value, int line) : super(line);
}

class AugAssign extends Stmt {
  final Expr target;
  final String op; // + - * / // % **
  final Expr value;
  const AugAssign(this.target, this.op, this.value, int line) : super(line);
}

class If extends Stmt {
  final Expr test;
  final List<Stmt> body;
  final List<Stmt> orelse;
  const If(this.test, this.body, this.orelse, int line) : super(line);
}

class While extends Stmt {
  final Expr test;
  final List<Stmt> body;
  const While(this.test, this.body, int line) : super(line);
}

class For extends Stmt {
  final Expr target;
  final Expr iter;
  final List<Stmt> body;
  const For(this.target, this.iter, this.body, int line) : super(line);
}

class Param {
  final String name;
  final Expr? defaultValue;
  const Param(this.name, this.defaultValue);
}

class FunctionDef extends Stmt {
  final String name;
  final List<Param> params;
  final List<Stmt> body;
  const FunctionDef(this.name, this.params, this.body, int line) : super(line);
}

class Return extends Stmt {
  final Expr? value;
  const Return(this.value, int line) : super(line);
}

class Break extends Stmt {
  const Break(super.line);
}

class Continue extends Stmt {
  const Continue(super.line);
}

class Pass extends Stmt {
  const Pass(super.line);
}

class Global extends Stmt {
  final List<String> names;
  const Global(this.names, int line) : super(line);
}

class Import extends Stmt {
  final List<String> modules;

  /// Names the statement binds: local name -> dotted path to the value
  /// (`import math as m` → {m: math}; `from math import sqrt` →
  /// {sqrt: math.sqrt}). A `*` key binds every attribute of the module.
  final Map<String, String> bindings;
  const Import(this.modules, int line, [this.bindings = const {}]) : super(line);
}

class Module {
  final List<Stmt> body;
  const Module(this.body);
}
