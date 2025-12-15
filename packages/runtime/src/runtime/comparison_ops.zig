/// Comparison operations with concrete types to reduce monomorphization
/// These functions compile ONCE per type, not per call site.
///
/// Pattern: O(n²) anytype → O(n) concrete functions + O(1) dispatch
///
/// Usage in codegen:
///   - Generate `comparison_ops.eqI64(a, b)` when both operands are known i64
///   - Generate `comparison_ops.ltPyValue(a, b)` for PyValue comparisons
///   - Fallback to `operator.eq(a, b)` for unknown types (still works, but monomorphizes)
const std = @import("std");
const PyValue = @import("../Objects/object.zig").PyValue;

// =============================================================================
// Integer Comparisons (i64) - Most common fast path
// =============================================================================

/// Equal: a == b (for i64)
pub fn eqI64(a: i64, b: i64) bool {
    return a == b;
}

/// Not equal: a != b (for i64)
pub fn neI64(a: i64, b: i64) bool {
    return a != b;
}

/// Less than: a < b (for i64)
pub fn ltI64(a: i64, b: i64) bool {
    return a < b;
}

/// Less than or equal: a <= b (for i64)
pub fn leI64(a: i64, b: i64) bool {
    return a <= b;
}

/// Greater than: a > b (for i64)
pub fn gtI64(a: i64, b: i64) bool {
    return a > b;
}

/// Greater than or equal: a >= b (for i64)
pub fn geI64(a: i64, b: i64) bool {
    return a >= b;
}

// =============================================================================
// Float Comparisons (f64) - Second most common
// =============================================================================

/// Equal: a == b (for f64, handles NaN)
pub fn eqF64(a: f64, b: f64) bool {
    // NaN != NaN in IEEE 754, but Python returns False for NaN == NaN
    return a == b;
}

/// Not equal: a != b (for f64)
pub fn neF64(a: f64, b: f64) bool {
    return a != b;
}

/// Less than: a < b (for f64)
pub fn ltF64(a: f64, b: f64) bool {
    return a < b;
}

/// Less than or equal: a <= b (for f64)
pub fn leF64(a: f64, b: f64) bool {
    return a <= b;
}

/// Greater than: a > b (for f64)
pub fn gtF64(a: f64, b: f64) bool {
    return a > b;
}

/// Greater than or equal: a >= b (for f64)
pub fn geF64(a: f64, b: f64) bool {
    return a >= b;
}

// =============================================================================
// Boolean Comparisons
// =============================================================================

/// Equal: a == b (for bool)
pub fn eqBool(a: bool, b: bool) bool {
    return a == b;
}

/// Not equal: a != b (for bool)
pub fn neBool(a: bool, b: bool) bool {
    return a != b;
}

// =============================================================================
// String Comparisons ([]const u8)
// =============================================================================

/// Equal: a == b (for strings)
pub fn eqStr(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

/// Not equal: a != b (for strings)
pub fn neStr(a: []const u8, b: []const u8) bool {
    return !std.mem.eql(u8, a, b);
}

/// Less than: a < b (for strings, lexicographic)
pub fn ltStr(a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

/// Less than or equal: a <= b (for strings)
pub fn leStr(a: []const u8, b: []const u8) bool {
    const order = std.mem.order(u8, a, b);
    return order == .lt or order == .eq;
}

/// Greater than: a > b (for strings)
pub fn gtStr(a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .gt;
}

/// Greater than or equal: a >= b (for strings)
pub fn geStr(a: []const u8, b: []const u8) bool {
    const order = std.mem.order(u8, a, b);
    return order == .gt or order == .eq;
}

// =============================================================================
// PyValue Comparisons - Universal fallback (compiles once)
// =============================================================================

/// Equal: a == b (for PyValue)
pub fn eqPyValue(a: PyValue, b: PyValue) bool {
    return a.eql(b);
}

/// Not equal: a != b (for PyValue)
pub fn nePyValue(a: PyValue, b: PyValue) bool {
    return !a.eql(b);
}

/// Less than: a < b (for PyValue)
pub fn ltPyValue(a: PyValue, b: PyValue) bool {
    return a.lt(b);
}

/// Less than or equal: a <= b (for PyValue)
pub fn lePyValue(a: PyValue, b: PyValue) bool {
    return a.le(b);
}

/// Greater than: a > b (for PyValue)
pub fn gtPyValue(a: PyValue, b: PyValue) bool {
    return a.gt(b);
}

/// Greater than or equal: a >= b (for PyValue)
pub fn gePyValue(a: PyValue, b: PyValue) bool {
    return a.ge(b);
}

// =============================================================================
// Cross-type Comparisons (int vs float) - Common in Python
// =============================================================================

/// Equal: i64 == f64 (cross-type)
pub fn eqI64F64(a: i64, b: f64) bool {
    const af: f64 = @floatFromInt(a);
    return af == b;
}

/// Equal: f64 == i64 (cross-type)
pub fn eqF64I64(a: f64, b: i64) bool {
    const bf: f64 = @floatFromInt(b);
    return a == bf;
}

/// Less than: i64 < f64 (cross-type)
pub fn ltI64F64(a: i64, b: f64) bool {
    const af: f64 = @floatFromInt(a);
    return af < b;
}

/// Less than: f64 < i64 (cross-type)
pub fn ltF64I64(a: f64, b: i64) bool {
    const bf: f64 = @floatFromInt(b);
    return a < bf;
}

/// Less than or equal: i64 <= f64 (cross-type)
pub fn leI64F64(a: i64, b: f64) bool {
    const af: f64 = @floatFromInt(a);
    return af <= b;
}

/// Less than or equal: f64 <= i64 (cross-type)
pub fn leF64I64(a: f64, b: i64) bool {
    const bf: f64 = @floatFromInt(b);
    return a <= bf;
}

/// Greater than: i64 > f64 (cross-type)
pub fn gtI64F64(a: i64, b: f64) bool {
    const af: f64 = @floatFromInt(a);
    return af > b;
}

/// Greater than: f64 > i64 (cross-type)
pub fn gtF64I64(a: f64, b: i64) bool {
    const bf: f64 = @floatFromInt(b);
    return a > bf;
}

/// Greater than or equal: i64 >= f64 (cross-type)
pub fn geI64F64(a: i64, b: f64) bool {
    const af: f64 = @floatFromInt(a);
    return af >= b;
}

/// Greater than or equal: f64 >= i64 (cross-type)
pub fn geF64I64(a: f64, b: i64) bool {
    const bf: f64 = @floatFromInt(b);
    return a >= bf;
}

// =============================================================================
// Tests
// =============================================================================

test "i64 comparisons" {
    try std.testing.expect(eqI64(42, 42));
    try std.testing.expect(!eqI64(42, 43));
    try std.testing.expect(neI64(42, 43));
    try std.testing.expect(ltI64(1, 2));
    try std.testing.expect(leI64(1, 1));
    try std.testing.expect(gtI64(2, 1));
    try std.testing.expect(geI64(1, 1));
}

test "f64 comparisons" {
    try std.testing.expect(eqF64(3.14, 3.14));
    try std.testing.expect(!eqF64(3.14, 3.15));
    try std.testing.expect(ltF64(1.0, 2.0));
    try std.testing.expect(leF64(1.0, 1.0));
}

test "string comparisons" {
    try std.testing.expect(eqStr("hello", "hello"));
    try std.testing.expect(!eqStr("hello", "world"));
    try std.testing.expect(ltStr("abc", "abd"));
    try std.testing.expect(gtStr("z", "a"));
}

test "cross-type comparisons" {
    try std.testing.expect(eqI64F64(42, 42.0));
    try std.testing.expect(!eqI64F64(42, 42.5));
    try std.testing.expect(ltI64F64(1, 1.5));
    try std.testing.expect(gtF64I64(2.5, 2));
}
