/// ZigStatement - Structured statement representation for Zig codegen
///
/// This abstraction separates statement semantics from string emission, enabling:
/// - Type-safe statement construction (compile-time validation)
/// - Unified comparison path (all comparisons flow through single dispatch)
/// - Statement-level transformations before emission
/// - Consistent formatting and indentation
///
/// Key design principle: Statements are constructed as structured data,
/// then emitted to strings only at the final output stage.
///
/// Integration with existing systems:
/// - ZigValue: Used for expression values within statements
/// - ZigType: Used for type annotations in declarations
/// - ZigBuilder: Handles actual string emission
///
const std = @import("std");
const zig_value = @import("zig_value.zig");
const zig_type = @import("zig_type.zig");

pub const ZigValue = zig_value.ZigValue;
pub const ZigType = zig_type.ZigType;
pub const TypeConfidence = zig_value.TypeConfidence;
pub const CertainType = zig_value.CertainType;
pub const CompOp = zig_value.CompOp;

/// Forward declaration for ZigExpr (defined in zig_expr.zig)
/// Using raw string for now until zig_expr.zig is created
pub const ZigExpr = @import("zig_expr.zig").ZigExpr;

/// ZigStatement - Union of all possible Zig statement types
pub const ZigStatement = union(enum) {
    // ========== Declarations ==========

    /// const x: T = value;
    const_decl: ConstDecl,

    /// var x: T = value;
    var_decl: VarDecl,

    /// var x: T = undefined;
    var_undef: VarUndef,

    // ========== Assignments ==========

    /// target = value;
    assign: Assign,

    /// target op= value; (e.g., x += 1)
    aug_assign: AugAssign,

    /// obj.field = value;
    field_assign: FieldAssign,

    /// container[index] = value;
    subscript_assign: SubscriptAssign,

    // ========== Control Flow ==========

    /// if (cond) { ... } else if (cond2) { ... } else { ... }
    if_stmt: IfStmt,

    /// while (cond) { ... }
    while_loop: WhileLoop,

    /// for (iter) |capture| { ... }
    for_loop: ForLoop,

    /// for (iter, 0..) |capture, index| { ... }
    for_indexed: ForIndexed,

    /// break; or break :label; or break :label value;
    break_: Break,

    /// continue; or continue :label;
    continue_: Continue,

    /// return; or return value;
    return_: Return,

    // ========== Error Handling ==========

    /// defer expr;
    defer_: Defer,

    /// errdefer expr;
    errdefer_: Errdefer,

    /// switch (value) { ... }
    switch_: Switch,

    // ========== Expression Statement ==========

    /// expr; (execute for side effects)
    expr_stmt: ExprStmt,

    /// _ = expr; (discard result)
    discard_stmt: DiscardStmt,

    // ========== Scopes ==========

    /// { ... } or label: { ... }
    block: Block,

    /// inline for (fields) |f| { ... }
    inline_for: InlineFor,

    // ========== Meta ==========

    /// // comment text
    comment: Comment,

    /// Empty line for formatting
    blank: void,

    /// Raw Zig code (escape hatch for complex patterns)
    raw: Raw,

    /// Check if this statement is a declaration (const/var)
    pub fn isDeclaration(self: ZigStatement) bool {
        return switch (self) {
            .const_decl, .var_decl, .var_undef => true,
            else => false,
        };
    }

    /// Check if this statement is an assignment
    pub fn isAssignment(self: ZigStatement) bool {
        return switch (self) {
            .assign, .aug_assign, .field_assign, .subscript_assign => true,
            else => false,
        };
    }

    /// Check if this statement is control flow
    pub fn isControlFlow(self: ZigStatement) bool {
        return switch (self) {
            .if_stmt, .while_loop, .for_loop, .for_indexed, .break_, .continue_, .return_, .switch_ => true,
            else => false,
        };
    }
};

// ========== Declaration Structs ==========

/// const name: type = init;
pub const ConstDecl = struct {
    /// Variable name
    name: []const u8,
    /// Type annotation (optional - null means infer)
    type_: ?*const ZigType = null,
    /// Initializer expression
    init: *const ZigExpr,
    /// Add _ = &name; after declaration (for potentially unused vars)
    add_discard: bool = false,
};

/// var name: type = init;
pub const VarDecl = struct {
    /// Variable name
    name: []const u8,
    /// Type annotation (optional - null means infer)
    type_: ?*const ZigType = null,
    /// Initializer expression
    init: *const ZigExpr,
    /// Add _ = &name; after declaration (for potentially unused vars)
    add_discard: bool = false,
};

/// var name: type = undefined;
pub const VarUndef = struct {
    /// Variable name
    name: []const u8,
    /// Type annotation (required for undefined)
    type_: *const ZigType,
    /// Add _ = &name; after declaration
    add_discard: bool = false,
};

// ========== Assignment Structs ==========

/// target = value;
pub const Assign = struct {
    /// Left-hand side (must be assignable)
    target: *const ZigExpr,
    /// Right-hand side value
    value: *const ZigExpr,
};

/// Augmented assignment operators
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

    pub fn toOperator(self: AugOp) []const u8 {
        return switch (self) {
            .add => "+=",
            .sub => "-=",
            .mul => "*=",
            .div => "/=",
            .mod => "%=",
            .bit_and => "&=",
            .bit_or => "|=",
            .bit_xor => "^=",
            .lshift => "<<=",
            .rshift => ">>=",
        };
    }
};

/// target op= value;
pub const AugAssign = struct {
    /// Left-hand side (must be assignable)
    target: *const ZigExpr,
    /// Augmented operator
    op: AugOp,
    /// Right-hand side value
    value: *const ZigExpr,
};

/// obj.field = value;
pub const FieldAssign = struct {
    /// Object expression
    obj: *const ZigExpr,
    /// Field name
    field: []const u8,
    /// Value to assign
    value: *const ZigExpr,
};

/// container[index] = value;
pub const SubscriptAssign = struct {
    /// Container expression
    container: *const ZigExpr,
    /// Index expression
    index: *const ZigExpr,
    /// Value to assign
    value: *const ZigExpr,
};

// ========== Control Flow Structs ==========

/// if (cond) { then_body } else if (cond2) { ... } else { else_body }
pub const IfStmt = struct {
    /// Condition expression
    condition: *const ZigExpr,
    /// Then branch statements
    then_body: []const ZigStatement,
    /// Else-if branches (condition, body pairs)
    else_ifs: []const ElseIf = &.{},
    /// Else branch statements (optional)
    else_body: ?[]const ZigStatement = null,

    pub const ElseIf = struct {
        condition: *const ZigExpr,
        body: []const ZigStatement,
    };
};

/// while (cond) { body }
pub const WhileLoop = struct {
    /// Loop condition
    condition: *const ZigExpr,
    /// Loop body statements
    body: []const ZigStatement,
    /// Optional label for break/continue
    label: ?[]const u8 = null,
};

/// for (iter) |capture| { body }
pub const ForLoop = struct {
    /// Iterable expression
    iter: *const ZigExpr,
    /// Capture variable name
    capture: []const u8,
    /// Loop body statements
    body: []const ZigStatement,
    /// Optional label for break/continue
    label: ?[]const u8 = null,
};

/// for (iter, 0..) |capture, index| { body }
pub const ForIndexed = struct {
    /// Iterable expression
    iter: *const ZigExpr,
    /// Capture variable name
    capture: []const u8,
    /// Index variable name
    index: []const u8,
    /// Loop body statements
    body: []const ZigStatement,
    /// Optional label for break/continue
    label: ?[]const u8 = null,
};

/// break; or break :label; or break :label value;
pub const Break = struct {
    /// Optional label to break to
    label: ?[]const u8 = null,
    /// Optional value (for labeled blocks)
    value: ?*const ZigExpr = null,
};

/// continue; or continue :label;
pub const Continue = struct {
    /// Optional label to continue
    label: ?[]const u8 = null,
};

/// return; or return value;
pub const Return = struct {
    /// Optional return value
    value: ?*const ZigExpr = null,
};

// ========== Error Handling Structs ==========

/// defer expr;
pub const Defer = struct {
    /// Expression to defer
    expr: *const ZigExpr,
};

/// errdefer expr;
pub const Errdefer = struct {
    /// Expression to errdefer
    expr: *const ZigExpr,
    /// Optional capture for error value
    capture: ?[]const u8 = null,
};

/// switch (value) { prongs }
pub const Switch = struct {
    /// Value to switch on
    value: *const ZigExpr,
    /// Switch prongs
    prongs: []const Prong,
    /// Else prong (optional)
    else_prong: ?[]const ZigStatement = null,

    pub const Prong = struct {
        /// Case values
        cases: []const *const ZigExpr,
        /// Capture variable (optional)
        capture: ?[]const u8 = null,
        /// Prong body
        body: []const ZigStatement,
    };
};

// ========== Expression Statement Structs ==========

/// expr; (execute for side effects)
pub const ExprStmt = struct {
    /// Expression to execute
    expr: *const ZigExpr,
    /// Whether to wrap in try
    use_try: bool = false,
};

/// _ = expr; (discard result)
pub const DiscardStmt = struct {
    /// Expression whose result is discarded
    expr: *const ZigExpr,
    /// Whether to wrap in try
    use_try: bool = false,
};

// ========== Scope Structs ==========

/// { body } or label: { body; break :label value; }
pub const Block = struct {
    /// Block body statements
    body: []const ZigStatement,
    /// Optional label for the block
    label: ?[]const u8 = null,
    /// Whether this is an expression block (returns value)
    is_expr: bool = false,
};

/// inline for (@typeInfo(T).@"struct".fields) |f| { body }
pub const InlineFor = struct {
    /// Iterable expression (typically @typeInfo result)
    iter: *const ZigExpr,
    /// Capture variable name
    capture: []const u8,
    /// Optional index variable
    index: ?[]const u8 = null,
    /// Loop body statements
    body: []const ZigStatement,
};

// ========== Meta Structs ==========

/// // comment text
pub const Comment = struct {
    /// Comment text (without // prefix)
    text: []const u8,
    /// Whether this is a doc comment (///)
    is_doc: bool = false,
};

/// Raw Zig code (escape hatch)
pub const Raw = struct {
    /// Raw Zig code string
    code: []const u8,
    /// Whether to add newline after
    add_newline: bool = true,
};

// ========== Builder Helpers ==========

/// Helper to create a const declaration
pub fn constDecl(name: []const u8, init: *const ZigExpr) ZigStatement {
    return .{ .const_decl = .{ .name = name, .init = init } };
}

/// Helper to create a const declaration with type
pub fn constDeclTyped(name: []const u8, type_: *const ZigType, init: *const ZigExpr) ZigStatement {
    return .{ .const_decl = .{ .name = name, .type_ = type_, .init = init } };
}

/// Helper to create a var declaration
pub fn varDecl(name: []const u8, init: *const ZigExpr) ZigStatement {
    return .{ .var_decl = .{ .name = name, .init = init } };
}

/// Helper to create a var declaration with undefined
pub fn varUndef(name: []const u8, type_: *const ZigType) ZigStatement {
    return .{ .var_undef = .{ .name = name, .type_ = type_ } };
}

/// Helper to create an assignment
pub fn assign(target: *const ZigExpr, value: *const ZigExpr) ZigStatement {
    return .{ .assign = .{ .target = target, .value = value } };
}

/// Helper to create an augmented assignment
pub fn augAssign(target: *const ZigExpr, op: AugOp, value: *const ZigExpr) ZigStatement {
    return .{ .aug_assign = .{ .target = target, .op = op, .value = value } };
}

/// Helper to create a return statement
pub fn ret(value: ?*const ZigExpr) ZigStatement {
    return .{ .return_ = .{ .value = value } };
}

/// Helper to create a break statement
pub fn brk() ZigStatement {
    return .{ .break_ = .{} };
}

/// Helper to create a break with label
pub fn brkLabel(label: []const u8) ZigStatement {
    return .{ .break_ = .{ .label = label } };
}

/// Helper to create a break with label and value
pub fn brkValue(label: []const u8, value: *const ZigExpr) ZigStatement {
    return .{ .break_ = .{ .label = label, .value = value } };
}

/// Helper to create a continue statement
pub fn cont() ZigStatement {
    return .{ .continue_ = .{} };
}

/// Helper to create an expression statement
pub fn exprStmt(expr: *const ZigExpr) ZigStatement {
    return .{ .expr_stmt = .{ .expr = expr } };
}

/// Helper to create a discard statement (_ = expr;)
pub fn discardStmt(expr: *const ZigExpr) ZigStatement {
    return .{ .discard_stmt = .{ .expr = expr } };
}

/// Helper to create a comment
pub fn comment(text: []const u8) ZigStatement {
    return .{ .comment = .{ .text = text } };
}

/// Helper to create raw code
pub fn raw(code: []const u8) ZigStatement {
    return .{ .raw = .{ .code = code } };
}

/// Helper to create a blank line
pub fn blank() ZigStatement {
    return .{ .blank = {} };
}

// ========== Tests ==========

test "ZigStatement basic creation" {
    const testing = std.testing;

    // Test const declaration helper
    const raw_expr = ZigExpr{ .raw = "42" };
    const stmt = constDecl("x", &raw_expr);
    try testing.expect(stmt == .const_decl);
    try testing.expectEqualStrings("x", stmt.const_decl.name);

    // Test break helper
    const brk_stmt = brk();
    try testing.expect(brk_stmt == .break_);
    try testing.expect(brk_stmt.break_.label == null);

    // Test comment helper
    const cmt = comment("test comment");
    try testing.expect(cmt == .comment);
    try testing.expectEqualStrings("test comment", cmt.comment.text);
}

test "ZigStatement type checks" {
    const testing = std.testing;

    const raw_expr = ZigExpr{ .raw = "42" };
    const const_stmt = constDecl("x", &raw_expr);
    try testing.expect(const_stmt.isDeclaration());
    try testing.expect(!const_stmt.isAssignment());
    try testing.expect(!const_stmt.isControlFlow());

    const brk_stmt = brk();
    try testing.expect(!brk_stmt.isDeclaration());
    try testing.expect(!brk_stmt.isAssignment());
    try testing.expect(brk_stmt.isControlFlow());
}
