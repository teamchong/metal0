/// Statement types for AST
/// Mirrors cpython/Python/Python-ast.c (statement nodes)

const Expr = @import("expression_types.zig").Expr;
const Operator = @import("operator_types.zig").Operator;
const Arguments = @import("supporting_types.zig").Arguments;
const Keyword = @import("supporting_types.zig").Keyword;
const Alias = @import("supporting_types.zig").Alias;
const WithItem = @import("supporting_types.zig").WithItem;
const MatchCase = @import("supporting_types.zig").MatchCase;
const ExceptHandler = @import("supporting_types.zig").ExceptHandler;
const TypeParam = @import("supporting_types.zig").TypeParam;

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
