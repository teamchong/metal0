/// Safe arithmetic operations
/// Mirrors cpython/Python/pymath.c

// ============================================================================
// Safe Arithmetic
// ============================================================================

/// Checked addition
pub fn Py_SAFE_ADD(a: i64, b: i64) ?i64 {
    const result = @addWithOverflow(a, b);
    return if (result[1] != 0) null else result[0];
}

/// Checked subtraction
pub fn Py_SAFE_SUB(a: i64, b: i64) ?i64 {
    const result = @subWithOverflow(a, b);
    return if (result[1] != 0) null else result[0];
}

/// Checked multiplication
pub fn Py_SAFE_MUL(a: i64, b: i64) ?i64 {
    const result = @mulWithOverflow(a, b);
    return if (result[1] != 0) null else result[0];
}

/// Saturating addition
pub fn Py_SATURATE_ADD(a: i64, b: i64) i64 {
    return a +| b;
}

/// Saturating subtraction
pub fn Py_SATURATE_SUB(a: i64, b: i64) i64 {
    return a -| b;
}

/// Saturating multiplication
pub fn Py_SATURATE_MUL(a: i64, b: i64) i64 {
    return a *| b;
}
