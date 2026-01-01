/// Basic float arithmetic operations
const std = @import("std");
const bigint = @import("bigint");
const BigInt = bigint.BigInt;
const type_predicates = @import("../type_predicates.zig");

/// Python error types
pub const PythonError = error{
    ZeroDivisionError,
    IndexError,
    ValueError,
    TypeError,
    KeyError,
    OverflowError,
    OutOfMemory,
    Exception,
};

/// Python floored modulo for floats: a % b = a - floor(a/b) * b
/// Result has the same sign as the divisor (b)
pub inline fn pyFloatMod(a: anytype, b: anytype) f64 {
    const af: f64 = numToFloat(a);
    const bf: f64 = numToFloat(b);
    const quotient = @floor(af / bf);
    const result = af - quotient * bf;
    if (result == 0.0) {
        return if (bf < 0.0) -@as(f64, 0.0) else @as(f64, 0.0);
    }
    return result;
}

/// Convert any numeric type to f64 (simple version for mixed arithmetic)
pub inline fn numToFloat(value: anytype) f64 {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    if (type_predicates.isFloatInfo(info)) {
        return @floatCast(value);
    } else if (type_predicates.isIntInfo(info)) {
        return @floatFromInt(value);
    } else if (T == BigInt) {
        return value.toFloat();
    } else {
        @compileError("numToFloat: unsupported type " ++ @typeName(T));
    }
}

/// Subtract two numbers, handling mixed int/float types (returns f64)
pub inline fn subtractNum(a: anytype, b: anytype) f64 {
    return numToFloat(a) - numToFloat(b);
}

/// Add two numbers, handling mixed int/float types
/// If both are integers, returns i64. Otherwise returns f64.
pub inline fn addNum(a: anytype, b: anytype) AddResultType(@TypeOf(a), @TypeOf(b)) {
    const A = @TypeOf(a);
    const B = @TypeOf(b);
    const a_info = @typeInfo(A);
    const b_info = @typeInfo(B);

    if ((type_predicates.isIntInfo(a_info)) and (type_predicates.isIntInfo(b_info))) {
        const a_i64: i64 = if (a_info == .comptime_int) a else @intCast(a);
        const b_i64: i64 = if (b_info == .comptime_int) b else @intCast(b);
        return a_i64 + b_i64;
    }
    return numToFloat(a) + numToFloat(b);
}

/// Computes result type for addNum: i64 if both int, f64 otherwise
fn AddResultType(comptime A: type, comptime B: type) type {
    const a_info = @typeInfo(A);
    const b_info = @typeInfo(B);
    if ((type_predicates.isIntInfo(a_info)) and (type_predicates.isIntInfo(b_info))) {
        return i64;
    }
    return f64;
}

/// Multiply two numbers, handling mixed int/float types (returns f64)
pub inline fn mulNum(a: anytype, b: anytype) f64 {
    return numToFloat(a) * numToFloat(b);
}

/// Float division with zero check
pub fn divideFloat(a: anytype, b: anytype) PythonError!f64 {
    const a_float = numToFloat(a);
    const b_float = numToFloat(b);

    if (b_float == 0.0) {
        return PythonError.ZeroDivisionError;
    }
    return a_float / b_float;
}
