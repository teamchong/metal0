/// ZigExpr - Structured expression representation for Zig codegen
///
/// This abstraction separates expression semantics from string emission, enabling:
/// - Type-safe expression construction (compile-time validation)
/// - Unified comparison path (all comparisons flow through single dispatch)
/// - Expression-level transformations before emission
/// - Type confidence tracking throughout expression trees
///
/// Key design principle: Expressions are constructed as structured data,
/// then emitted to strings only at the final output stage. All comparisons
/// use the same code path regardless of how they were constructed.
///
/// Integration with existing systems:
/// - ZigValue: Used for leaf values (literals, names, locals)
/// - ZigType: Used for type annotations in casts/conversions
/// - ZigStatement: Uses ZigExpr for expression positions
/// - TypeConfidence: Determines native vs runtime dispatch
///
const std = @import("std");
const zig_value = @import("zig_value.zig");
const zig_type = @import("zig_type.zig");

pub const ZigValue = zig_value.ZigValue;
pub const ZigType = zig_type.ZigType;
pub const TypeConfidence = zig_value.TypeConfidence;
pub const CertainType = zig_value.CertainType;
pub const TypeHint = zig_value.TypeHint;
pub const CompOp = zig_value.CompOp;
pub const BinOp = zig_value.BinOp;

/// ZigExpr - Union of all possible Zig expression types
pub const ZigExpr = union(enum) {
    // ========== Leaf Values ==========

    /// Wraps a ZigValue (literals, names, locals, params)
    value: ZigValue,

    /// Variable reference by name
    name: []const u8,

    /// Raw Zig expression (escape hatch for complex patterns)
    raw: []const u8,

    // ========== Binary Operations ==========

    /// Binary operation: left op right
    /// ALL comparisons flow through this for unified dispatch
    binary: Binary,

    // ========== Unary Operations ==========

    /// Unary operation: op expr
    unary: Unary,

    // ========== Access Operations ==========

    /// Field access: obj.field
    field: Field,

    /// Subscript access: container[index]
    subscript: Subscript,

    /// Slice access: container[start..end]
    slice: Slice,

    // ========== Calls ==========

    /// Function call: func(args)
    call: Call,

    /// Method call: obj.method(args)
    method_call: MethodCall,

    /// Builtin call: @builtin(args)
    builtin_call: BuiltinCall,

    // ========== Compound Expressions ==========

    /// Struct literal: .{ .field = value, ... }
    struct_literal: StructLiteral,

    /// Array literal: .{ elem1, elem2, ... }
    array_literal: ArrayLiteral,

    /// Ternary expression: if (cond) then_expr else else_expr
    ternary: Ternary,

    /// Labeled block expression: label: { ... break :label value; }
    labeled_block: LabeledBlock,

    // ========== Error Handling ==========

    /// Try expression: try expr
    try_: Try,

    /// Catch expression: expr catch |err| handler
    catch_: Catch,

    /// Orelse expression: expr orelse default
    orelse_: Orelse,

    // ========== Pointer/Address Operations ==========

    /// Address of: &expr
    address_of: AddressOf,

    /// Dereference: expr.*
    deref: Deref,

    // ========== Type Operations ==========

    /// Type cast: @as(T, expr) or @intCast(expr)
    cast: Cast,

    /// Type coercion: expr (with implicit type)
    coerce: Coerce,

    // ========== Methods ==========

    /// Get the type confidence of this expression
    pub fn confidence(self: ZigExpr) TypeConfidence {
        return switch (self) {
            .value => |v| v.confidence(),
            .name => .certain, // Named bindings tracked separately
            .raw => .certain, // Raw expressions are user-controlled
            .binary => |b| b.result_confidence,
            .unary => |u| u.result_confidence,
            .field => |f| f.result_confidence,
            .subscript => |s| s.result_confidence,
            .slice => .certain, // Slices are always certain type
            .call => |c| c.result_confidence,
            .method_call => |m| m.result_confidence,
            .builtin_call => .certain, // Builtins have known types
            .struct_literal => .certain,
            .array_literal => .certain,
            .ternary => |t| t.result_confidence,
            .labeled_block => |lb| lb.result_confidence,
            .try_ => |t| t.result_confidence,
            .catch_ => |c| c.result_confidence,
            .orelse_ => |o| o.result_confidence,
            .address_of => .certain,
            .deref => |d| d.result_confidence,
            .cast => .certain, // Casts have explicit types
            .coerce => |c| c.result_confidence,
        };
    }

    /// Check if this expression needs PyValue wrapping
    pub fn needsPyValue(self: ZigExpr) bool {
        return self.confidence().needsPyValue();
    }

    /// Check if this expression is a compile-time constant
    pub fn isComptime(self: ZigExpr) bool {
        return switch (self) {
            .value => |v| v.isComptime(),
            .name => false,
            .raw => false,
            .binary => |b| b.left.isComptime() and b.right.isComptime(),
            .unary => |u| u.operand.isComptime(),
            else => false,
        };
    }

    /// Get the certain type category for type-based dispatch
    pub fn certainType(self: ZigExpr) CertainType {
        return switch (self) {
            .value => |v| v.certainType(),
            .binary => |b| b.result_type,
            .unary => |u| u.result_type,
            else => .other,
        };
    }

    /// Check if this is a simple name reference
    pub fn isName(self: ZigExpr) bool {
        return self == .name or (self == .value and self.value == .named);
    }

    /// Get name if this is a name reference
    pub fn getName(self: ZigExpr) ?[]const u8 {
        return switch (self) {
            .name => |n| n,
            .value => |v| if (v == .named) v.named else null,
            else => null,
        };
    }

    // ========== Constructors ==========

    /// Create from a ZigValue
    pub fn fromValue(v: ZigValue) ZigExpr {
        return .{ .value = v };
    }

    /// Create a name reference
    pub fn fromName(n: []const u8) ZigExpr {
        return .{ .name = n };
    }

    /// Create an integer literal
    pub fn int(v: i64) ZigExpr {
        return .{ .value = ZigValue.int(v) };
    }

    /// Create a float literal
    pub fn float(v: f64) ZigExpr {
        return .{ .value = ZigValue.float(v) };
    }

    /// Create a string literal
    pub fn string(v: []const u8) ZigExpr {
        return .{ .value = ZigValue.string(v) };
    }

    /// Create a boolean literal
    pub fn boolean(v: bool) ZigExpr {
        return .{ .value = ZigValue.boolean(v) };
    }

    /// Create a null literal
    pub fn null_() ZigExpr {
        return .{ .value = ZigValue.null_() };
    }

    /// Create a raw expression (escape hatch)
    pub fn rawExpr(code: []const u8) ZigExpr {
        return .{ .raw = code };
    }
};

// ========== Binary Operation ==========

/// Binary operator categories for dispatch
pub const BinaryOpKind = enum {
    /// Arithmetic: +, -, *, /, //, %, **
    arithmetic,
    /// Bitwise: &, |, ^, <<, >>
    bitwise,
    /// Comparison: ==, !=, <, <=, >, >= (UNIFIED PATH)
    comparison,
    /// Logical: and, or
    logical,
    /// Membership: in, not in
    membership,
    /// Identity: is, is not
    identity,

    pub fn fromBinOp(op: BinOp) BinaryOpKind {
        return switch (op) {
            .add, .sub, .mul, .div, .floor_div, .mod, .pow => .arithmetic,
            .bit_and, .bit_or, .bit_xor, .lshift, .rshift => .bitwise,
            .eq, .ne, .lt, .le, .gt, .ge => .comparison,
            .@"and", .@"or" => .logical,
            .in, .not_in => .membership,
            .is, .is_not => .identity,
        };
    }
};

/// Result type determines runtime vs native dispatch
pub const ResultType = enum {
    /// Use native Zig operators (same type, certain confidence)
    native,
    /// Use runtime helpers (cross-type or uncertain)
    runtime,
};

/// Binary operation expression
pub const Binary = struct {
    /// Operator
    op: BinOp,
    /// Left operand
    left: *const ZigExpr,
    /// Right operand
    right: *const ZigExpr,
    /// Result confidence (from type inference)
    result_confidence: TypeConfidence = .certain,
    /// Result type category (for certainType())
    result_type: CertainType = .other,
    /// Dispatch path (native Zig or runtime helper)
    dispatch: ResultType = .native,

    /// Get the operator kind for dispatch
    pub fn opKind(self: Binary) BinaryOpKind {
        return BinaryOpKind.fromBinOp(self.op);
    }

    /// Check if this is a comparison operation
    pub fn isComparison(self: Binary) bool {
        return self.opKind() == .comparison;
    }

    /// Check if this should use runtime dispatch
    pub fn useRuntime(self: Binary) bool {
        return self.dispatch == .runtime;
    }

    /// Get the Zig operator string for native dispatch
    pub fn toOperator(self: Binary) ?[]const u8 {
        return switch (self.op) {
            .add => "+",
            .sub => "-",
            .mul => "*",
            .div => "/",
            .mod => "%",
            .bit_and => "&",
            .bit_or => "|",
            .bit_xor => "^",
            .lshift => "<<",
            .rshift => ">>",
            .eq => "==",
            .ne => "!=",
            .lt => "<",
            .le => "<=",
            .gt => ">",
            .ge => ">=",
            .@"and" => "and",
            .@"or" => "or",
            // These don't have direct Zig operators
            .floor_div, .pow, .in, .not_in, .is, .is_not => null,
        };
    }
};

// ========== Unary Operation ==========

/// Unary operators
pub const UnaryOp = enum {
    /// Negation: -x
    neg,
    /// Logical not: !x (Zig) / not x (Python)
    not_,
    /// Bitwise not: ~x
    bit_not,
    /// Positive (no-op for most types): +x
    pos,

    pub fn toOperator(self: UnaryOp) []const u8 {
        return switch (self) {
            .neg => "-",
            .not_ => "!",
            .bit_not => "~",
            .pos => "+",
        };
    }
};

/// Unary operation expression
pub const Unary = struct {
    /// Operator
    op: UnaryOp,
    /// Operand
    operand: *const ZigExpr,
    /// Result confidence
    result_confidence: TypeConfidence = .certain,
    /// Result type category
    result_type: CertainType = .other,
};

// ========== Access Operations ==========

/// Field access expression: obj.field
pub const Field = struct {
    /// Object being accessed
    obj: *const ZigExpr,
    /// Field name
    field: []const u8,
    /// Result confidence
    result_confidence: TypeConfidence = .certain,
};

/// Subscript access expression: container[index]
pub const Subscript = struct {
    /// Container being indexed
    container: *const ZigExpr,
    /// Index expression
    index: *const ZigExpr,
    /// Result confidence
    result_confidence: TypeConfidence = .uncertain, // Dict/list subscript usually uncertain
};

/// Slice access expression: container[start..end]
pub const Slice = struct {
    /// Container being sliced
    container: *const ZigExpr,
    /// Start index (null = from beginning)
    start: ?*const ZigExpr = null,
    /// End index (null = to end)
    end: ?*const ZigExpr = null,
    /// Sentinel value (for sentinel-terminated slices)
    sentinel: ?*const ZigExpr = null,
};

// ========== Call Operations ==========

/// Function call expression
pub const Call = struct {
    /// Function to call (name or expression)
    func: *const ZigExpr,
    /// Positional arguments
    args: []const *const ZigExpr = &.{},
    /// Result confidence
    result_confidence: TypeConfidence = .uncertain, // Most calls are uncertain
};

/// Method call expression: obj.method(args)
pub const MethodCall = struct {
    /// Receiver object
    receiver: *const ZigExpr,
    /// Method name
    method: []const u8,
    /// Positional arguments
    args: []const *const ZigExpr = &.{},
    /// Result confidence
    result_confidence: TypeConfidence = .uncertain,
};

/// Builtin call expression: @builtin(args)
pub const BuiltinCall = struct {
    /// Builtin name (without @)
    builtin: []const u8,
    /// Arguments
    args: []const *const ZigExpr = &.{},
    /// Type argument (for @as, @intCast, etc.)
    type_arg: ?*const ZigType = null,
};

// ========== Compound Expressions ==========

/// Struct literal expression
pub const StructLiteral = struct {
    /// Type name (null for anonymous)
    type_name: ?[]const u8 = null,
    /// Field initializers
    fields: []const FieldInit = &.{},

    pub const FieldInit = struct {
        name: []const u8,
        value: *const ZigExpr,
    };
};

/// Array literal expression
pub const ArrayLiteral = struct {
    /// Elements
    elements: []const *const ZigExpr = &.{},
    /// Element type (null for inferred)
    element_type: ?*const ZigType = null,
};

/// Ternary expression: if (cond) then_expr else else_expr
pub const Ternary = struct {
    /// Condition
    condition: *const ZigExpr,
    /// Then branch expression
    then_expr: *const ZigExpr,
    /// Else branch expression
    else_expr: *const ZigExpr,
    /// Result confidence
    result_confidence: TypeConfidence = .certain,
};

/// Labeled block expression
pub const LabeledBlock = struct {
    /// Label name
    label: []const u8,
    /// Block body (statements, not expressions)
    /// Note: Uses ZigStatement from zig_statement.zig
    body: []const u8, // TODO: Change to []const ZigStatement when integrated
    /// Break value expression
    break_value: ?*const ZigExpr = null,
    /// Result confidence
    result_confidence: TypeConfidence = .certain,
};

// ========== Error Handling ==========

/// Try expression: try expr
pub const Try = struct {
    /// Expression to try
    expr: *const ZigExpr,
    /// Result confidence
    result_confidence: TypeConfidence = .certain,
};

/// Catch expression: expr catch |err| handler
pub const Catch = struct {
    /// Expression that may error
    expr: *const ZigExpr,
    /// Error capture name (optional)
    capture: ?[]const u8 = null,
    /// Handler expression
    handler: *const ZigExpr,
    /// Result confidence
    result_confidence: TypeConfidence = .certain,
};

/// Orelse expression: expr orelse default
pub const Orelse = struct {
    /// Optional expression
    expr: *const ZigExpr,
    /// Default value if null
    default: *const ZigExpr,
    /// Result confidence
    result_confidence: TypeConfidence = .certain,
};

// ========== Pointer Operations ==========

/// Address-of expression: &expr
pub const AddressOf = struct {
    /// Expression to take address of
    expr: *const ZigExpr,
};

/// Dereference expression: expr.*
pub const Deref = struct {
    /// Pointer expression to dereference
    expr: *const ZigExpr,
    /// Result confidence
    result_confidence: TypeConfidence = .certain,
};

// ========== Type Operations ==========

/// Cast expression: @as(T, expr) or @intCast(expr)
pub const Cast = struct {
    /// Cast kind
    kind: CastKind,
    /// Target type
    target_type: *const ZigType,
    /// Expression to cast
    expr: *const ZigExpr,

    pub const CastKind = enum {
        /// @as(T, x)
        as,
        /// @intCast(x)
        int_cast,
        /// @floatCast(x)
        float_cast,
        /// @intFromFloat(x)
        int_from_float,
        /// @floatFromInt(x)
        float_from_int,
        /// @ptrCast(x)
        ptr_cast,
        /// @alignCast(x)
        align_cast,
        /// @truncate(x)
        truncate,
        /// @bitCast(x)
        bit_cast,
    };
};

/// Type coercion expression (implicit type)
pub const Coerce = struct {
    /// Expression being coerced
    expr: *const ZigExpr,
    /// Target type
    target_type: *const ZigType,
    /// Result confidence
    result_confidence: TypeConfidence = .certain,
};

// ========== Builder Helpers ==========

/// Create a binary expression
pub fn binary(op: BinOp, left: *const ZigExpr, right: *const ZigExpr) ZigExpr {
    return .{ .binary = .{ .op = op, .left = left, .right = right } };
}

/// Create a comparison expression with dispatch info
pub fn comparison(op: BinOp, left: *const ZigExpr, right: *const ZigExpr, dispatch: ResultType) ZigExpr {
    return .{ .binary = .{
        .op = op,
        .left = left,
        .right = right,
        .dispatch = dispatch,
        .result_type = .bool_,
        .result_confidence = .certain,
    } };
}

/// Create a unary expression
pub fn unary(op: UnaryOp, operand: *const ZigExpr) ZigExpr {
    return .{ .unary = .{ .op = op, .operand = operand } };
}

/// Create a field access expression
pub fn field(obj: *const ZigExpr, field_name: []const u8) ZigExpr {
    return .{ .field = .{ .obj = obj, .field = field_name } };
}

/// Create a subscript expression
pub fn subscript(container: *const ZigExpr, index: *const ZigExpr) ZigExpr {
    return .{ .subscript = .{ .container = container, .index = index } };
}

/// Create a function call expression
pub fn call(func: *const ZigExpr, args: []const *const ZigExpr) ZigExpr {
    return .{ .call = .{ .func = func, .args = args } };
}

/// Create a method call expression
pub fn methodCall(receiver: *const ZigExpr, method: []const u8, args: []const *const ZigExpr) ZigExpr {
    return .{ .method_call = .{ .receiver = receiver, .method = method, .args = args } };
}

/// Create a try expression
pub fn try_(expr: *const ZigExpr) ZigExpr {
    return .{ .try_ = .{ .expr = expr } };
}

/// Create an orelse expression
pub fn orelse_(expr: *const ZigExpr, default: *const ZigExpr) ZigExpr {
    return .{ .orelse_ = .{ .expr = expr, .default = default } };
}

/// Create an address-of expression
pub fn addressOf(expr: *const ZigExpr) ZigExpr {
    return .{ .address_of = .{ .expr = expr } };
}

/// Create a ternary expression
pub fn ternary(cond: *const ZigExpr, then_expr: *const ZigExpr, else_expr: *const ZigExpr) ZigExpr {
    return .{ .ternary = .{
        .condition = cond,
        .then_expr = then_expr,
        .else_expr = else_expr,
    } };
}

// ========== Tests ==========

test "ZigExpr basic creation" {
    const testing = std.testing;

    // Test integer literal
    const int_expr = ZigExpr.int(42);
    try testing.expect(int_expr == .value);
    try testing.expectEqual(TypeConfidence.certain, int_expr.confidence());
    try testing.expect(int_expr.isComptime());

    // Test name reference
    const name_expr = ZigExpr.fromName("x");
    try testing.expect(name_expr == .name);
    try testing.expectEqualStrings("x", name_expr.name);
    try testing.expect(name_expr.isName());
    try testing.expectEqualStrings("x", name_expr.getName().?);

    // Test raw expression
    const raw_expr = ZigExpr.rawExpr("@intCast(y)");
    try testing.expect(raw_expr == .raw);
    try testing.expectEqualStrings("@intCast(y)", raw_expr.raw);
}

test "ZigExpr binary operations" {
    const testing = std.testing;

    const left = ZigExpr.int(1);
    const right = ZigExpr.int(2);

    // Test binary creation
    const bin = binary(.add, &left, &right);
    try testing.expect(bin == .binary);
    try testing.expectEqual(BinOp.add, bin.binary.op);
    try testing.expect(!bin.binary.isComparison());
    try testing.expectEqualStrings("+", bin.binary.toOperator().?);

    // Test comparison
    const cmp = comparison(.eq, &left, &right, .native);
    try testing.expect(cmp == .binary);
    try testing.expect(cmp.binary.isComparison());
    try testing.expect(!cmp.binary.useRuntime());
    try testing.expectEqualStrings("==", cmp.binary.toOperator().?);
}

test "ZigExpr unary operations" {
    const testing = std.testing;

    const operand = ZigExpr.int(42);
    const neg = unary(.neg, &operand);

    try testing.expect(neg == .unary);
    try testing.expectEqual(UnaryOp.neg, neg.unary.op);
    try testing.expectEqualStrings("-", neg.unary.op.toOperator());
}

test "ZigExpr field access" {
    const testing = std.testing;

    const obj = ZigExpr.fromName("self");
    const access = field(&obj, "value");

    try testing.expect(access == .field);
    try testing.expectEqualStrings("value", access.field.field);
}

test "ZigExpr subscript" {
    const testing = std.testing;

    const container = ZigExpr.fromName("arr");
    const index = ZigExpr.int(0);
    const sub = subscript(&container, &index);

    try testing.expect(sub == .subscript);
    try testing.expectEqual(TypeConfidence.uncertain, sub.confidence());
}

test "ZigExpr confidence propagation" {
    const testing = std.testing;

    // Certain values
    const certain_int = ZigExpr.int(42);
    try testing.expectEqual(TypeConfidence.certain, certain_int.confidence());

    // Uncertain subscript
    const container = ZigExpr.fromName("dict");
    const key = ZigExpr.string("key");
    const sub = subscript(&container, &key);
    try testing.expectEqual(TypeConfidence.uncertain, sub.confidence());
}

test "BinaryOpKind categorization" {
    const testing = std.testing;

    try testing.expectEqual(BinaryOpKind.arithmetic, BinaryOpKind.fromBinOp(.add));
    try testing.expectEqual(BinaryOpKind.arithmetic, BinaryOpKind.fromBinOp(.mul));
    try testing.expectEqual(BinaryOpKind.comparison, BinaryOpKind.fromBinOp(.eq));
    try testing.expectEqual(BinaryOpKind.comparison, BinaryOpKind.fromBinOp(.lt));
    try testing.expectEqual(BinaryOpKind.logical, BinaryOpKind.fromBinOp(.@"and"));
    try testing.expectEqual(BinaryOpKind.membership, BinaryOpKind.fromBinOp(.in));
    try testing.expectEqual(BinaryOpKind.identity, BinaryOpKind.fromBinOp(.is));
    try testing.expectEqual(BinaryOpKind.bitwise, BinaryOpKind.fromBinOp(.bit_and));
}
