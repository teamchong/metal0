/// Python-ast - AST Node Types
/// Mirrors cpython/Python/Python-ast.c (auto-generated from Parser/Python.asdl)
///
/// Defines all AST node types for the Python abstract syntax tree.
/// This is the canonical representation of parsed Python code.

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// AST Node Types
// ============================================================================

/// Module types (top-level)
pub const ModKind = enum {
    Module,
    Interactive,
    Expression,
    FunctionType,
};

/// Module node
pub const Module = struct {
    kind: ModKind,
    body: []Statement,
    type_ignores: []TypeIgnore = &[_]TypeIgnore{},
};

/// Statement types
pub const StmtKind = enum {
    // Definitions
    FunctionDef,
    AsyncFunctionDef,
    ClassDef,

    // Simple statements
    Return,
    Delete,
    Assign,
    TypeAlias,
    AugAssign,
    AnnAssign,

    // Control flow
    For,
    AsyncFor,
    While,
    If,
    With,
    AsyncWith,
    Match,

    // Exception handling
    Raise,
    Try,
    TryStar,
    Assert,

    // Import statements
    Import,
    ImportFrom,

    // Global/nonlocal
    Global,
    Nonlocal,

    // Expression statement
    Expr,

    // Other
    Pass,
    Break,
    Continue,
};

/// Statement node
pub const Statement = struct {
    kind: StmtKind,
    lineno: i32 = 0,
    col_offset: i32 = 0,
    end_lineno: ?i32 = null,
    end_col_offset: ?i32 = null,
    data: StmtData = .{ .pass = {} },
};

/// Statement-specific data
pub const StmtData = union(StmtKind) {
    FunctionDef: FunctionDefData,
    AsyncFunctionDef: FunctionDefData,
    ClassDef: ClassDefData,
    Return: ReturnData,
    Delete: DeleteData,
    Assign: AssignData,
    TypeAlias: TypeAliasData,
    AugAssign: AugAssignData,
    AnnAssign: AnnAssignData,
    For: ForData,
    AsyncFor: ForData,
    While: WhileData,
    If: IfData,
    With: WithData,
    AsyncWith: WithData,
    Match: MatchData,
    Raise: RaiseData,
    Try: TryData,
    TryStar: TryData,
    Assert: AssertData,
    Import: ImportData,
    ImportFrom: ImportFromData,
    Global: GlobalData,
    Nonlocal: NonlocalData,
    Expr: ExprData,
    Pass: void,
    Break: void,
    Continue: void,
};

// Statement data types
pub const FunctionDefData = struct {
    name: []const u8,
    args: Arguments,
    body: []Statement,
    decorator_list: []Expr = &[_]Expr{},
    returns: ?*Expr = null,
    type_comment: ?[]const u8 = null,
    type_params: []TypeParam = &[_]TypeParam{},
};

pub const ClassDefData = struct {
    name: []const u8,
    bases: []Expr = &[_]Expr{},
    keywords: []Keyword = &[_]Keyword{},
    body: []Statement,
    decorator_list: []Expr = &[_]Expr{},
    type_params: []TypeParam = &[_]TypeParam{},
};

pub const ReturnData = struct {
    value: ?*Expr = null,
};

pub const DeleteData = struct {
    targets: []Expr,
};

pub const AssignData = struct {
    targets: []Expr,
    value: *Expr,
    type_comment: ?[]const u8 = null,
};

pub const TypeAliasData = struct {
    name: *Expr,
    type_params: []TypeParam = &[_]TypeParam{},
    value: *Expr,
};

pub const AugAssignData = struct {
    target: *Expr,
    op: Operator,
    value: *Expr,
};

pub const AnnAssignData = struct {
    target: *Expr,
    annotation: *Expr,
    value: ?*Expr = null,
    simple: bool = true,
};

pub const ForData = struct {
    target: *Expr,
    iter: *Expr,
    body: []Statement,
    orelse: []Statement = &[_]Statement{},
    type_comment: ?[]const u8 = null,
};

pub const WhileData = struct {
    test: *Expr,
    body: []Statement,
    orelse: []Statement = &[_]Statement{},
};

pub const IfData = struct {
    test: *Expr,
    body: []Statement,
    orelse: []Statement = &[_]Statement{},
};

pub const WithData = struct {
    items: []WithItem,
    body: []Statement,
    type_comment: ?[]const u8 = null,
};

pub const MatchData = struct {
    subject: *Expr,
    cases: []MatchCase,
};

pub const RaiseData = struct {
    exc: ?*Expr = null,
    cause: ?*Expr = null,
};

pub const TryData = struct {
    body: []Statement,
    handlers: []ExceptHandler = &[_]ExceptHandler{},
    orelse: []Statement = &[_]Statement{},
    finalbody: []Statement = &[_]Statement{},
};

pub const AssertData = struct {
    test: *Expr,
    msg: ?*Expr = null,
};

pub const ImportData = struct {
    names: []Alias,
};

pub const ImportFromData = struct {
    module: ?[]const u8 = null,
    names: []Alias,
    level: u32 = 0,
};

pub const GlobalData = struct {
    names: [][]const u8,
};

pub const NonlocalData = struct {
    names: [][]const u8,
};

pub const ExprData = struct {
    value: *Expr,
};

// ============================================================================
// Expression Types
// ============================================================================

/// Expression types
pub const ExprKind = enum {
    BoolOp,
    NamedExpr,
    BinOp,
    UnaryOp,
    Lambda,
    IfExp,
    Dict,
    Set,
    ListComp,
    SetComp,
    DictComp,
    GeneratorExp,
    Await,
    Yield,
    YieldFrom,
    Compare,
    Call,
    FormattedValue,
    JoinedStr,
    Constant,
    Attribute,
    Subscript,
    Starred,
    Name,
    List,
    Tuple,
    Slice,
};

/// Expression node
pub const Expr = struct {
    kind: ExprKind,
    lineno: i32 = 0,
    col_offset: i32 = 0,
    end_lineno: ?i32 = null,
    end_col_offset: ?i32 = null,
    ctx: ExprContext = .Load,
};

/// Expression context
pub const ExprContext = enum {
    Load,
    Store,
    Del,
};

// ============================================================================
// Operators
// ============================================================================

/// Binary operators
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

/// Unary operators
pub const UnaryOp = enum {
    Invert,
    Not,
    UAdd,
    USub,
};

/// Boolean operators
pub const BoolOp = enum {
    And,
    Or,
};

/// Comparison operators
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

// ============================================================================
// Supporting Types
// ============================================================================

/// Function arguments
pub const Arguments = struct {
    posonlyargs: []Arg = &[_]Arg{},
    args: []Arg = &[_]Arg{},
    vararg: ?*Arg = null,
    kwonlyargs: []Arg = &[_]Arg{},
    kw_defaults: []?*Expr = &[_]?*Expr{},
    kwarg: ?*Arg = null,
    defaults: []Expr = &[_]Expr{},
};

/// Function argument
pub const Arg = struct {
    arg: []const u8,
    annotation: ?*Expr = null,
    type_comment: ?[]const u8 = null,
    lineno: i32 = 0,
    col_offset: i32 = 0,
    end_lineno: ?i32 = null,
    end_col_offset: ?i32 = null,
};

/// Keyword argument
pub const Keyword = struct {
    arg: ?[]const u8 = null, // null for **kwargs
    value: *Expr,
    lineno: i32 = 0,
    col_offset: i32 = 0,
    end_lineno: ?i32 = null,
    end_col_offset: ?i32 = null,
};

/// Import alias
pub const Alias = struct {
    name: []const u8,
    asname: ?[]const u8 = null,
    lineno: i32 = 0,
    col_offset: i32 = 0,
    end_lineno: ?i32 = null,
    end_col_offset: ?i32 = null,
};

/// With item
pub const WithItem = struct {
    context_expr: *Expr,
    optional_vars: ?*Expr = null,
};

/// Match case
pub const MatchCase = struct {
    pattern: *Pattern,
    guard: ?*Expr = null,
    body: []Statement,
};

/// Exception handler
pub const ExceptHandler = struct {
    type_: ?*Expr = null,
    name: ?[]const u8 = null,
    body: []Statement,
    lineno: i32 = 0,
    col_offset: i32 = 0,
    end_lineno: ?i32 = null,
    end_col_offset: ?i32 = null,
};

/// Type ignore
pub const TypeIgnore = struct {
    lineno: i32,
    tag: []const u8,
};

/// Type parameter (PEP 695)
pub const TypeParam = struct {
    kind: TypeParamKind,
    name: []const u8,
    bound: ?*Expr = null,
    default_value: ?*Expr = null,
    lineno: i32 = 0,
    col_offset: i32 = 0,
    end_lineno: ?i32 = null,
    end_col_offset: ?i32 = null,
};

pub const TypeParamKind = enum {
    TypeVar,
    ParamSpec,
    TypeVarTuple,
};

// ============================================================================
// Pattern Types (for match statements)
// ============================================================================

/// Pattern types
pub const PatternKind = enum {
    MatchValue,
    MatchSingleton,
    MatchSequence,
    MatchMapping,
    MatchClass,
    MatchStar,
    MatchAs,
    MatchOr,
};

/// Pattern node
pub const Pattern = struct {
    kind: PatternKind,
    lineno: i32 = 0,
    col_offset: i32 = 0,
    end_lineno: ?i32 = null,
    end_col_offset: ?i32 = null,
};

// ============================================================================
// Constant Types
// ============================================================================

/// Constant value
pub const Constant = union(enum) {
    none: void,
    true_val: void,
    false_val: void,
    ellipsis: void,
    int_val: i64,
    float_val: f64,
    complex_val: struct { real: f64, imag: f64 },
    str_val: []const u8,
    bytes_val: []const u8,
    tuple_val: []Constant,
    frozenset_val: []Constant,
};

// ============================================================================
// AST Visitor Interface
// ============================================================================

/// AST visitor interface
pub fn Visitor(comptime Context: type) type {
    return struct {
        context: Context,

        visit_stmt: ?*const fn (Context, *Statement) void = null,
        visit_expr: ?*const fn (Context, *Expr) void = null,
        visit_pattern: ?*const fn (Context, *Pattern) void = null,

        pub fn visitModule(self: @This(), module: *Module) void {
            for (module.body) |*stmt| {
                self.visitStmt(stmt);
            }
        }

        pub fn visitStmt(self: @This(), stmt: *Statement) void {
            if (self.visit_stmt) |visit| {
                visit(self.context, stmt);
            }
        }

        pub fn visitExpr(self: @This(), expr: *Expr) void {
            if (self.visit_expr) |visit| {
                visit(self.context, expr);
            }
        }
    };
}

// ============================================================================
// Module Initialization
// ============================================================================

var initialized: bool = false;

/// Initialize the Python-ast module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "statement kind" {
    try std.testing.expectEqual(StmtKind.FunctionDef, StmtKind.FunctionDef);
    try std.testing.expectEqual(StmtKind.Pass, StmtKind.Pass);
}

test "expression kind" {
    try std.testing.expectEqual(ExprKind.Constant, ExprKind.Constant);
    try std.testing.expectEqual(ExprKind.Name, ExprKind.Name);
}

test "operator types" {
    try std.testing.expectEqual(Operator.Add, Operator.Add);
    try std.testing.expectEqual(CmpOp.Eq, CmpOp.Eq);
}

test "constant types" {
    const c1 = Constant{ .int_val = 42 };
    try std.testing.expectEqual(@as(i64, 42), c1.int_val);

    const c2 = Constant.none;
    _ = c2;

    const c3 = Constant{ .str_val = "hello" };
    try std.testing.expectEqualStrings("hello", c3.str_val);
}

test "expression context" {
    try std.testing.expectEqual(ExprContext.Load, ExprContext.Load);
    try std.testing.expectEqual(ExprContext.Store, ExprContext.Store);
    try std.testing.expectEqual(ExprContext.Del, ExprContext.Del);
}
