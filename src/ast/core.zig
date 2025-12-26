const std = @import("std");
const fstring = @import("fstring.zig");

/// Source location information for AST nodes
pub const SourceLoc = struct {
    line: u32 = 0,
    col: u32 = 0,
    end_line: u32 = 0,
    end_col: u32 = 0,
};

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
    genexp: GenExp,
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
    nonlocal_stmt: NonlocalStmt,
    with_stmt: With,
    starred: Starred,
    double_starred: DoubleStarred,
    del_stmt: Del,
    named_expr: NamedExpr,
    if_expr: IfExpr,
    yield_stmt: Yield,
    yield_from_stmt: YieldFrom,
    slice_expr: SliceRange,
    match_stmt: Match,

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
        orelse_body: ?[]Node = null, // Optional else clause (for/else)
        is_async: bool = false, // True for "async for" loops
    };

    pub const While = struct {
        condition: *Node,
        body: []Node,
        orelse_body: ?[]Node = null, // Optional else clause (while/else)
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
        loc: SourceLoc = .{}, // Source location
    };

    pub const Lambda = struct {
        args: []Arg,
        body: *Node, // Single expression, not statement list
    };

    pub const ClassDef = struct {
        name: []const u8,
        bases: [][]const u8,
        body: []Node,
        metaclass: ?[]const u8 = null,
        /// Type parameters for Generic[T, U, ...] classes
        type_params: [][]const u8 = &[_][]const u8{},
        /// Decorators (e.g., @logic_table, @dataclass)
        decorators: []Node = &[_]Node{},
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

    pub const GenExp = struct {
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

    /// Import statement: import json, import os.path
    pub const Import = struct {
        module: []const u8, // "json" or "os.path"
        asname: ?[]const u8, // "np" or null
    };

    /// From-import statement: from os import path, getcwd
    pub const ImportFrom = struct {
        module: []const u8, // "os"
        names: [][]const u8, // ["path", "getcwd"]
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

    /// Raise statement: raise or raise Exception("msg") or raise Exception("msg") from cause
    pub const Raise = struct {
        exc: ?*Node, // Exception to raise (or null for bare raise)
        cause: ?*Node = null, // Cause exception for "raise X from Y" syntax
    };

    /// Yield statement: yield or yield value or yield a, b
    pub const Yield = struct {
        value: ?*Node, // Value to yield (or null for bare yield)
    };

    /// Yield from statement: yield from iterable (PEP 380)
    pub const YieldFrom = struct {
        value: *Node, // Iterable to yield from
    };

    /// Global statement: global x, y, z
    pub const GlobalStmt = struct {
        names: [][]const u8, // Variable names to mark as global
    };

    /// Nonlocal statement: nonlocal x, y, z
    pub const NonlocalStmt = struct {
        names: [][]const u8, // Variable names to mark as nonlocal
    };

    /// With statement: with expr as var: body
    pub const With = struct {
        context_expr: *Node, // Expression (e.g., open("file"))
        optional_vars: ?*Node, // Target node: name, tuple, list, etc. (e.g., "f" or "(a, b)")
        body: []Node, // Body statements
    };

    pub const Starred = struct {
        value: *Node, // The expression being unpacked (e.g., [1,2,3] in *[1,2,3])
    };

    /// Double starred for kwargs unpacking: func(**kwargs)
    pub const DoubleStarred = struct {
        value: *Node, // The expression being unpacked (e.g., d in **d)
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

    /// Match statement (PEP 634): match subject: case pattern: body
    pub const Match = struct {
        subject: *Node, // The value being matched
        cases: []MatchCase, // List of case clauses
    };

    /// Single case clause in a match statement
    pub const MatchCase = struct {
        pattern: MatchPattern, // Pattern to match
        guard: ?*Node, // Optional guard condition (case x if x > 0)
        body: []Node, // Statements to execute if matched
    };

    /// Pattern types for match/case
    pub const MatchPattern = union(enum) {
        literal: *Node, // case 1, case "hello", case True
        capture: []const u8, // case x (capture variable)
        wildcard: void, // case _
        sequence: []MatchPattern, // case [a, b, c]
        mapping: []MappingPatternEntry, // case {"key": value}
        class_pattern: ClassPattern, // case Point(x=0, y=0)
        or_pattern: []MatchPattern, // case 1 | 2 | 3
        as_pattern: AsPattern, // case pattern as name
        value: *Node, // case Foo.Bar.x (dotted value pattern)
    };

    pub const MappingPatternEntry = struct {
        key: *Node, // Key (literal or constant)
        pattern: MatchPattern, // Pattern for value
    };

    pub const ClassPattern = struct {
        cls: []const u8, // Class name
        positional: []MatchPattern, // Positional patterns
        keyword: []KeywordPattern, // Keyword patterns (x=0)
    };

    pub const KeywordPattern = struct {
        name: []const u8,
        pattern: MatchPattern,
    };

    pub const AsPattern = struct {
        pattern: *MatchPattern, // Inner pattern
        name: []const u8, // Capture name
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
    MatMul, // Matrix multiplication (@)
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
    bigint: []const u8, // String representation for integers > i64
    float: f64,
    string: []const u8,
    bytes: []const u8, // Bytes literal (b"...") - raw bytes, no UTF-8 encoding
    bool: bool,
    none: void,
    complex: f64, // Imaginary component (e.g., 0j -> 0.0, 1j -> 1.0)
};

pub const Arg = struct {
    name: []const u8,
    type_annotation: ?[]const u8,
    default: ?*Node,
};

/// Parse JSON AST from Python's ast.dump()
/// This function is used when receiving AST from external Python tools
pub fn parseFromJson(allocator: std.mem.Allocator, json_str: []const u8) !Node {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer parsed.deinit();

    return try nodeFromJson(allocator, parsed.value);
}

/// Convert a JSON value to an AST Node
fn nodeFromJson(allocator: std.mem.Allocator, json: std.json.Value) !Node {
    const obj = json.object;
    const node_type = obj.get("_type") orelse return error.MissingNodeType;

    const type_str = node_type.string;

    // Handle different node types
    if (std.mem.eql(u8, type_str, "Module")) {
        return try parseModule(allocator, obj);
    } else if (std.mem.eql(u8, type_str, "Constant")) {
        return try parseConstant(allocator, obj);
    } else if (std.mem.eql(u8, type_str, "Name")) {
        return try parseName(allocator, obj);
    } else if (std.mem.eql(u8, type_str, "BinOp")) {
        return try parseBinOp(allocator, obj);
    } else if (std.mem.eql(u8, type_str, "UnaryOp")) {
        return try parseUnaryOp(allocator, obj);
    } else if (std.mem.eql(u8, type_str, "Call")) {
        return try parseCall(allocator, obj);
    } else if (std.mem.eql(u8, type_str, "Expr")) {
        const value = obj.get("value") orelse return error.MissingValue;
        const node = try allocator.create(Node);
        node.* = try nodeFromJson(allocator, value);
        return .{ .Expr = .{ .expression = node } };
    } else if (std.mem.eql(u8, type_str, "Assign")) {
        return try parseAssign(allocator, obj);
    } else if (std.mem.eql(u8, type_str, "FunctionDef")) {
        return try parseFunctionDef(allocator, obj);
    } else {
        return error.UnsupportedNodeType;
    }
}

fn parseModule(allocator: std.mem.Allocator, obj: std.json.ObjectMap) !Node {
    const body_json = obj.get("body") orelse return error.MissingBody;
    var body = std.ArrayList(*Node){};

    for (body_json.array.items) |item| {
        const node = try allocator.create(Node);
        node.* = try nodeFromJson(allocator, item);
        try body.append(allocator, node);
    }

    return .{ .module = .{ .body = try body.toOwnedSlice(allocator) } };
}

fn parseConstant(allocator: std.mem.Allocator, obj: std.json.ObjectMap) !Node {
    const value = obj.get("value") orelse return error.MissingValue;

    const const_value: Value = switch (value) {
        .null => .None,
        .bool => |b| .{ .Bool = b },
        .integer => |i| .{ .Int = i },
        .float => |f| .{ .Float = f },
        .string => |s| .{ .String = try allocator.dupe(u8, s) },
        else => return error.UnsupportedConstantType,
    };

    return .{ .constant = .{ .value = const_value } };
}

fn parseName(allocator: std.mem.Allocator, obj: std.json.ObjectMap) !Node {
    const id = obj.get("id") orelse return error.MissingId;
    return .{ .name = .{
        .id = try allocator.dupe(u8, id.string),
        .ctx = .Load,
    } };
}

fn parseBinOp(allocator: std.mem.Allocator, obj: std.json.ObjectMap) !Node {
    const left_json = obj.get("left") orelse return error.MissingLeft;
    const right_json = obj.get("right") orelse return error.MissingRight;
    const op_json = obj.get("op") orelse return error.MissingOp;

    const left = try allocator.create(Node);
    left.* = try nodeFromJson(allocator, left_json);

    const right = try allocator.create(Node);
    right.* = try nodeFromJson(allocator, right_json);

    const op_type = op_json.object.get("_type").?.string;
    const op: Operator = if (std.mem.eql(u8, op_type, "Add"))
        .Add
    else if (std.mem.eql(u8, op_type, "Sub"))
        .Sub
    else if (std.mem.eql(u8, op_type, "Mult"))
        .Mult
    else if (std.mem.eql(u8, op_type, "Div"))
        .Div
    else
        .Add;

    return .{ .binop = .{ .left = left, .right = right, .op = op } };
}

fn parseUnaryOp(allocator: std.mem.Allocator, obj: std.json.ObjectMap) !Node {
    const operand_json = obj.get("operand") orelse return error.MissingOperand;
    const op_json = obj.get("op") orelse return error.MissingOp;

    const operand = try allocator.create(Node);
    operand.* = try nodeFromJson(allocator, operand_json);

    const op_type = op_json.object.get("_type").?.string;
    const op: UnaryOperator = if (std.mem.eql(u8, op_type, "UAdd"))
        .UAdd
    else if (std.mem.eql(u8, op_type, "USub"))
        .USub
    else if (std.mem.eql(u8, op_type, "Not"))
        .Not
    else
        .UAdd;

    return .{ .unaryop = .{ .operand = operand, .op = op } };
}

fn parseCall(allocator: std.mem.Allocator, obj: std.json.ObjectMap) !Node {
    const func_json = obj.get("func") orelse return error.MissingFunc;
    const args_json = obj.get("args") orelse return error.MissingArgs;

    const func = try allocator.create(Node);
    func.* = try nodeFromJson(allocator, func_json);

    var args = std.ArrayList(*Node){};
    for (args_json.array.items) |arg| {
        const arg_node = try allocator.create(Node);
        arg_node.* = try nodeFromJson(allocator, arg);
        try args.append(allocator, arg_node);
    }

    return .{ .call = .{
        .func = func,
        .args = try args.toOwnedSlice(allocator),
        .keyword_args = &.{},
    } };
}

fn parseAssign(allocator: std.mem.Allocator, obj: std.json.ObjectMap) !Node {
    const targets_json = obj.get("targets") orelse return error.MissingTargets;
    const value_json = obj.get("value") orelse return error.MissingValue;

    var targets = std.ArrayList(*Node){};
    for (targets_json.array.items) |target| {
        const target_node = try allocator.create(Node);
        target_node.* = try nodeFromJson(allocator, target);
        try targets.append(allocator, target_node);
    }

    const value = try allocator.create(Node);
    value.* = try nodeFromJson(allocator, value_json);

    return .{ .assign = .{
        .targets = try targets.toOwnedSlice(allocator),
        .value = value,
    } };
}

fn parseFunctionDef(allocator: std.mem.Allocator, obj: std.json.ObjectMap) !Node {
    const name = obj.get("name") orelse return error.MissingName;
    const body_json = obj.get("body") orelse return error.MissingBody;

    var body = std.ArrayList(Node){};
    for (body_json.array.items) |item| {
        try body.append(allocator, try nodeFromJson(allocator, item));
    }

    return .{ .function_def = .{
        .name = try allocator.dupe(u8, name.string),
        .args = &.{},
        .body = try body.toOwnedSlice(allocator),
        .decorator_list = &.{},
        .returns = null,
        .defaults = &.{},
        .kwonly_args = &.{},
        .kwonly_defaults = &.{},
        .kw_defaults = &.{},
    } };
}
