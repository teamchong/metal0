/// intrinsics - Bytecode Intrinsic Functions
/// Mirrors cpython/Python/intrinsics.c
///
/// This module provides intrinsic functions used by Python bytecode:
/// - Unary intrinsics (print, import_star, etc.)
/// - Binary intrinsics (prep_reraise_star, typevar_with_bound, etc.)
/// - Type parameter creation helpers

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Intrinsic IDs - Unary
// ============================================================================

pub const Intrinsic1 = enum(u8) {
    invalid = 0,
    print = 1,
    import_star = 2,
    stopiteration_error = 3,
    async_gen_wrap = 4,
    unary_positive = 5,
    list_to_tuple = 6,
    typevar = 7,
    paramspec = 8,
    typevartuple = 9,
    subscript_generic = 10,
    typealias = 11,
};

pub const MAX_INTRINSIC_1: usize = 11;

// ============================================================================
// Intrinsic IDs - Binary
// ============================================================================

pub const Intrinsic2 = enum(u8) {
    invalid = 0,
    prep_reraise_star = 1,
    typevar_with_bound = 2,
    typevar_with_constraints = 3,
    set_function_type_params = 4,
    set_typeparam_default = 5,
};

pub const MAX_INTRINSIC_2: usize = 5;

// ============================================================================
// Intrinsic Names
// ============================================================================

/// Names for unary intrinsics
pub const unary_names: [MAX_INTRINSIC_1 + 1][]const u8 = .{
    "INTRINSIC_1_INVALID",
    "INTRINSIC_PRINT",
    "INTRINSIC_IMPORT_STAR",
    "INTRINSIC_STOPITERATION_ERROR",
    "INTRINSIC_ASYNC_GEN_WRAP",
    "INTRINSIC_UNARY_POSITIVE",
    "INTRINSIC_LIST_TO_TUPLE",
    "INTRINSIC_TYPEVAR",
    "INTRINSIC_PARAMSPEC",
    "INTRINSIC_TYPEVARTUPLE",
    "INTRINSIC_SUBSCRIPT_GENERIC",
    "INTRINSIC_TYPEALIAS",
};

/// Names for binary intrinsics
pub const binary_names: [MAX_INTRINSIC_2 + 1][]const u8 = .{
    "INTRINSIC_2_INVALID",
    "INTRINSIC_PREP_RERAISE_STAR",
    "INTRINSIC_TYPEVAR_WITH_BOUND",
    "INTRINSIC_TYPEVAR_WITH_CONSTRAINTS",
    "INTRINSIC_SET_FUNCTION_TYPE_PARAMS",
    "INTRINSIC_SET_TYPEPARAM_DEFAULT",
};

// ============================================================================
// Generic Value Type
// ============================================================================

/// Generic Python value for intrinsic operations
pub const PyValue = union(enum) {
    none,
    int_val: i64,
    float_val: f64,
    bool_val: bool,
    string: []const u8,
    list: []PyValue,
    tuple: []PyValue,
    object: *anyopaque,

    pub fn isNone(self: PyValue) bool {
        return self == .none;
    }
};

// ============================================================================
// Unary Intrinsic Functions
// ============================================================================

/// Invalid intrinsic placeholder
pub fn noIntrinsic1(value: PyValue) !PyValue {
    _ = value;
    return error.InvalidIntrinsic;
}

/// Print expression (used by REPL displayhook)
pub fn printExpr(value: PyValue) !PyValue {
    switch (value) {
        .none => {},
        .int_val => |v| std.debug.print("{d}\n", .{v}),
        .float_val => |v| std.debug.print("{d}\n", .{v}),
        .bool_val => |v| std.debug.print("{}\n", .{v}),
        .string => |v| std.debug.print("{s}\n", .{v}),
        else => std.debug.print("<object>\n", .{}),
    }
    return .none;
}

/// Unary positive (+x)
pub fn unaryPositive(value: PyValue) !PyValue {
    return switch (value) {
        .int_val => value,
        .float_val => value,
        else => error.TypeError,
    };
}

/// Convert list to tuple
pub fn listToTuple(allocator: Allocator, value: PyValue) !PyValue {
    switch (value) {
        .list => |items| {
            const tuple = try allocator.dupe(PyValue, items);
            return .{ .tuple = tuple };
        },
        else => return error.TypeError,
    }
}

/// Create a TypeVar
pub fn makeTypevar(name: []const u8) !PyValue {
    // Return type var as a simple string for now
    // Real implementation would create a TypeVar object
    return .{ .string = name };
}

/// Handle StopIteration in generator
/// CPython wraps StopIteration in RuntimeError for generator.throw()
/// In AOT, we pass through the exception - error handling is compile-time
pub fn stopiterationError(exc: PyValue) !PyValue {
    return exc;
}

/// Wrap value for async generator
/// CPython wraps in _PyAsyncGenValueWrapper for yield tracking
/// In AOT, async generators use native coroutine handling
pub fn asyncGenWrap(value: PyValue) !PyValue {
    return value;
}

/// Create a ParamSpec
pub fn makeParamspec(name: []const u8) !PyValue {
    return .{ .string = name };
}

/// Create a TypeVarTuple
pub fn makeTypevartuple(name: []const u8) !PyValue {
    return .{ .string = name };
}

/// Subscript a generic type
/// Creates Generic[args] - in AOT, type parameters are erased at runtime
/// The typing info is used at compile-time for type inference only
pub fn subscriptGeneric(generic: PyValue, args: PyValue) !PyValue {
    _ = generic;
    _ = args;
    return .none;
}

/// Create a TypeAlias
pub fn makeTypealias(name: []const u8) !PyValue {
    return .{ .string = name };
}

// ============================================================================
// Binary Intrinsic Functions
// ============================================================================

/// Invalid binary intrinsic placeholder
pub fn noIntrinsic2(a: PyValue, b: PyValue) !PyValue {
    _ = a;
    _ = b;
    return error.InvalidIntrinsic;
}

/// Prepare exception for reraise star (PEP 654)
/// In CPython, merges orig exception with new exceptions for except*
/// In AOT, exception groups are handled at compile-time codegen
pub fn prepReraiseStar(orig: PyValue, excs: PyValue) !PyValue {
    _ = orig;
    _ = excs;
    return .none;
}

/// Create TypeVar with bound (PEP 695)
/// AOT: Type bounds are checked at compile-time, not runtime
pub fn makeTypevarWithBound(name: []const u8, bound: PyValue) !PyValue {
    _ = bound;
    return .{ .string = name };
}

/// Create TypeVar with constraints (PEP 695)
/// AOT: Type constraints are checked at compile-time, not runtime
pub fn makeTypevarWithConstraints(name: []const u8, constraints: PyValue) !PyValue {
    _ = constraints;
    return .{ .string = name };
}

/// Set function type parameters (PEP 695)
/// AOT: __type_params__ is used by type checkers, not needed at runtime
pub fn setFunctionTypeParams(func: PyValue, type_params: PyValue) !PyValue {
    _ = type_params;
    return func;
}

/// Set type parameter default (PEP 696)
/// AOT: Default type params resolved at compile-time
pub fn setTypeparamDefault(type_param: PyValue, default: PyValue) !PyValue {
    _ = default;
    return type_param;
}

// ============================================================================
// Intrinsic Dispatch
// ============================================================================

/// Dispatch unary intrinsic by ID
pub fn callUnaryIntrinsic(allocator: Allocator, id: Intrinsic1, value: PyValue) !PyValue {
    return switch (id) {
        .invalid => noIntrinsic1(value),
        .print => printExpr(value),
        .import_star => error.NotImplemented, // Requires frame access
        .stopiteration_error => stopiterationError(value),
        .async_gen_wrap => asyncGenWrap(value),
        .unary_positive => unaryPositive(value),
        .list_to_tuple => listToTuple(allocator, value),
        .typevar => switch (value) {
            .string => |s| makeTypevar(s),
            else => error.TypeError,
        },
        .paramspec => switch (value) {
            .string => |s| makeParamspec(s),
            else => error.TypeError,
        },
        .typevartuple => switch (value) {
            .string => |s| makeTypevartuple(s),
            else => error.TypeError,
        },
        .subscript_generic => error.NotImplemented,
        .typealias => switch (value) {
            .string => |s| makeTypealias(s),
            else => error.TypeError,
        },
    };
}

/// Dispatch binary intrinsic by ID
pub fn callBinaryIntrinsic(id: Intrinsic2, a: PyValue, b: PyValue) !PyValue {
    return switch (id) {
        .invalid => noIntrinsic2(a, b),
        .prep_reraise_star => prepReraiseStar(a, b),
        .typevar_with_bound => switch (a) {
            .string => |s| makeTypevarWithBound(s, b),
            else => error.TypeError,
        },
        .typevar_with_constraints => switch (a) {
            .string => |s| makeTypevarWithConstraints(s, b),
            else => error.TypeError,
        },
        .set_function_type_params => setFunctionTypeParams(a, b),
        .set_typeparam_default => setTypeparamDefault(a, b),
    };
}

// ============================================================================
// Name Lookup
// ============================================================================

/// Get name of unary intrinsic
pub fn getUnaryIntrinsicName(index: usize) ?[]const u8 {
    if (index > MAX_INTRINSIC_1) {
        return null;
    }
    return unary_names[index];
}

/// Get name of binary intrinsic
pub fn getBinaryIntrinsicName(index: usize) ?[]const u8 {
    if (index > MAX_INTRINSIC_2) {
        return null;
    }
    return binary_names[index];
}

/// Look up unary intrinsic by name
pub fn findUnaryIntrinsic(name: []const u8) ?Intrinsic1 {
    for (unary_names, 0..) |n, i| {
        if (std.mem.eql(u8, n, name)) {
            return @enumFromInt(i);
        }
    }
    return null;
}

/// Look up binary intrinsic by name
pub fn findBinaryIntrinsic(name: []const u8) ?Intrinsic2 {
    for (binary_names, 0..) |n, i| {
        if (std.mem.eql(u8, n, name)) {
            return @enumFromInt(i);
        }
    }
    return null;
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "unary intrinsic names" {
    try std.testing.expectEqualStrings("INTRINSIC_PRINT", getUnaryIntrinsicName(1).?);
    try std.testing.expectEqualStrings("INTRINSIC_LIST_TO_TUPLE", getUnaryIntrinsicName(6).?);
    try std.testing.expect(getUnaryIntrinsicName(100) == null);
}

test "binary intrinsic names" {
    try std.testing.expectEqualStrings("INTRINSIC_PREP_RERAISE_STAR", getBinaryIntrinsicName(1).?);
    try std.testing.expect(getBinaryIntrinsicName(100) == null);
}

test "find intrinsic" {
    try std.testing.expectEqual(Intrinsic1.print, findUnaryIntrinsic("INTRINSIC_PRINT").?);
    try std.testing.expectEqual(Intrinsic2.prep_reraise_star, findBinaryIntrinsic("INTRINSIC_PREP_RERAISE_STAR").?);
}

test "unary positive" {
    const result = try unaryPositive(.{ .int_val = 42 });
    try std.testing.expectEqual(@as(i64, 42), result.int_val);
}

test "print expr" {
    // Just test it doesn't error
    _ = try printExpr(.{ .int_val = 42 });
    _ = try printExpr(.none);
}
