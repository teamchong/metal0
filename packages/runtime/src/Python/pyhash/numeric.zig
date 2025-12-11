/// Numeric Hashing
/// Hash functions for integers, floats, and complex numbers
///
/// Ensures that numerically equal values have equal hashes:
/// - hash(42) == hash(42.0)
/// - hash(1+2j) is deterministic

const std = @import("std");
const constants = @import("constants.zig");

const HashT = constants.HashT;
const UHashT = constants.UHashT;
const HASH_BITS = constants.HASH_BITS;
const HASH_MODULUS = constants.HASH_MODULUS;
const HASH_INF = constants.HASH_INF;
const HASH_NAN = constants.HASH_NAN;
const HASH_IMAG = constants.HASH_IMAG;
const HASH_INVALID = constants.HASH_INVALID;

// ============================================================================
// Integer Hashing
// ============================================================================

/// Hash an integer
/// For small integers, the hash is the integer itself
/// For large integers, we reduce modulo HASH_MODULUS
pub fn hashLong(v: i64) HashT {
    if (v == HASH_INVALID) {
        return -2;
    }

    // For values that fit in hash range, return as-is
    if (v >= 0 and v < @as(i64, @intCast(HASH_MODULUS))) {
        return v;
    }

    // Reduce modulo HASH_MODULUS
    var result: HashT = undefined;
    if (v >= 0) {
        result = @intCast(@as(u64, @intCast(v)) % HASH_MODULUS);
    } else {
        // For negative, compute -(|v| mod P)
        const abs_v: u64 = @intCast(-v);
        result = -@as(HashT, @intCast(abs_v % HASH_MODULUS));
    }

    if (result == HASH_INVALID) {
        result = -2;
    }

    return result;
}

// ============================================================================
// Float Hashing
// ============================================================================

/// Hash a double-precision float
/// Mirrors: _Py_HashDouble
pub fn hashDouble(v: f64) HashT {
    // Handle special cases
    if (!std.math.isFinite(v)) {
        if (std.math.isInf(v)) {
            return if (v > 0) HASH_INF else -HASH_INF;
        } else {
            // NaN - return a consistent value
            return HASH_NAN;
        }
    }

    // Handle zero
    if (v == 0.0) {
        return 0;
    }

    // Extract mantissa and exponent
    var e: i32 = undefined;
    var m = std.math.frexp(v);
    const frac = m.significand;
    e = m.exponent;

    const sign: HashT = if (frac < 0) -1 else 1;
    const abs_frac = @abs(frac);

    // Process 28 bits at a time
    var x: UHashT = 0;
    var remaining = abs_frac;

    while (remaining != 0) {
        x = ((x << 28) & HASH_MODULUS) | (x >> (HASH_BITS - 28));
        remaining *= 268435456.0; // 2^28
        e -= 28;
        const y: UHashT = @intFromFloat(remaining);
        remaining -= @floatFromInt(y);
        x += y;
        if (x >= HASH_MODULUS) {
            x -= HASH_MODULUS;
        }
    }

    // Adjust for exponent
    const exp_mod: u6 = @intCast(@mod(@as(i64, e), HASH_BITS));
    x = ((x << exp_mod) & HASH_MODULUS) | (x >> (HASH_BITS - exp_mod));

    var result: HashT = @intCast(x);
    result *= sign;

    if (result == HASH_INVALID) {
        result = -2;
    }

    return result;
}

// ============================================================================
// Complex Hashing
// ============================================================================

/// Hash a complex number
pub fn hashComplex(real: f64, imag: f64) HashT {
    var hash_real = hashDouble(real);
    var hash_imag = hashDouble(imag);

    // Combine using the formula: hash_real + HASH_IMAG * hash_imag
    const combined = hash_real +% @mulWithOverflow(HASH_IMAG, hash_imag)[0];

    var result: HashT = @intCast(@as(u64, @bitCast(combined)) % HASH_MODULUS);
    if (result == HASH_INVALID) {
        result = -2;
    }

    return result;
}

// ============================================================================
// Tests
// ============================================================================

test "hash long" {
    try std.testing.expectEqual(@as(HashT, 0), hashLong(0));
    try std.testing.expectEqual(@as(HashT, 42), hashLong(42));
    try std.testing.expectEqual(@as(HashT, -2), hashLong(-1)); // -1 maps to -2
}

test "hash double" {
    try std.testing.expectEqual(@as(HashT, 0), hashDouble(0.0));
    try std.testing.expectEqual(HASH_INF, hashDouble(std.math.inf(f64)));
    try std.testing.expectEqual(-HASH_INF, hashDouble(-std.math.inf(f64)));

    // Same value should produce same hash
    const h1 = hashDouble(3.14159);
    const h2 = hashDouble(3.14159);
    try std.testing.expectEqual(h1, h2);
}
