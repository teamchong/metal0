//! Python 'ast' module - Abstract Syntax Trees
//!
//! Provides AST node types and utilities for working with Python ASTs.
//!
//! Mirrors: CPython Lib/ast.py

const std = @import("std");

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

/// Module node types
pub const Module = struct {
    body: []Statement,
    type_ignores: []TypeIgnore,
};

pub const Interactive = struct {
    body: []Statement,
};

pub const Expression = struct {
    body: Expr,
};

pub const FunctionType = struct {
    argtypes: []Expr,
    returns: Expr,
};

/// Statement types
pub const Statement = union(enum) {
    function_def: FunctionDef,
    async_function_def: AsyncFunctionDef,
    class_def: ClassDef,
    return_stmt: Return,
    delete: Delete,
    assign: Assign,
    aug_assign: AugAssign,
    ann_assign: AnnAssign,
    for_stmt: For,
    async_for: AsyncFor,
    while_stmt: While,
    if_stmt: If,
    with_stmt: With,
    async_with: AsyncWith,
    match_stmt: Match,
    raise_stmt: Raise,
    try_stmt: Try,
    try_star: TryStar,
    assert_stmt: Assert,
    import_stmt: Import,
    import_from: ImportFrom,
    global_stmt: Global,
    nonlocal_stmt: Nonlocal,
    expr_stmt: ExprStmt,
    pass_stmt: Pass,
    break_stmt: Break,
    continue_stmt: Continue,
};

pub const FunctionDef = struct {
    name: []const u8,
    args: Arguments,
    body: []Statement,
    decorator_list: []Expr,
    returns: ?Expr,
    type_comment: ?[]const u8,
    type_params: []TypeParam,
};

pub const AsyncFunctionDef = FunctionDef;

pub const ClassDef = struct {
    name: []const u8,
    bases: []Expr,
    keywords: []Keyword,
    body: []Statement,
    decorator_list: []Expr,
    type_params: []TypeParam,
};

pub const Return = struct {
    value: ?Expr,
};

pub const Delete = struct {
    targets: []Expr,
};

pub const Assign = struct {
    targets: []Expr,
    value: Expr,
    type_comment: ?[]const u8,
};

pub const AugAssign = struct {
    target: Expr,
    op: Operator,
    value: Expr,
};

pub const AnnAssign = struct {
    target: Expr,
    annotation: Expr,
    value: ?Expr,
    simple: bool,
};

pub const For = struct {
    target: Expr,
    iter: Expr,
    body: []Statement,
    orelse: []Statement,
    type_comment: ?[]const u8,
};

pub const AsyncFor = For;

pub const While = struct {
    test: Expr,
    body: []Statement,
    orelse: []Statement,
};

pub const If = struct {
    test: Expr,
    body: []Statement,
    orelse: []Statement,
};

pub const With = struct {
    items: []WithItem,
    body: []Statement,
    type_comment: ?[]const u8,
};

pub const AsyncWith = With;

pub const Match = struct {
    subject: Expr,
    cases: []MatchCase,
};

pub const Raise = struct {
    exc: ?Expr,
    cause: ?Expr,
};

pub const Try = struct {
    body: []Statement,
    handlers: []ExceptHandler,
    orelse: []Statement,
    finalbody: []Statement,
};

pub const TryStar = Try;

pub const Assert = struct {
    test: Expr,
    msg: ?Expr,
};

pub const Import = struct {
    names: []Alias,
};

pub const ImportFrom = struct {
    module: ?[]const u8,
    names: []Alias,
    level: i32,
};

pub const Global = struct {
    names: [][]const u8,
};

pub const Nonlocal = Global;

pub const ExprStmt = struct {
    value: Expr,
};

pub const Pass = struct {};
pub const Break = struct {};
pub const Continue = struct {};

/// Expression types
pub const Expr = union(enum) {
    bool_op: BoolOp,
    named_expr: NamedExpr,
    bin_op: BinOp,
    unary_op: UnaryOp,
    lambda: Lambda,
    if_exp: IfExp,
    dict: Dict,
    set: Set,
    list_comp: ListComp,
    set_comp: SetComp,
    dict_comp: DictComp,
    generator_exp: GeneratorExp,
    await_expr: Await,
    yield_expr: Yield,
    yield_from: YieldFrom,
    compare: Compare,
    call: Call,
    formatted_value: FormattedValue,
    joined_str: JoinedStr,
    constant: Constant,
    attribute: Attribute,
    subscript: Subscript,
    starred: Starred,
    name: Name,
    list: List,
    tuple: Tuple,
    slice: Slice,
};

pub const BoolOp = struct {
    op: BoolOperator,
    values: []Expr,
};

pub const NamedExpr = struct {
    target: *Expr,
    value: *Expr,
};

pub const BinOp = struct {
    left: *Expr,
    op: Operator,
    right: *Expr,
};

pub const UnaryOp = struct {
    op: UnaryOperator,
    operand: *Expr,
};

pub const Lambda = struct {
    args: Arguments,
    body: *Expr,
};

pub const IfExp = struct {
    test: *Expr,
    body: *Expr,
    orelse: *Expr,
};

pub const Dict = struct {
    keys: []?Expr,
    values: []Expr,
};

pub const Set = struct {
    elts: []Expr,
};

pub const ListComp = struct {
    elt: *Expr,
    generators: []Comprehension,
};

pub const SetComp = ListComp;

pub const DictComp = struct {
    key: *Expr,
    value: *Expr,
    generators: []Comprehension,
};

pub const GeneratorExp = ListComp;

pub const Await = struct {
    value: *Expr,
};

pub const Yield = struct {
    value: ?*Expr,
};

pub const YieldFrom = struct {
    value: *Expr,
};

pub const Compare = struct {
    left: *Expr,
    ops: []CmpOp,
    comparators: []Expr,
};

pub const Call = struct {
    func: *Expr,
    args: []Expr,
    keywords: []Keyword,
};

pub const FormattedValue = struct {
    value: *Expr,
    conversion: i32,
    format_spec: ?*Expr,
};

pub const JoinedStr = struct {
    values: []Expr,
};

pub const Constant = struct {
    value: ConstantValue,
    kind: ?[]const u8,
};

pub const ConstantValue = union(enum) {
    none,
    bool_val: bool,
    int_val: i64,
    float_val: f64,
    string_val: []const u8,
    bytes_val: []const u8,
    ellipsis,
};

pub const Attribute = struct {
    value: *Expr,
    attr: []const u8,
    ctx: ExprContext,
};

pub const Subscript = struct {
    value: *Expr,
    slice: *Expr,
    ctx: ExprContext,
};

pub const Starred = struct {
    value: *Expr,
    ctx: ExprContext,
};

pub const Name = struct {
    id: []const u8,
    ctx: ExprContext,
};

pub const List = struct {
    elts: []Expr,
    ctx: ExprContext,
};

pub const Tuple = List;

pub const Slice = struct {
    lower: ?*Expr,
    upper: ?*Expr,
    step: ?*Expr,
};

/// Operators
pub const BoolOperator = enum {
    @"and",
    @"or",
};

pub const Operator = enum {
    add,
    sub,
    mult,
    mat_mult,
    div,
    mod,
    pow,
    lshift,
    rshift,
    bit_or,
    bit_xor,
    bit_and,
    floor_div,
};

pub const UnaryOperator = enum {
    invert,
    not,
    uadd,
    usub,
};

pub const CmpOp = enum {
    eq,
    not_eq,
    lt,
    lte,
    gt,
    gte,
    is,
    is_not,
    in,
    not_in,
};

pub const ExprContext = enum {
    load,
    store,
    del,
};

/// Other node types
pub const Comprehension = struct {
    target: Expr,
    iter: Expr,
    ifs: []Expr,
    is_async: bool,
};

pub const ExceptHandler = struct {
    type: ?Expr,
    name: ?[]const u8,
    body: []Statement,
};

pub const Arguments = struct {
    posonlyargs: []Arg,
    args: []Arg,
    vararg: ?Arg,
    kwonlyargs: []Arg,
    kw_defaults: []?Expr,
    kwarg: ?Arg,
    defaults: []Expr,
};

pub const Arg = struct {
    arg: []const u8,
    annotation: ?Expr,
    type_comment: ?[]const u8,
};

pub const Keyword = struct {
    arg: ?[]const u8,
    value: Expr,
};

pub const Alias = struct {
    name: []const u8,
    asname: ?[]const u8,
};

pub const WithItem = struct {
    context_expr: Expr,
    optional_vars: ?Expr,
};

pub const MatchCase = struct {
    pattern: Pattern,
    guard: ?Expr,
    body: []Statement,
};

pub const Pattern = union(enum) {
    match_value: MatchValue,
    match_singleton: MatchSingleton,
    match_sequence: MatchSequence,
    match_mapping: MatchMapping,
    match_class: MatchClass,
    match_star: MatchStar,
    match_as: MatchAs,
    match_or: MatchOr,
};

pub const MatchValue = struct {
    value: Expr,
};

pub const MatchSingleton = struct {
    value: ConstantValue,
};

pub const MatchSequence = struct {
    patterns: []Pattern,
};

pub const MatchMapping = struct {
    keys: []Expr,
    patterns: []Pattern,
    rest: ?[]const u8,
};

pub const MatchClass = struct {
    cls: Expr,
    patterns: []Pattern,
    kwd_attrs: [][]const u8,
    kwd_patterns: []Pattern,
};

pub const MatchStar = struct {
    name: ?[]const u8,
};

pub const MatchAs = struct {
    pattern: ?*Pattern,
    name: ?[]const u8,
};

pub const MatchOr = struct {
    patterns: []Pattern,
};

pub const TypeIgnore = struct {
    lineno: i32,
    tag: []const u8,
};

pub const TypeParam = union(enum) {
    type_var: TypeVar,
    param_spec: ParamSpec,
    type_var_tuple: TypeVarTuple,
};

pub const TypeVar = struct {
    name: []const u8,
    bound: ?Expr,
};

pub const ParamSpec = struct {
    name: []const u8,
};

pub const TypeVarTuple = struct {
    name: []const u8,
};

// ============================================================================
// AST Functions
// ============================================================================

/// Parse source code into an AST
pub fn parse(allocator: std.mem.Allocator, source: []const u8, filename: []const u8, mode: []const u8) !*Module {
    _ = allocator;
    _ = source;
    _ = filename;
    _ = mode;
    // Would parse Python source into AST
    return error.NotImplemented;
}

/// Compile an AST into a code object
pub fn compile_ast(allocator: std.mem.Allocator, node: anytype, filename: []const u8, mode: []const u8) !*anyopaque {
    _ = allocator;
    _ = node;
    _ = filename;
    _ = mode;
    return error.NotImplemented;
}

/// Convert AST to source code
pub fn unparse(allocator: std.mem.Allocator, node: anytype) ![]u8 {
    _ = allocator;
    _ = node;
    return error.NotImplemented;
}

/// Pretty print an AST
pub fn dump(allocator: std.mem.Allocator, node: anytype, annotate_fields: bool, include_attributes: bool, indent: ?usize) ![]u8 {
    _ = allocator;
    _ = node;
    _ = annotate_fields;
    _ = include_attributes;
    _ = indent;
    return error.NotImplemented;
}

/// Get docstring from node
pub fn getDocstring(node: anytype) ?[]const u8 {
    _ = node;
    return null;
}

/// Walk AST nodes
pub fn walk(allocator: std.mem.Allocator, node: anytype) !NodeIterator {
    return NodeIterator.init(allocator, node);
}

pub const NodeIterator = struct {
    allocator: std.mem.Allocator,
    stack: std.ArrayList(*anyopaque),

    pub fn init(allocator: std.mem.Allocator, root: anytype) NodeIterator {
        _ = root;
        return .{
            .allocator = allocator,
            .stack = std.ArrayList(*anyopaque).init(allocator),
        };
    }

    pub fn deinit(self: *NodeIterator) void {
        self.stack.deinit();
    }

    pub fn next(self: *NodeIterator) ?*anyopaque {
        if (self.stack.items.len == 0) return null;
        return self.stack.pop();
    }
};

/// Fix missing locations in AST
pub fn fixMissingLocations(node: anytype) void {
    _ = node;
}

/// Increment line numbers
pub fn incrementLineno(node: anytype, n: i32) void {
    _ = node;
    _ = n;
}

/// Copy location from one node to another
pub fn copyLocation(source: anytype, dest: anytype) void {
    _ = source;
    _ = dest;
}

/// Get source segment
pub fn getSourceSegment(source: []const u8, node: anytype, padded: bool) ?[]const u8 {
    _ = source;
    _ = node;
    _ = padded;
    return null;
}

// ============================================================================
// NodeVisitor
// ============================================================================

/// Base class for AST visitors
pub fn NodeVisitor(comptime T: type) type {
    return struct {
        const Self = @This();

        context: T,

        pub fn init(context: T) Self {
            return .{ .context = context };
        }

        pub fn visit(self: *Self, node: anytype) void {
            _ = self;
            _ = node;
        }

        pub fn genericVisit(self: *Self, node: anytype) void {
            _ = self;
            _ = node;
        }
    };
}

/// Base class for AST transformers
pub fn NodeTransformer(comptime T: type) type {
    return struct {
        const Self = @This();

        context: T,

        pub fn init(context: T) Self {
            return .{ .context = context };
        }

        pub fn visit(self: *Self, node: anytype) @TypeOf(node) {
            _ = self;
            return node;
        }

        pub fn genericVisit(self: *Self, node: anytype) @TypeOf(node) {
            _ = self;
            return node;
        }
    };
}

// ============================================================================
// Constants
// ============================================================================

pub const PyCF_ONLY_AST = 0x0400;
pub const PyCF_TYPE_COMMENTS = 0x1000;
pub const PyCF_ALLOW_TOP_LEVEL_AWAIT = 0x2000;

// ============================================================================
// Tests
// ============================================================================

test "operator enum" {
    try std.testing.expect(@intFromEnum(Operator.add) == 0);
    try std.testing.expect(@intFromEnum(CmpOp.eq) == 0);
}

test "expr context" {
    try std.testing.expect(@intFromEnum(ExprContext.load) == 0);
    try std.testing.expect(@intFromEnum(ExprContext.store) == 1);
}

test "constant value" {
    const c1 = ConstantValue{ .int_val = 42 };
    try std.testing.expectEqual(@as(i64, 42), c1.int_val);

    const c2 = ConstantValue{ .string_val = "hello" };
    try std.testing.expectEqualStrings("hello", c2.string_val);
}
