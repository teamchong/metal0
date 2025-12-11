/// Utility functions (GCD, LCM, ISQRT, etc.)
/// Mirrors cpython/Python/pymath.c

// ============================================================================
// Utilities
// ============================================================================

/// Greatest common divisor
pub fn Py_GCD(a: u64, b: u64) u64 {
    if (b == 0) return a;
    return Py_GCD(b, a % b);
}

/// Least common multiple
pub fn Py_LCM(a: u64, b: u64) u64 {
    if (a == 0 or b == 0) return 0;
    return (a / Py_GCD(a, b)) * b;
}

/// Integer square root
pub fn Py_ISQRT(n: u64) u64 {
    if (n < 2) return n;

    var x = n;
    var y = (x + 1) / 2;

    while (y < x) {
        x = y;
        y = (x + n / x) / 2;
    }

    return x;
}

/// Check if integer is power of 2
pub fn Py_IS_POWER_OF_TWO(n: u64) bool {
    return n != 0 and (n & (n - 1)) == 0;
}

/// Round up to next power of 2
pub fn Py_NEXT_POWER_OF_TWO(n: u64) u64 {
    if (n == 0) return 1;
    if (Py_IS_POWER_OF_TWO(n)) return n;
    return @as(u64, 1) << @intCast(64 - @clz(n));
}
