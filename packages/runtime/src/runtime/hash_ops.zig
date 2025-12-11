/// Python hash() operations
/// Implements CPython-compatible hash algorithms for various types
/// Extracted from runtime.zig to reduce file size
const std = @import("std");
const bigint = @import("bigint");
const BigInt = bigint.BigInt;

/// Python hash() builtin - returns integer hash of object
/// For integers: returns the integer itself (Python behavior)
/// For strings: uses wyhash for fast hashing
/// For bools: 1 for True, 0 for False
pub fn pyHash(value: anytype) i64 {
    const T = @TypeOf(value);
    const type_info = @typeInfo(T);

    // Integer types: hash is the value itself (Python behavior)
    // Note: Python maps -1 to -2 because -1 is reserved as error indicator in C API
    if (type_info == .int or type_info == .comptime_int) {
        const result: i64 = @intCast(value);
        return if (result == -1) -2 else result;
    }

    // Bool: 1 for true, 0 for false
    if (type_info == .bool) {
        return if (value) 1 else 0;
    }

    // Pointer types - check if it's a string slice
    if (type_info == .pointer) {
        const child = type_info.pointer.child;
        // Check for []const u8 (string slice)
        if (child == u8) {
            return @as(i64, @bitCast(std.hash.Wyhash.hash(0, value)));
        }
        // Check for slice of u8
        if (@typeInfo(child) == .array) {
            const array_child = @typeInfo(child).array.child;
            if (array_child == u8) {
                return @as(i64, @bitCast(std.hash.Wyhash.hash(0, value)));
            }
        }
    }

    // Float: use Python's float hash algorithm
    if (type_info == .float or type_info == .comptime_float) {
        return floatHashInternal(@as(f64, value));
    }

    // Union (e.g., IntResult from toIntBig): extract and hash the contained value
    if (type_info == .@"union") {
        // Check if it's IntResult (has small: i64 and big: BigInt fields)
        if (@hasField(T, "small") and @hasField(T, "big")) {
            return switch (value) {
                .small => |v| if (v == -1) -2 else v,
                .big => |b| b.hash(),
            };
        }
    }

    // Struct (tuple): use Python's tuple hash algorithm
    if (type_info == .@"struct") {
        return tupleHashInternal(value);
    }

    // Default: return 0 for unhashable types
    return 0;
}

/// Python-compatible pow function
/// Handles special cases like (-1)**1e100 = 1.0 (large even exponent)
/// and 1**anything = 1.0
pub fn pyPow(base: f64, exp: f64) f64 {
    // Special case: 1**anything = 1.0
    if (base == 1.0) {
        return 1.0;
    }

    // Special case: anything**0 = 1.0
    if (exp == 0.0) {
        return 1.0;
    }

    // Special case: (-1)**large_integer
    // If exp is a very large number that would become infinity,
    // but the mathematical result should be 1 or -1
    if (base == -1.0) {
        // Check if exponent is an integer (or effectively an integer)
        // For very large exponents, we need to determine if even or odd
        // If |exp| >= 2^53, all floats are integers and even (due to representation)
        if (@abs(exp) >= 9007199254740992.0) {
            // Very large exponent - all such floats are even integers
            return 1.0;
        }
        // For smaller exponents, check if it's an integer
        if (exp == @trunc(exp)) {
            // It's an integer - check odd/even
            const exp_int: i64 = @intFromFloat(exp);
            return if (@mod(exp_int, 2) == 0) 1.0 else -1.0;
        }
    }

    // Default: use standard pow
    return std.math.pow(f64, base, exp);
}

/// Python-compatible float hash (from Objects/object.c _Py_HashDouble)
/// Uses the same algorithm as CPython to ensure hash(0.5) == hash(Fraction(1,2))
fn floatHashInternal(v: f64) i64 {
    // Special cases
    if (std.math.isNan(v)) {
        return 0;
    }
    if (std.math.isInf(v)) {
        return if (v > 0) 314159 else -314159;
    }
    if (v == 0.0) {
        return 0;
    }

    // Python's _PyHASH_MODULUS = (1 << 61) - 1 on 64-bit systems
    const P: u128 = 2305843009213693951;

    // Get the sign and absolute value
    const sign: i64 = if (v < 0) -1 else 1;
    const abs_v = @abs(v);

    // frexp: v = m * 2^e where 0.5 <= |m| < 1
    const frexp_result = std.math.frexp(abs_v);
    var m: f64 = frexp_result.significand;
    var e: i32 = frexp_result.exponent;

    // Reduce the fraction: multiply mantissa by 2 until it's >= 1
    // to get the integer numerator, tracking the power of 2 divisor
    while (m != @trunc(m) and m < 9007199254740992.0) { // 2^53
        m *= 2.0;
        e -= 1;
    }

    // m is now effectively the numerator, 2^(-e) is the denominator (if e < 0)
    // or 2^e is a multiplier (if e >= 0)
    var x: u128 = @intFromFloat(m);

    // Apply the exponent
    if (e >= 0) {
        // Multiply by 2^e mod P
        while (e > 0) : (e -= 1) {
            x = (x * 2) % P;
        }
    } else {
        // Divide by 2^|e| mod P = multiply by modular inverse of 2^|e|
        // inv(2) mod P = (P+1)/2 for Mersenne prime P = 2^61 - 1
        const INV_2: u128 = 1152921504606846976;
        while (e < 0) : (e += 1) {
            x = (x * INV_2) % P;
        }
    }

    var result: i64 = @intCast(x);
    result *= sign;
    if (result == -1) {
        result = -2;
    }
    return result;
}

/// Python-compatible tuple hash using xxHash algorithm (CPython 3.8+)
fn tupleHashInternal(tup: anytype) i64 {
    const T = @TypeOf(tup);
    const info = @typeInfo(T);
    if (info != .@"struct") return 0;

    const fields = info.@"struct".fields;
    const num_fields = fields.len;

    // Python's xxHash constants
    const XXPRIME_1: u64 = 11400714785074694791;
    const XXPRIME_2: u64 = 14029467366897019727;
    const XXPRIME_5: u64 = 2870177450012600261;

    var acc: u64 = XXPRIME_5;

    // Hash each element
    inline for (fields) |field| {
        const elem = @field(tup, field.name);
        const elem_hash: u64 = @bitCast(pyHash(elem));
        acc +%= elem_hash *% XXPRIME_2;
        acc = (acc << 31) | (acc >> 33); // rotate left 31
        acc *%= XXPRIME_1;
    }

    // Final mix
    acc +%= @as(u64, num_fields) ^ (XXPRIME_5 ^ 3527539);

    if (acc == @as(u64, @bitCast(@as(i64, -1)))) {
        return 1546275796;
    }

    return @bitCast(acc);
}
