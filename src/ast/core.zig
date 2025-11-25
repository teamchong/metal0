const std = @import("std");
const fstring = @import("fstring.zig");

/// AST node types matching Python's ast module
pub const Node = union(enum) {
    module: Module,
    assign: Assign,
    ann_assign: AnnAssign,
    aug_assign: AugAssign,
    binop: BinOp,
    unaryop: UnaryOp,
    compare: Compare,
    boolop: BoolOp,
    call: Call,
    name: Name,
    constant: Constant,
    fstring: fstring.FString,
    if_stmt: If,
    for_stmt: For,
    while_stmt: While,
    function_def: FunctionDef,
    lambda: Lambda,
    class_def: ClassDef,
    return_stmt: Return,
    list: List,
    listcomp: ListComp,
    dict: Dict,
    dictcomp: DictComp,
    set: Set,
    tuple: Tuple,
    subscript: Subscript,
    attribute: Attribute,
    expr_stmt: ExprStmt,
    await_expr: AwaitExpr,
    import_stmt: Import,
    import_from: ImportFrom,
    assert_stmt: Assert,
    try_stmt: Try,
    raise_stmt: Raise,
    pass: void,
    break_stmt: void,
    continue_stmt: void,
    ellipsis_literal: void,
    global_stmt: GlobalStmt,
    with_stmt: With,
    starred: Starred,
    del_stmt: Del,
    named_expr: NamedExpr,
    if_expr: IfExpr,

    // Type aliases for backward compatibility with nested access (ast.Node.FString)
    pub const FString = fstring.FString;
    pub const FStringPart = fstring.FStringPart;

    pub const Module = struct {
        body: []Node,
    };

    pub const Assign = struct {
        targets: []Node,
        value: *Node,
    };

    pub const AnnAssign = struct {
        target: *Node,
        annotation: *Node,
        value: ?*Node,
        simple: bool,
    };

    pub const AugAssign = struct {
        target: *Node,
        op: Operator,
        value: *Node,
    };

    pub const BinOp = struct {
        left: *Node,
        op: Operator,
        right: *Node,
    };

    pub const UnaryOp = struct {
        op: UnaryOperator,
        operand: *Node,
    };

    pub const KeywordArg = struct {
        name: []const u8,
        value: Node,
    };

    pub const Call = struct {
        func: *Node,
        args: []Node,
        keyword_args: []KeywordArg,
    };

    pub const Name = struct {
        id: []const u8,
    };

    pub const Constant = struct {
        value: Value,
    };

    pub const If = struct {
        condition: *Node,
        body: []Node,
        else_body: []Node,
    };

    pub const For = struct {
        target: *Node,
        iter: *Node,
        body: []Node,
    };

    pub const While = struct {
        condition: *Node,
        body: []Node,
    };

    pub const FunctionDef = struct {
        name: []const u8,
        args: []Arg,
        body: []Node,
        is_async: bool,
        decorators: []Node,
        return_type: ?[]const u8 = null,
        is_nested: bool = false,
        captured_vars: [][]const u8 = &[_][]const u8{},
        vararg: ?[]const u8 = null, // *args parameter name
        kwarg: ?[]const u8 = null, // **kwargs parameter name
    };

    pub const Lambda = struct {
        args: []Arg,
        body: *Node, // Single expression, not statement list
    };

    pub const ClassDef = struct {
        name: []const u8,
        bases: [][]const u8,
        body: []Node,
    };

    pub const Return = struct {
        value: ?*Node,
    };

    pub const Compare = struct {
        left: *Node,
        ops: []CompareOp,
        comparators: []Node,
    };

    pub const BoolOp = struct {
        op: BoolOperator,
        values: []Node,
    };

    pub const List = struct {
        elts: []Node,
    };

    pub const ListComp = struct {
        elt: *Node, // Expression to evaluate for each element
        generators: []Comprehension, // One or more for clauses
    };

    pub const Comprehension = struct {
        target: *Node, // Loop variable (e.g., 'x' in 'for x in items')
        iter: *Node, // Iterable (e.g., 'items')
        ifs: []Node, // Optional filter conditions
    };

    pub const Dict = struct {
        keys: []Node,
        values: []Node,
    };

    pub const DictComp = struct {
        key: *Node, // Key expression
        value: *Node, // Value expression
        generators: []Comprehension, // One or more for clauses
    };

    pub const Set = struct {
        elts: []Node,
    };

    pub const Tuple = struct {
        elts: []Node,
    };

    pub const Subscript = struct {
        value: *Node,
        slice: Slice,
    };

    pub const Slice = union(enum) {
        index: *Node, // items[0]
        slice: SliceRange, // items[1:3]
    };

    pub const SliceRange = struct {
        lower: ?*Node, // start (null = from beginning)
        upper: ?*Node, // end (null = to end)
        step: ?*Node, // step (null = 1)
    };

    pub const Attribute = struct {
        value: *Node,
        attr: []const u8,
    };

    pub const ExprStmt = struct {
        value: *Node,
    };

    pub const AwaitExpr = struct {
        value: *Node,
    };

    /// Import statement: import numpy as np, import os.path
    pub const Import = struct {
        module: []const u8, // "numpy" or "os.path"
        asname: ?[]const u8, // "np" or null
    };

    /// From-import statement: from numpy import array, zeros
    pub const ImportFrom = struct {
        module: []const u8, // "numpy"
        names: [][]const u8, // ["array", "zeros"]
        asnames: []?[]const u8, // [null, null] or ["arr", null]
    };

    /// Assert statement: assert condition or assert condition, message
    pub const Assert = struct {
        condition: *Node,
        msg: ?*Node,
    };

    /// Try/except/finally statement
    pub const Try = struct {
        body: []Node, // try block
        handlers: []ExceptHandler, // except clauses
        else_body: []Node, // else block (optional, rarely used)
        finalbody: []Node, // finally block (optional)
    };

    /// Exception handler clause
    pub const ExceptHandler = struct {
        type: ?[]const u8, // Exception type name (or null for bare except)
        name: ?[]const u8, // Variable name (as e) - not implementing yet
        body: []Node, // Handler body
    };

    /// Raise statement: raise or raise Exception("msg")
    pub const Raise = struct {
        exc: ?*Node, // Exception to raise (or null for bare raise)
    };

    /// Global statement: global x, y, z
    pub const GlobalStmt = struct {
        names: [][]const u8, // Variable names to mark as global
    };

    /// With statement: with expr as var: body
    pub const With = struct {
        context_expr: *Node, // Expression (e.g., open("file"))
        optional_vars: ?[]const u8, // Variable name (e.g., "f") or null
        body: []Node, // Body statements
    };

    pub const Starred = struct {
        value: *Node, // The expression being unpacked (e.g., [1,2,3] in *[1,2,3])
    };

    /// Del statement: del x, del x, y, del obj.attr
    pub const Del = struct {
        targets: []Node, // Targets to delete (names, subscripts, attributes)
    };

    /// Named expression (walrus operator): (x := value)
    pub const NamedExpr = struct {
        target: *Node, // Name node
        value: *Node, // Expression
    };

    /// Conditional expression (ternary): value if condition else orelse_value
    pub const IfExpr = struct {
        body: *Node, // value to return if condition is true
        condition: *Node, // condition (can't use 'test' - reserved keyword in Zig)
        orelse_value: *Node, // value to return if condition is false (can't use 'orelse' - reserved)
    };

    /// Recursively free all allocations in the AST
    pub fn deinit(self: *const Node, allocator: std.mem.Allocator) void {
        const deinit_impl = @import("deinit.zig");
        deinit_impl.deinit(self, allocator);
    }
};

pub const Operator = enum {
    Add,
    Sub,
    Mult,
    Div,
    FloorDiv,
    Mod,
    Pow,
    BitAnd,
    BitOr,
    BitXor,
    LShift,
    RShift,
};

pub const CompareOp = enum {
    Eq,
    NotEq,
    Lt,
    LtEq,
    Gt,
    GtEq,
    In,
    NotIn,
    Is,
    IsNot,
};

pub const BoolOperator = enum {
    And,
    Or,
};

pub const UnaryOperator = enum {
    Not,
    UAdd, // Unary plus (+x)
    USub, // Unary minus (-x)
    Invert, // Bitwise NOT (~x)
};

pub const Value = union(enum) {
    int: i64,
    float: f64,
    string: []const u8,
    bool: bool,
    none: void,
};

pub const Arg = struct {
    name: []const u8,
    type_annotation: ?[]const u8,
    default: ?*Node,
};

/// Parse JSON AST from Python's ast.dump()
pub fn parseFromJson(allocator: std.mem.Allocator, json_str: []const u8) !Node {
    // TODO: Implement JSON → AST parsing
    // For now, this is a stub that will be implemented in Phase 1
    _ = allocator;
    _ = json_str;
    return error.NotImplemented;
}
