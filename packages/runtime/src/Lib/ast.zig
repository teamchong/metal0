//! ast - Abstract Syntax Tree module
//! Reference: cpython/Lib/ast.py
//!
//! CPython __all__: parse, literal_eval, dump, unparse, copy_location,
//!                  fix_missing_locations, get_docstring, get_source_segment,
//!                  walk, NodeVisitor, NodeTransformer, Constant, Num, Str,
//!                  Bytes, NameConstant, Ellipsis, PyCF_ONLY_AST,
//!                  PyCF_TYPE_COMMENTS, PyCF_ALLOW_TOP_LEVEL_AWAIT
//!
//! The ast module provides classes and functions to help with parsing,
//! manipulating, and compiling Python abstract syntax trees.

const std = @import("std");

// ============================================================================
// Compiler Flags
// ============================================================================

/// Parse code and return AST instead of compiling
pub const PyCF_ONLY_AST: u32 = 0x0400;
/// Enable type comments
pub const PyCF_TYPE_COMMENTS: u32 = 0x1000;
/// Allow top-level await
pub const PyCF_ALLOW_TOP_LEVEL_AWAIT: u32 = 0x2000;

// ============================================================================
// AST Node Types
// ============================================================================

/// Base AST node
pub const AST = struct {
    lineno: ?i32 = null,
    col_offset: ?i32 = null,
    end_lineno: ?i32 = null,
    end_col_offset: ?i32 = null,
};

/// Expression context
pub const ExprContext = enum {
    Load,
    Store,
    Del,
};

/// Module node (root of AST)
pub const Module = struct {
    body: []Statement,
    type_ignores: []TypeIgnore = &.{},
};

/// Statement node (union of all statement types)
pub const Statement = union(enum) {
    FunctionDef: FunctionDef,
    AsyncFunctionDef: FunctionDef,
    ClassDef: ClassDef,
    Return: Return,
    Delete: Delete,
    Assign: Assign,
    AugAssign: AugAssign,
    AnnAssign: AnnAssign,
    For: For,
    AsyncFor: For,
    While: While,
    If: If,
    With: With,
    AsyncWith: With,
    Match: Match,
    Raise: Raise,
    Try: Try,
    TryStar: Try,
    Assert: Assert,
    Import: Import,
    ImportFrom: ImportFrom,
    Global: Global,
    Nonlocal: Nonlocal,
    Expr: ExprStmt,
    Pass: void,
    Break: void,
    Continue: void,
};

/// Expression node
pub const Expression = union(enum) {
    BoolOp: BoolOp,
    NamedExpr: NamedExpr,
    BinOp: BinOp,
    UnaryOp: UnaryOp,
    Lambda: Lambda,
    IfExp: IfExp,
    Dict: Dict,
    Set: Set,
    ListComp: Comprehension,
    SetComp: Comprehension,
    DictComp: Comprehension,
    GeneratorExp: Comprehension,
    Await: Await,
    Yield: Yield,
    YieldFrom: YieldFrom,
    Compare: Compare,
    Call: Call,
    FormattedValue: FormattedValue,
    JoinedStr: JoinedStr,
    Constant: Constant,
    Attribute: Attribute,
    Subscript: Subscript,
    Starred: Starred,
    Name: Name,
    List: List,
    Tuple: Tuple,
    Slice: Slice,
};

// ============================================================================
// Node Definitions
// ============================================================================

pub const FunctionDef = struct {
    name: []const u8,
    args: Arguments,
    body: []Statement,
    decorator_list: []Expression = &.{},
    returns: ?*Expression = null,
    type_comment: ?[]const u8 = null,
};

pub const ClassDef = struct {
    name: []const u8,
    bases: []Expression = &.{},
    keywords: []Keyword = &.{},
    body: []Statement,
    decorator_list: []Expression = &.{},
};

pub const Return = struct {
    value: ?*Expression = null,
};

pub const Delete = struct {
    targets: []Expression,
};

pub const Assign = struct {
    targets: []Expression,
    value: *Expression,
    type_comment: ?[]const u8 = null,
};

pub const AugAssign = struct {
    target: *Expression,
    op: Operator,
    value: *Expression,
};

pub const AnnAssign = struct {
    target: *Expression,
    annotation: *Expression,
    value: ?*Expression = null,
    simple: bool = true,
};

pub const For = struct {
    target: *Expression,
    iter: *Expression,
    body: []Statement,
    orelse: []Statement = &.{},
    type_comment: ?[]const u8 = null,
};

pub const While = struct {
    test: *Expression,
    body: []Statement,
    orelse: []Statement = &.{},
};

pub const If = struct {
    test: *Expression,
    body: []Statement,
    orelse: []Statement = &.{},
};

pub const With = struct {
    items: []WithItem,
    body: []Statement,
    type_comment: ?[]const u8 = null,
};

pub const Match = struct {
    subject: *Expression,
    cases: []MatchCase,
};

pub const Raise = struct {
    exc: ?*Expression = null,
    cause: ?*Expression = null,
};

pub const Try = struct {
    body: []Statement,
    handlers: []ExceptHandler = &.{},
    orelse: []Statement = &.{},
    finalbody: []Statement = &.{},
};

pub const Assert = struct {
    test: *Expression,
    msg: ?*Expression = null,
};

pub const Import = struct {
    names: []Alias,
};

pub const ImportFrom = struct {
    module: ?[]const u8 = null,
    names: []Alias,
    level: u32 = 0,
};

pub const Global = struct {
    names: [][]const u8,
};

pub const Nonlocal = struct {
    names: [][]const u8,
};

pub const ExprStmt = struct {
    value: *Expression,
};

// Expression types
pub const BoolOp = struct {
    op: BoolOperator,
    values: []Expression,
};

pub const NamedExpr = struct {
    target: *Expression,
    value: *Expression,
};

pub const BinOp = struct {
    left: *Expression,
    op: Operator,
    right: *Expression,
};

pub const UnaryOp = struct {
    op: UnaryOperator,
    operand: *Expression,
};

pub const Lambda = struct {
    args: Arguments,
    body: *Expression,
};

pub const IfExp = struct {
    test: *Expression,
    body: *Expression,
    orelse: *Expression,
};

pub const Dict = struct {
    keys: []?*Expression,
    values: []Expression,
};

pub const Set = struct {
    elts: []Expression,
};

pub const Comprehension = struct {
    elt: *Expression,
    generators: []ComprehensionGen,
};

pub const ComprehensionGen = struct {
    target: *Expression,
    iter: *Expression,
    ifs: []Expression = &.{},
    is_async: bool = false,
};

pub const Await = struct {
    value: *Expression,
};

pub const Yield = struct {
    value: ?*Expression = null,
};

pub const YieldFrom = struct {
    value: *Expression,
};

pub const Compare = struct {
    left: *Expression,
    ops: []CmpOp,
    comparators: []Expression,
};

pub const Call = struct {
    func: *Expression,
    args: []Expression = &.{},
    keywords: []Keyword = &.{},
};

pub const FormattedValue = struct {
    value: *Expression,
    conversion: i32 = -1,
    format_spec: ?*Expression = null,
};

pub const JoinedStr = struct {
    values: []Expression,
};

pub const Constant = struct {
    value: ConstantValue,
    kind: ?[]const u8 = null,
};

pub const ConstantValue = union(enum) {
    none: void,
    bool_: bool,
    int: i64,
    float: f64,
    string: []const u8,
    bytes: []const u8,
    ellipsis: void,
};

pub const Attribute = struct {
    value: *Expression,
    attr: []const u8,
    ctx: ExprContext = .Load,
};

pub const Subscript = struct {
    value: *Expression,
    slice: *Expression,
    ctx: ExprContext = .Load,
};

pub const Starred = struct {
    value: *Expression,
    ctx: ExprContext = .Load,
};

pub const Name = struct {
    id: []const u8,
    ctx: ExprContext = .Load,
};

pub const List = struct {
    elts: []Expression,
    ctx: ExprContext = .Load,
};

pub const Tuple = struct {
    elts: []Expression,
    ctx: ExprContext = .Load,
};

pub const Slice = struct {
    lower: ?*Expression = null,
    upper: ?*Expression = null,
    step: ?*Expression = null,
};

// ============================================================================
// Helper Types
// ============================================================================

pub const Operator = enum {
    Add,
    Sub,
    Mult,
    MatMult,
    Div,
    Mod,
    Pow,
    LShift,
    RShift,
    BitOr,
    BitXor,
    BitAnd,
    FloorDiv,
};

pub const BoolOperator = enum {
    And,
    Or,
};

pub const UnaryOperator = enum {
    Invert,
    Not,
    UAdd,
    USub,
};

pub const CmpOp = enum {
    Eq,
    NotEq,
    Lt,
    LtE,
    Gt,
    GtE,
    Is,
    IsNot,
    In,
    NotIn,
};

pub const Arguments = struct {
    posonlyargs: []Arg = &.{},
    args: []Arg = &.{},
    vararg: ?*Arg = null,
    kwonlyargs: []Arg = &.{},
    kw_defaults: []?*Expression = &.{},
    kwarg: ?*Arg = null,
    defaults: []Expression = &.{},
};

pub const Arg = struct {
    arg: []const u8,
    annotation: ?*Expression = null,
    type_comment: ?[]const u8 = null,
};

pub const Keyword = struct {
    arg: ?[]const u8 = null,
    value: *Expression,
};

pub const Alias = struct {
    name: []const u8,
    asname: ?[]const u8 = null,
};

pub const WithItem = struct {
    context_expr: *Expression,
    optional_vars: ?*Expression = null,
};

pub const MatchCase = struct {
    pattern: Pattern,
    guard: ?*Expression = null,
    body: []Statement,
};

pub const Pattern = union(enum) {
    MatchValue: *Expression,
    MatchSingleton: ConstantValue,
    MatchSequence: []Pattern,
    MatchMapping: MatchMapping,
    MatchClass: MatchClass,
    MatchStar: ?[]const u8,
    MatchAs: MatchAs,
    MatchOr: []Pattern,
};

pub const MatchMapping = struct {
    keys: []Expression,
    patterns: []Pattern,
    rest: ?[]const u8 = null,
};

pub const MatchClass = struct {
    cls: *Expression,
    patterns: []Pattern = &.{},
    kwd_attrs: [][]const u8 = &.{},
    kwd_patterns: []Pattern = &.{},
};

pub const MatchAs = struct {
    pattern: ?*Pattern = null,
    name: ?[]const u8 = null,
};

pub const ExceptHandler = struct {
    type_: ?*Expression = null,
    name: ?[]const u8 = null,
    body: []Statement,
};

pub const TypeIgnore = struct {
    lineno: i32,
    tag: []const u8,
};

// ============================================================================
// Functions
// ============================================================================

/// Parse source code into AST (placeholder - actual parsing done by compiler)
pub fn parse(source: []const u8, filename: []const u8, mode: []const u8) !*Module {
    _ = source;
    _ = filename;
    _ = mode;
    return error.NotImplemented;
}

/// Safely evaluate a literal expression
pub fn literal_eval(node_or_string: anytype) !ConstantValue {
    _ = node_or_string;
    return error.NotImplemented;
}

/// Dump AST as string representation
pub fn dump(allocator: std.mem.Allocator, node: anytype, indent: ?u32) ![]const u8 {
    _ = allocator;
    _ = node;
    _ = indent;
    return error.NotImplemented;
}

// ============================================================================
// Tests
// ============================================================================

test "AST node creation" {
    const name = Name{ .id = "x" };
    try std.testing.expectEqualStrings("x", name.id);
}

test "Constant values" {
    const c = Constant{ .value = .{ .int = 42 } };
    try std.testing.expectEqual(@as(i64, 42), c.value.int);
}
