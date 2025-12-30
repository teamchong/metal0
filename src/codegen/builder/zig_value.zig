/// ZigValue - Type-safe value representation for structured Zig codegen
///
/// This abstraction separates storage location from semantic meaning, enabling:
/// - Type-safe operations (compile-time checks on value compatibility)
/// - Automatic PyValue wrapping for uncertain types (Two-Flow TypeSystem integration)
/// - Compile-time constant folding for certain values
/// - Local variable reuse by type (performance optimization)
///
/// Key design principle: Values know their type confidence (certain/uncertain)
/// which determines whether they use raw Zig types or PyValue wrappers.
///
/// Integration with existing systems:
/// - NameGen: Names generated internally, not passed as strings
/// - TypeInferrer: Confidence comes from type inference analysis
/// - NativeType: Maps to ZigType for code emission
///
const std = @import("std");

/// Index into the local variable pool
pub const LocalIndex = u32;

/// Index into the parameter list
pub const ParamIndex = u32;

/// Type confidence from Two-Flow TypeSystem
/// Determines whether values use raw Zig types or PyValue wrappers
pub const TypeConfidence = enum {
    /// Type is known with certainty (literals, annotated, known builtins)
    /// Use raw Zig types: i64, f64, []const u8
    certain,

    /// Type may vary at runtime (user functions without annotations, dict subscript)
    /// Use runtime.PyValue wrapper for safety
    uncertain,

    /// Check if this confidence level requires PyValue wrapping
    pub fn needsPyValue(self: TypeConfidence) bool {
        return self == .uncertain;
    }
};

/// Type category for certain values - used for type-based comparison routing
/// Helps emitComparison dispatch to optimized paths for same-type comparisons
pub const CertainType = enum {
    /// Integer type (i64, comptime_int)
    int,
    /// Floating-point type (f64, comptime_float)
    float,
    /// Boolean type
    bool_,
    /// String type ([]const u8)
    string,
    /// Bytes type (Python b"...")
    bytes,
    /// Null/None type
    null_,
    /// Other/unknown type (use runtime comparison)
    other,
};

/// Comparison operators (Python semantics)
/// Used by ZigBuilder.emitComparison for structured comparison generation
pub const CompOp = enum {
    /// Equality (==)
    eq,
    /// Inequality (!=)
    ne,
    /// Less than (<)
    lt,
    /// Less than or equal (<=)
    le,
    /// Greater than (>)
    gt,
    /// Greater than or equal (>=)
    ge,
    /// Membership test (in)
    in_,
    /// Negative membership test (not in)
    not_in,
    /// Identity test (is)
    is,
    /// Negative identity test (is not)
    is_not,

    /// Convert to string representation for emitting operators
    pub fn toOperator(self: CompOp) []const u8 {
        return switch (self) {
            .eq => "==",
            .ne => "!=",
            .lt => "<",
            .le => "<=",
            .gt => ">",
            .ge => ">=",
            .in_, .not_in, .is, .is_not => unreachable, // Not direct operators
        };
    }

    /// Check if this is an ordering comparison (uses < <= > >=)
    pub fn isOrdering(self: CompOp) bool {
        return switch (self) {
            .lt, .le, .gt, .ge => true,
            else => false,
        };
    }

    /// Check if this is an equality comparison (uses == !=)
    pub fn isEquality(self: CompOp) bool {
        return self == .eq or self == .ne;
    }

    /// Check if this is a containment test (in, not in)
    pub fn isContainment(self: CompOp) bool {
        return self == .in_ or self == .not_in;
    }

    /// Check if this is an identity test (is, is not)
    pub fn isIdentity(self: CompOp) bool {
        return self == .is or self == .is_not;
    }
};

/// Represents a value that can be emitted as Zig code
/// Separates the concept of "what the value is" from "how to emit it"
pub const ZigValue = union(enum) {
    // ============================================
    // Storage locations (where the value lives)
    // ============================================

    /// No value (void, uninitialized)
    none: void,

    /// Local variable by index (t0, t1, ...)
    /// Created by LocalAllocator for temporaries
    local: LocalIndex,

    /// Address of a local variable (&t0)
    local_ref: LocalIndex,

    /// Named binding from Python source (original variable name)
    /// May be escaped if it's a Zig keyword
    named: []const u8,

    /// Function parameter by index
    param: ParamIndex,

    // ============================================
    // Certain values (known at codegen time)
    // ============================================

    /// Compile-time known integer (fits in i64)
    certain_int: i64,

    /// Compile-time known float
    certain_float: f64,

    /// Compile-time known boolean
    certain_bool: bool,

    /// String literal (escaped for Zig)
    certain_str: []const u8,

    /// Bytes literal (Python b"..." - wrapped in bytesLiteral())
    certain_bytes: []const u8,

    /// Null/None value
    certain_null: void,

    // ============================================
    // Uncertain values (runtime polymorphic)
    // ============================================

    /// Runtime PyValue (type uncertain, needs wrapper)
    /// The attached TypeHint helps with optimization when available
    uncertain_pyvalue: TypeHint,

    // ============================================
    // Compound/special values
    // ============================================

    /// BigInt for arbitrary precision integers
    bigint: BigIntValue,

    /// UnifiedInt (i64 or BigInt, auto-promotes)
    unified_int: UnifiedIntValue,

    /// Array/slice literal
    array: ArrayValue,

    /// Python list (ArrayList)
    list: ListValue,

    /// Python tuple
    tuple: TupleValue,

    /// Python dict
    dict: DictValue,

    /// Python set
    set: SetValue,

    /// Struct literal
    struct_literal: StructLiteralValue,

    /// Method call result (receiver.method(args))
    method_result: MethodResultValue,

    /// Binary operation result (deferred evaluation)
    binop_result: BinOpResultValue,

    /// Unary operation result (deferred evaluation)
    unaryop_result: UnaryOpResultValue,

    /// Raw Zig expression (escape hatch for complex cases)
    /// Use sparingly - prefer structured values
    raw_expr: []const u8,

    /// Typed raw expression (captured complex expression with confidence tracking)
    /// Used for calls/attributes/subscripts that need complex dispatch but tracked confidence
    typed_raw: TypedRawValue,

    /// Field access (obj.field)
    field_access: FieldAccessValue,

    /// Index/subscript access (obj[index])
    subscript: SubscriptValue,

    /// Function call result (func(args))
    call_result: CallResultValue,

    /// Ternary/conditional expression (if-else)
    ternary: TernaryValue,

    /// Boolean operation (and/or)
    boolop: BoolOpValue,

    /// Type cast expression (@as(T, @builtin(inner)))
    cast: CastValue,

    // ============================================
    // Type information
    // ============================================

    /// Get the confidence level of this value
    pub fn confidence(self: ZigValue) TypeConfidence {
        return switch (self) {
            .certain_int, .certain_float, .certain_bool, .certain_str, .certain_bytes, .certain_null => .certain,
            .uncertain_pyvalue => .uncertain,
            // Locals and named bindings depend on their declared type
            .local, .local_ref, .named, .param => .certain, // Assume certain unless wrapped
            // Compound values inherit from their construction
            .bigint, .unified_int => .certain,
            .array, .struct_literal => .certain,
            // Container types are certain (element types are known)
            .list, .tuple, .dict, .set => .certain,
            .method_result => |m| m.confidence,
            .binop_result => |b| b.confidence,
            .unaryop_result => |u| u.confidence,
            .field_access => |f| f.confidence,
            .subscript => |s| s.confidence,
            .call_result => |c| c.confidence,
            .ternary => |t| t.confidence,
            .boolop => |bo| bo.confidence,
            .cast => .certain, // Casts produce certain types
            .raw_expr => .certain, // Raw expressions are user-controlled
            .typed_raw => |t| t.confidence,
            .none => .certain,
        };
    }

    /// Check if this value needs PyValue wrapping
    pub fn needsPyValue(self: ZigValue) bool {
        return self.confidence().needsPyValue();
    }

    /// Check if this value is a compile-time constant
    pub fn isComptime(self: ZigValue) bool {
        return switch (self) {
            .certain_int, .certain_float, .certain_bool, .certain_str, .certain_bytes, .certain_null => true,
            else => false,
        };
    }

    /// Check if this value represents no value (void)
    pub fn isVoid(self: ZigValue) bool {
        return self == .none;
    }

    /// Get the certain type category for type-based dispatch
    /// Used by comparison operations to route to optimized paths
    pub fn certainType(self: ZigValue) CertainType {
        return switch (self) {
            .certain_int => .int,
            .certain_float => .float,
            .certain_bool => .bool_,
            .certain_str => .string,
            .certain_bytes => .bytes,
            .certain_null => .null_,
            .bigint, .unified_int => .int,
            // typed_raw with type_hint - use the hint
            .typed_raw => |t| if (t.type_hint) |hint| hint else .other,
            // binop_result - infer from operand types
            .binop_result => |b| blk: {
                const lhs_ty = b.lhs.certainType();
                const rhs_ty = b.rhs.certainType();
                // Numeric result: int + int = int, int + float = float, float + float = float
                if ((lhs_ty == .int or lhs_ty == .float) and (rhs_ty == .int or rhs_ty == .float)) {
                    // Float promotion
                    if (lhs_ty == .float or rhs_ty == .float) {
                        break :blk .float;
                    }
                    break :blk .int;
                }
                break :blk .other;
            },
            // unaryop_result - preserve operand type for neg/pos, bool for not
            .unaryop_result => |u| blk: {
                switch (u.op) {
                    .neg, .pos => break :blk u.operand.certainType(),
                    .not_ => break :blk .bool_,
                    .bit_not => break :blk .int, // Bitwise not always produces int
                }
            },
            else => .other,
        };
    }

    /// Check if this value is numeric (int or float)
    pub fn isNumeric(self: ZigValue) bool {
        const ty = self.certainType();
        return ty == .int or ty == .float;
    }

    /// Create a certain integer value
    pub fn int(value: i64) ZigValue {
        return .{ .certain_int = value };
    }

    /// Create a certain float value
    pub fn float(value: f64) ZigValue {
        return .{ .certain_float = value };
    }

    /// Create a certain boolean value
    pub fn boolean(value: bool) ZigValue {
        return .{ .certain_bool = value };
    }

    /// Create a certain string value
    pub fn string(value: []const u8) ZigValue {
        return .{ .certain_str = value };
    }

    /// Create a certain bytes value (Python b"...")
    pub fn bytes(value: []const u8) ZigValue {
        return .{ .certain_bytes = value };
    }

    /// Create a null/None value
    pub fn null_() ZigValue {
        return .{ .certain_null = {} };
    }

    /// Create a named binding
    pub fn fromName(name: []const u8) ZigValue {
        return .{ .named = name };
    }

    /// Create a local variable reference
    pub fn fromLocal(idx: LocalIndex) ZigValue {
        return .{ .local = idx };
    }

    /// Create a parameter reference
    pub fn fromParam(idx: ParamIndex) ZigValue {
        return .{ .param = idx };
    }

    /// Create an uncertain PyValue
    pub fn pyvalue(hint: TypeHint) ZigValue {
        return .{ .uncertain_pyvalue = hint };
    }

    /// Create a raw expression (escape hatch)
    pub fn raw(expr: []const u8) ZigValue {
        return .{ .raw_expr = expr };
    }

    /// Create void/none value
    pub fn void_() ZigValue {
        return .{ .none = {} };
    }

    // ============================================
    // Type detection for builder dispatch
    // ============================================

    /// Check if this value is a BigInt
    pub fn isBigInt(self: ZigValue) bool {
        return self == .bigint;
    }

    /// Check if this value is a UnifiedInt
    pub fn isUnifiedInt(self: ZigValue) bool {
        return self == .unified_int;
    }

    /// Check if this value is a complex number (tracked via raw expression pattern)
    pub fn isComplex(self: ZigValue) bool {
        // Complex values come through raw_expr with PyComplex pattern
        return switch (self) {
            .raw_expr => |r| std.mem.indexOf(u8, r, "PyComplex") != null,
            .typed_raw => |t| t.type_hint != null and t.type_hint.? == .other, // Complex maps to other
            else => false,
        };
    }

    /// Check if this value is a list
    pub fn isList(self: ZigValue) bool {
        return self == .list;
    }

    /// Check if this value is a tuple
    pub fn isTuple(self: ZigValue) bool {
        return self == .tuple;
    }

    /// Check if this value is a string (certain or uncertain)
    pub fn isString(self: ZigValue) bool {
        return switch (self) {
            .certain_str => true,
            .typed_raw => |t| t.type_hint != null and t.type_hint.? == .string,
            else => false,
        };
    }

    /// Check if this value needs BigInt or UnifiedInt operations
    pub fn needsBigIntOps(self: ZigValue) bool {
        return self.isBigInt() or self.isUnifiedInt();
    }

    /// Get type hint from typed_raw, if available
    pub fn typeHint(self: ZigValue) ?CertainType {
        return switch (self) {
            .typed_raw => |t| t.type_hint,
            else => null,
        };
    }

    // ============================================
    // Auto-close wrapper constructors (for callbacks)
    // ============================================

    /// Wrap value in @as(T, inner)
    /// Example: wrapAs("i64", x) => @as(i64, x)
    pub fn wrapAs(comptime target_type: []const u8, inner: ZigValue) ZigValue {
        _ = inner;
        // Return a cast wrapper that will be emitted as @as(T, inner)
        return .{ .cast = .{
            .target_type = target_type,
            .builtin = null,
            .inner = null, // Will use the inner value during emission
        } };
    }

    /// Wrap value in @as(T, @builtin(inner))
    /// Example: wrapCast("i64", "@intCast", x) => @as(i64, @intCast(x))
    pub fn wrapCast(comptime target_type: []const u8, comptime builtin: []const u8, inner: ZigValue) ZigValue {
        _ = inner;
        return .{ .cast = .{
            .target_type = target_type,
            .builtin = builtin,
            .inner = null,
        } };
    }
};

/// Type hint for uncertain values (helps with optimization)
pub const TypeHint = enum {
    /// No type information available
    unknown,
    /// Likely integer
    int_like,
    /// Likely float
    float_like,
    /// Likely string
    str_like,
    /// Likely list/array
    list_like,
    /// Likely dict/map
    dict_like,
    /// Likely boolean
    bool_like,
    /// Likely None
    none_like,
    /// Likely callable
    callable,
    /// Class instance
    class_instance,
};

/// BigInt value with source information
pub const BigIntValue = struct {
    /// Source expression to create BigInt from
    source: union(enum) {
        /// From integer literal
        literal: i128,
        /// From string parsing
        string: []const u8,
        /// From another value
        from_value: *const ZigValue,
    },
};

/// UnifiedInt value (i64 or BigInt)
pub const UnifiedIntValue = struct {
    /// Source value
    source: union(enum) {
        /// Known to fit in i64
        small: i64,
        /// Needs BigInt
        big: BigIntValue,
        /// From runtime value (unknown size)
        runtime: *const ZigValue,
    },
};

/// Array literal value
pub const ArrayValue = struct {
    /// Element values
    elements: []const ZigValue,
    /// Element type (if known)
    element_type: ?[]const u8,
};

/// Python list value (ArrayList)
pub const ListValue = struct {
    /// Element values
    elements: []const ZigValue,
    /// Element type (e.g., "i64", "runtime.PyValue")
    element_type: []const u8,
    /// Whether to use array optimization (constant homogeneous elements)
    use_array: bool = false,
};

/// Python tuple value (fixed-size, heterogeneous)
pub const TupleValue = struct {
    /// Element values
    elements: []const ZigValue,
};

/// Python dict value
pub const DictValue = struct {
    /// Key-value pairs
    pairs: []const DictPair,
    /// Key type (e.g., "[]const u8")
    key_type: []const u8,
    /// Value type (e.g., "i64", "runtime.PyValue")
    value_type: []const u8,

    pub const DictPair = struct {
        key: ZigValue,
        value: ZigValue,
    };
};

/// Python set value
pub const SetValue = struct {
    /// Element values
    elements: []const ZigValue,
    /// Element type
    element_type: []const u8,
};

/// Struct literal value
pub const StructLiteralValue = struct {
    /// Struct type name
    type_name: []const u8,
    /// Field name -> value pairs
    fields: []const FieldInit,

    pub const FieldInit = struct {
        name: []const u8,
        value: ZigValue,
    };
};

/// Method call result (deferred until emission)
pub const MethodResultValue = struct {
    /// Receiver object
    receiver: *const ZigValue,
    /// Method name
    method: []const u8,
    /// Arguments
    args: []const ZigValue,
    /// Result confidence
    confidence: TypeConfidence,
};

/// Binary operation result (deferred until emission)
pub const BinOpResultValue = struct {
    /// Operator
    op: BinOp,
    /// Left operand
    lhs: *const ZigValue,
    /// Right operand
    rhs: *const ZigValue,
    /// Result confidence
    confidence: TypeConfidence,
};

/// Binary operators
pub const BinOp = enum {
    // Arithmetic
    add,
    sub,
    mul,
    div, // true division (/)
    floor_div, // floor division (//)
    mod, // modulo (%)
    pow, // power (**)

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

    // Logical (short-circuit)
    @"and",
    @"or",

    // Membership
    in,
    not_in,

    // Identity
    is,
    is_not,
};

/// Field access value
pub const FieldAccessValue = struct {
    /// Object being accessed
    obj: *const ZigValue,
    /// Field name
    field: []const u8,
    /// Access confidence
    confidence: TypeConfidence,
};

/// Subscript/index access value
pub const SubscriptValue = struct {
    /// Container being indexed
    container: *const ZigValue,
    /// Index value
    index: *const ZigValue,
    /// Access confidence
    confidence: TypeConfidence,
};

/// Function call result value
pub const CallResultValue = struct {
    /// Function being called (name or expression)
    func: *const ZigValue,
    /// Arguments
    args: []const ZigValue,
    /// Result confidence (from return type inference)
    confidence: TypeConfidence,
    /// Optional return type hint (for optimization)
    return_type_hint: ?CertainType = null,
};

/// Typed raw expression value
/// Used for complex expressions (calls, attributes, subscripts) that need
/// the existing dispatch logic but still track type confidence
pub const TypedRawValue = struct {
    /// The captured raw Zig expression
    raw: []const u8,
    /// Result confidence (from type inference)
    confidence: TypeConfidence,
    /// Optional type hint for optimization
    type_hint: ?CertainType = null,
};

/// Ternary/conditional expression (if-else expression)
/// Python: value if condition else other_value
/// Zig: if (condition) value else other_value
pub const TernaryValue = struct {
    /// Condition expression
    condition: *const ZigValue,
    /// True branch value
    then_value: *const ZigValue,
    /// False branch value (else)
    else_value: *const ZigValue,
    /// Result confidence (combined from both branches)
    confidence: TypeConfidence,
};

/// Boolean operation value (and/or)
/// Python: a and b, a or b
pub const BoolOpValue = struct {
    /// Operator (and/or)
    op: BoolOpKind,
    /// Operand values
    values: []const ZigValue,
    /// Result confidence
    confidence: TypeConfidence,

    pub const BoolOpKind = enum {
        and_,
        or_,
    };
};

/// Import UnaryOp from zig_expr to avoid duplication
pub const UnaryOp = @import("zig_expr.zig").UnaryOp;

/// Unary operation result value
pub const UnaryOpResultValue = struct {
    /// Operator
    op: UnaryOp,
    /// Operand
    operand: *const ZigValue,
    /// Result confidence
    confidence: TypeConfidence,
};

/// Type cast value: @as(target_type, @builtin(inner)) or @as(target_type, inner)
pub const CastValue = struct {
    /// Target type (e.g., "i64", "usize")
    target_type: []const u8,
    /// Optional builtin to apply before cast (e.g., "@intCast", "@floatFromInt")
    builtin: ?[]const u8,
    /// Inner value (null means use placeholder - will be filled during emission)
    inner: ?*const ZigValue,
};

// ============================================
// Tests
// ============================================

test "ZigValue.int" {
    const v = ZigValue.int(42);
    try std.testing.expect(v == .certain_int);
    try std.testing.expectEqual(@as(i64, 42), v.certain_int);
    try std.testing.expectEqual(TypeConfidence.certain, v.confidence());
    try std.testing.expect(!v.needsPyValue());
    try std.testing.expect(v.isComptime());
}

test "ZigValue.float" {
    const v = ZigValue.float(3.14);
    try std.testing.expect(v == .certain_float);
    try std.testing.expectEqual(@as(f64, 3.14), v.certain_float);
    try std.testing.expectEqual(TypeConfidence.certain, v.confidence());
}

test "ZigValue.string" {
    const v = ZigValue.string("hello");
    try std.testing.expect(v == .certain_str);
    try std.testing.expectEqualStrings("hello", v.certain_str);
}

test "ZigValue.boolean" {
    const v = ZigValue.boolean(true);
    try std.testing.expect(v == .certain_bool);
    try std.testing.expect(v.certain_bool);
}

test "ZigValue.pyvalue" {
    const v = ZigValue.pyvalue(.unknown);
    try std.testing.expect(v == .uncertain_pyvalue);
    try std.testing.expectEqual(TypeConfidence.uncertain, v.confidence());
    try std.testing.expect(v.needsPyValue());
    try std.testing.expect(!v.isComptime());
}

test "ZigValue.fromName" {
    const v = ZigValue.fromName("my_var");
    try std.testing.expect(v == .named);
    try std.testing.expectEqualStrings("my_var", v.named);
}

test "ZigValue.fromLocal" {
    const v = ZigValue.fromLocal(5);
    try std.testing.expect(v == .local);
    try std.testing.expectEqual(@as(LocalIndex, 5), v.local);
}

test "ZigValue.void" {
    const v = ZigValue.void_();
    try std.testing.expect(v.isVoid());
    try std.testing.expect(v == .none);
}

test "ZigValue.raw" {
    const v = ZigValue.raw("@intCast(x)");
    try std.testing.expect(v == .raw_expr);
    try std.testing.expectEqualStrings("@intCast(x)", v.raw_expr);
}

test "ZigValue.certainType" {
    try std.testing.expectEqual(CertainType.int, ZigValue.int(42).certainType());
    try std.testing.expectEqual(CertainType.float, ZigValue.float(3.14).certainType());
    try std.testing.expectEqual(CertainType.bool_, ZigValue.boolean(true).certainType());
    try std.testing.expectEqual(CertainType.string, ZigValue.string("hello").certainType());
    try std.testing.expectEqual(CertainType.null_, ZigValue.null_().certainType());
    try std.testing.expectEqual(CertainType.other, ZigValue.fromName("x").certainType());
    try std.testing.expectEqual(CertainType.other, ZigValue.pyvalue(.unknown).certainType());
}

test "ZigValue.isNumeric" {
    try std.testing.expect(ZigValue.int(42).isNumeric());
    try std.testing.expect(ZigValue.float(3.14).isNumeric());
    try std.testing.expect(!ZigValue.string("hi").isNumeric());
    try std.testing.expect(!ZigValue.boolean(true).isNumeric());
    try std.testing.expect(!ZigValue.null_().isNumeric());
}

test "CompOp.toOperator" {
    try std.testing.expectEqualStrings("==", CompOp.eq.toOperator());
    try std.testing.expectEqualStrings("!=", CompOp.ne.toOperator());
    try std.testing.expectEqualStrings("<", CompOp.lt.toOperator());
    try std.testing.expectEqualStrings("<=", CompOp.le.toOperator());
    try std.testing.expectEqualStrings(">", CompOp.gt.toOperator());
    try std.testing.expectEqualStrings(">=", CompOp.ge.toOperator());
}

test "CompOp.categories" {
    // Ordering
    try std.testing.expect(CompOp.lt.isOrdering());
    try std.testing.expect(CompOp.le.isOrdering());
    try std.testing.expect(CompOp.gt.isOrdering());
    try std.testing.expect(CompOp.ge.isOrdering());
    try std.testing.expect(!CompOp.eq.isOrdering());

    // Equality
    try std.testing.expect(CompOp.eq.isEquality());
    try std.testing.expect(CompOp.ne.isEquality());
    try std.testing.expect(!CompOp.lt.isEquality());

    // Containment
    try std.testing.expect(CompOp.in_.isContainment());
    try std.testing.expect(CompOp.not_in.isContainment());
    try std.testing.expect(!CompOp.eq.isContainment());

    // Identity
    try std.testing.expect(CompOp.is.isIdentity());
    try std.testing.expect(CompOp.is_not.isIdentity());
    try std.testing.expect(!CompOp.eq.isIdentity());
}
