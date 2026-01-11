//! Intermediate Representation for Zig code generation.
//!
//! This module defines the IR types used in the multi-pass build system:
//! - Pass 1: Python AST -> ZigIR (this module)
//! - Pass 2: ZigIR -> MutationAnalysis
//! - Pass 3: ZigIR + MutationAnalysis -> Zig source code

const std = @import("std");

/// Intermediate Representation for Zig statements
pub const ZigIR = union(enum) {
    /// const name: type = init;
    const_decl: ConstDecl,

    /// var name: type = init;
    var_decl: VarDecl,

    /// var name: type = undefined;
    var_undef: VarUndef,

    /// target = value;
    assign: Assign,

    /// target op= value; (e.g., +=, -=)
    aug_assign: AugAssign,

    /// if (cond) { ... } else { ... }
    if_stmt: IfStmt,

    /// while (cond) { ... }
    while_loop: WhileLoop,

    /// for (iter) |item| { ... }
    for_loop: ForLoop,

    /// inline for (iter) |item| { ... }
    inline_for: InlineFor,

    /// fn name(params) type { ... }
    function: Function,

    /// return value;
    return_: Return,

    /// break; or break :label value;
    break_: Break,

    /// continue; or continue :label;
    continue_: Continue,

    /// Expression statement
    expr_stmt: ExprStmt,

    /// Block with optional label
    block: Block,

    /// defer expr;
    defer_: Defer,

    /// errdefer expr;
    errdefer_: Errdefer,

    /// _ = expr; (discard)
    discard: Discard,

    /// Comment
    comment: Comment,

    /// Blank line
    blank: void,

    /// Raw Zig code (escape hatch for unsupported constructs)
    raw: []const u8,
};

/// const name: type = init;
pub const ConstDecl = struct {
    name: []const u8,
    type_: ?*const ZigIRType = null,
    init: *const ZigIRExpr,
    is_pub: bool = false,
};

/// var name: type = init;
pub const VarDecl = struct {
    name: []const u8,
    type_: ?*const ZigIRType = null,
    init: *const ZigIRExpr,
    is_pub: bool = false,
};

/// var name: type = undefined;
pub const VarUndef = struct {
    name: []const u8,
    type_: *const ZigIRType,
};

/// target = value;
pub const Assign = struct {
    target: *const ZigIRExpr,
    value: *const ZigIRExpr,
};

/// target op= value;
pub const AugAssign = struct {
    target: *const ZigIRExpr,
    op: AugOp,
    value: *const ZigIRExpr,
};

pub const AugOp = enum {
    add, // +=
    sub, // -=
    mul, // *=
    div, // /=
    mod, // %=
    bit_and, // &=
    bit_or, // |=
    bit_xor, // ^=
    lshift, // <<=
    rshift, // >>=
};

/// if (cond) { ... } else if (...) { ... } else { ... }
pub const IfStmt = struct {
    condition: *const ZigIRExpr,
    then_body: []const ZigIR,
    else_ifs: []const ElseIf = &.{},
    else_body: ?[]const ZigIR = null,
};

pub const ElseIf = struct {
    condition: *const ZigIRExpr,
    body: []const ZigIR,
};

/// while (cond) { ... }
pub const WhileLoop = struct {
    condition: *const ZigIRExpr,
    body: []const ZigIR,
    else_body: ?[]const ZigIR = null,
};

/// for (iter) |item| { ... }
pub const ForLoop = struct {
    target: []const u8,
    iter: *const ZigIRExpr,
    body: []const ZigIR,
    else_body: ?[]const ZigIR = null,
};

/// inline for (iter) |item| { ... }
pub const InlineFor = struct {
    target: []const u8,
    iter: *const ZigIRExpr,
    body: []const ZigIR,
};

/// fn name(params) return_type { ... }
pub const Function = struct {
    name: []const u8,
    params: []const FunctionParam,
    return_type: ?*const ZigIRType = null,
    body: []const ZigIR,
    is_pub: bool = false,
    is_inline: bool = false,
};

pub const FunctionParam = struct {
    name: []const u8,
    type_: ?*const ZigIRType = null,
    default: ?*const ZigIRExpr = null,
};

/// return value;
pub const Return = struct {
    value: ?*const ZigIRExpr = null,
};

/// break :label value;
pub const Break = struct {
    label: ?[]const u8 = null,
    value: ?*const ZigIRExpr = null,
};

/// continue :label;
pub const Continue = struct {
    label: ?[]const u8 = null,
};

/// Expression statement
pub const ExprStmt = struct {
    expr: *const ZigIRExpr,
};

/// { ... } or label: { ... }
pub const Block = struct {
    label: ?[]const u8 = null,
    body: []const ZigIR,
};

/// defer expr;
pub const Defer = struct {
    expr: *const ZigIRExpr,
};

/// errdefer expr;
pub const Errdefer = struct {
    expr: *const ZigIRExpr,
};

/// _ = expr;
pub const Discard = struct {
    expr: *const ZigIRExpr,
};

/// // comment
pub const Comment = struct {
    text: []const u8,
};

// ============================================================================
// Expressions
// ============================================================================

/// Intermediate Representation for Zig expressions
pub const ZigIRExpr = union(enum) {
    /// Integer literal
    int: i64,

    /// Float literal
    float: f64,

    /// Boolean literal
    bool_: bool,

    /// String literal
    string: []const u8,

    /// null
    null_: void,

    /// undefined
    undefined: void,

    /// Variable reference
    name: []const u8,

    /// obj.field
    field_access: FieldAccess,

    /// obj[index]
    subscript: Subscript,

    /// obj[start..end]
    slice: Slice,

    /// func(args)
    call: Call,

    /// a + b, a < b, etc.
    binop: BinOp,

    /// -a, !a, etc.
    unaryop: UnaryOp,

    /// a and b, a or b
    boolop: BoolOp,

    /// if (cond) a else b
    ternary: Ternary,

    /// [_]T{ ... } or &[_]T{ ... }
    array: Array,

    /// .{ a, b, c }
    tuple: Tuple,

    /// Type{ .field = value }
    struct_init: StructInit,

    /// @as(Type, value)
    cast: Cast,

    /// @builtin(args)
    builtin: Builtin,

    /// try expr
    try_: Try,

    /// catch |err| expr
    catch_: Catch,

    /// orelse expr
    orelse_: Orelse,

    /// &expr
    address_of: AddressOf,

    /// expr.*
    deref: Deref,

    /// Raw Zig expression (escape hatch)
    raw: []const u8,
};

pub const FieldAccess = struct {
    object: *const ZigIRExpr,
    field: []const u8,
};

pub const Subscript = struct {
    object: *const ZigIRExpr,
    index: *const ZigIRExpr,
};

pub const Slice = struct {
    object: *const ZigIRExpr,
    start: ?*const ZigIRExpr = null,
    end: ?*const ZigIRExpr = null,
};

pub const Call = struct {
    func: *const ZigIRExpr,
    args: []const *const ZigIRExpr,
};

pub const BinOp = struct {
    left: *const ZigIRExpr,
    op: BinOpKind,
    right: *const ZigIRExpr,
};

pub const BinOpKind = enum {
    // Arithmetic
    add,
    sub,
    mul,
    div,
    mod,
    // Bitwise
    bit_and,
    bit_or,
    bit_xor,
    lshift,
    rshift,
    // Comparison
    eq,
    ne,
    lt,
    le,
    gt,
    ge,
    // Array
    concat, // ++
};

pub const UnaryOp = struct {
    op: UnaryOpKind,
    operand: *const ZigIRExpr,
};

pub const UnaryOpKind = enum {
    neg, // -
    bit_not, // ~
    logic_not, // !
};

pub const BoolOp = struct {
    op: BoolOpKind,
    operands: []const *const ZigIRExpr,
};

pub const BoolOpKind = enum {
    @"and",
    @"or",
};

pub const Ternary = struct {
    condition: *const ZigIRExpr,
    then_expr: *const ZigIRExpr,
    else_expr: *const ZigIRExpr,
};

pub const Array = struct {
    elem_type: ?*const ZigIRType = null,
    elements: []const *const ZigIRExpr,
    is_slice: bool = false, // true for &[_]T{...}
};

pub const Tuple = struct {
    elements: []const *const ZigIRExpr,
};

pub const StructInit = struct {
    type_name: ?[]const u8 = null, // null for anonymous .{ }
    fields: []const StructField,
};

pub const StructField = struct {
    name: []const u8,
    value: *const ZigIRExpr,
};

pub const Cast = struct {
    type_: *const ZigIRType,
    value: *const ZigIRExpr,
};

pub const Builtin = struct {
    name: []const u8, // without @
    args: []const *const ZigIRExpr,
};

pub const Try = struct {
    expr: *const ZigIRExpr,
};

pub const Catch = struct {
    expr: *const ZigIRExpr,
    capture: ?[]const u8 = null,
    handler: *const ZigIRExpr,
};

pub const Orelse = struct {
    expr: *const ZigIRExpr,
    default: *const ZigIRExpr,
};

pub const AddressOf = struct {
    expr: *const ZigIRExpr,
};

pub const Deref = struct {
    expr: *const ZigIRExpr,
};

// ============================================================================
// Types
// ============================================================================

/// Intermediate Representation for Zig types
pub const ZigIRType = union(enum) {
    // Primitives
    i8_,
    i16_,
    i32_,
    i64_,
    i128_,
    u8_,
    u16_,
    u32_,
    u64_,
    u128_,
    usize_,
    f32_,
    f64_,
    bool_,
    void_,
    noreturn_,
    type_,
    comptime_int,
    comptime_float,

    /// []T or [N]T
    array: ArrayType,

    /// *T or *const T
    pointer: PointerType,

    /// ?T
    optional: OptionalType,

    /// !T or E!T
    error_union: ErrorUnionType,

    /// Named type (struct, enum, etc.)
    named: []const u8,

    /// fn(args) return_type
    function: FunctionType,

    /// @TypeOf(expr)
    type_of: *const ZigIRExpr,

    /// anytype
    anytype_,
};

pub const ArrayType = struct {
    elem_type: *const ZigIRType,
    size: ?usize = null, // null for slices []T
};

pub const PointerType = struct {
    child: *const ZigIRType,
    is_const: bool = false,
    is_many: bool = false, // [*]T vs *T
};

pub const OptionalType = struct {
    child: *const ZigIRType,
};

pub const ErrorUnionType = struct {
    error_set: ?[]const u8 = null, // null for anyerror
    value: *const ZigIRType,
};

pub const FunctionType = struct {
    params: []const *const ZigIRType,
    return_type: *const ZigIRType,
};

// ============================================================================
// Memory Management
// ============================================================================

/// Free an IR expression tree
pub fn freeExpr(expr: *const ZigIRExpr, allocator: std.mem.Allocator) void {
    switch (expr.*) {
        .field_access => |fa| {
            freeExpr(fa.object, allocator);
        },
        .subscript => |s| {
            freeExpr(s.object, allocator);
            freeExpr(s.index, allocator);
        },
        .call => |c| {
            freeExpr(c.func, allocator);
            for (c.args) |arg| {
                freeExpr(arg, allocator);
            }
            allocator.free(c.args);
        },
        .binop => |b| {
            freeExpr(b.left, allocator);
            freeExpr(b.right, allocator);
        },
        .unaryop => |u| {
            freeExpr(u.operand, allocator);
        },
        .array => |a| {
            for (a.elements) |elem| {
                freeExpr(elem, allocator);
            }
            allocator.free(a.elements);
        },
        // Simple variants - nothing to free
        else => {},
    }
    allocator.destroy(@constCast(expr));
}

/// Free an IR statement tree
pub fn freeStmt(stmt: ZigIR, allocator: std.mem.Allocator) void {
    switch (stmt) {
        .const_decl => |cd| {
            freeExpr(cd.init, allocator);
        },
        .var_decl => |vd| {
            freeExpr(vd.init, allocator);
        },
        .assign => |a| {
            freeExpr(a.target, allocator);
            freeExpr(a.value, allocator);
        },
        .if_stmt => |i| {
            freeExpr(i.condition, allocator);
            for (i.then_body) |s| {
                freeStmt(s, allocator);
            }
            allocator.free(i.then_body);
            if (i.else_body) |eb| {
                for (eb) |s| {
                    freeStmt(s, allocator);
                }
                allocator.free(eb);
            }
        },
        .expr_stmt => |e| {
            freeExpr(e.expr, allocator);
        },
        // Simple variants
        else => {},
    }
}

// ============================================================================
// Debug Printing
// ============================================================================

/// Print IR for debugging
pub fn debugPrintStmt(stmt: ZigIR, writer: anytype, indent: usize) !void {
    const spaces = "                                ";
    const ind = spaces[0..@min(indent * 2, spaces.len)];

    switch (stmt) {
        .const_decl => |cd| {
            try writer.print("{s}const_decl: {s}\n", .{ ind, cd.name });
        },
        .var_decl => |vd| {
            try writer.print("{s}var_decl: {s}\n", .{ ind, vd.name });
        },
        .assign => |a| {
            try writer.print("{s}assign:\n", .{ind});
            try debugPrintExpr(a.target, writer, indent + 1);
            try debugPrintExpr(a.value, writer, indent + 1);
        },
        .if_stmt => |i| {
            try writer.print("{s}if_stmt:\n", .{ind});
            try debugPrintExpr(i.condition, writer, indent + 1);
            for (i.then_body) |s| {
                try debugPrintStmt(s, writer, indent + 1);
            }
        },
        .return_ => |r| {
            try writer.print("{s}return\n", .{ind});
            if (r.value) |v| {
                try debugPrintExpr(v, writer, indent + 1);
            }
        },
        .expr_stmt => |e| {
            try writer.print("{s}expr_stmt:\n", .{ind});
            try debugPrintExpr(e.expr, writer, indent + 1);
        },
        .raw => |r| {
            try writer.print("{s}raw: {s}\n", .{ ind, r[0..@min(50, r.len)] });
        },
        else => {
            try writer.print("{s}{s}\n", .{ ind, @tagName(stmt) });
        },
    }
}

pub fn debugPrintExpr(expr: *const ZigIRExpr, writer: anytype, indent: usize) !void {
    const spaces = "                                ";
    const ind = spaces[0..@min(indent * 2, spaces.len)];

    switch (expr.*) {
        .int => |i| try writer.print("{s}int: {d}\n", .{ ind, i }),
        .float => |f| try writer.print("{s}float: {d}\n", .{ ind, f }),
        .bool_ => |b| try writer.print("{s}bool: {}\n", .{ ind, b }),
        .string => |s| try writer.print("{s}string: \"{s}\"\n", .{ ind, s }),
        .name => |n| try writer.print("{s}name: {s}\n", .{ ind, n }),
        .binop => |b| {
            try writer.print("{s}binop: {s}\n", .{ ind, @tagName(b.op) });
            try debugPrintExpr(b.left, writer, indent + 1);
            try debugPrintExpr(b.right, writer, indent + 1);
        },
        .call => |c| {
            try writer.print("{s}call:\n", .{ind});
            try debugPrintExpr(c.func, writer, indent + 1);
            for (c.args) |arg| {
                try debugPrintExpr(arg, writer, indent + 1);
            }
        },
        .raw => |r| try writer.print("{s}raw: {s}\n", .{ ind, r[0..@min(50, r.len)] }),
        else => try writer.print("{s}{s}\n", .{ ind, @tagName(expr.*) }),
    }
}
