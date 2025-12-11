/// Integer operations (bit operations, etc.)
/// Mirrors cpython/Python/pymath.c

// ============================================================================
// Integer Operations
// ============================================================================

/// Count leading zeros in 32-bit integer
pub fn Py_CLZ32(x: u32) u32 {
    if (x == 0) return 32;
    return @clz(x);
}

/// Count leading zeros in 64-bit integer
pub fn Py_CLZ64(x: u64) u64 {
    if (x == 0) return 64;
    return @clz(x);
}

/// Count trailing zeros in 32-bit integer
pub fn Py_CTZ32(x: u32) u32 {
    if (x == 0) return 32;
    return @ctz(x);
}

/// Count trailing zeros in 64-bit integer
pub fn Py_CTZ64(x: u64) u64 {
    if (x == 0) return 64;
    return @ctz(x);
}

/// Population count (number of 1 bits)
pub fn Py_POPCOUNT32(x: u32) u32 {
    return @popCount(x);
}

/// Population count (number of 1 bits)
pub fn Py_POPCOUNT64(x: u64) u64 {
    return @popCount(x);
}

/// Bit length (position of highest set bit)
pub fn Py_BIT_LENGTH32(x: u32) u32 {
    if (x == 0) return 0;
    return 32 - @clz(x);
}

/// Bit length (position of highest set bit)
pub fn Py_BIT_LENGTH64(x: u64) u64 {
    if (x == 0) return 0;
    return 64 - @clz(x);
}
