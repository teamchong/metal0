//! CPython source: Lib/operator.py
//!
//! Provides functions corresponding to Python's intrinsic operators.
//! These are useful for functional programming and with functions like map/reduce.
//!
//! Mirrors: CPython Lib/operator.py

const std = @import("std");

// ============================================================================
// Comparison Operations
// ============================================================================

/// Less than: a < b
pub fn lt(a: anytype, b: @TypeOf(a)) bool {
    return a < b;
}

/// Less than or equal: a <= b
pub fn le(a: anytype, b: @TypeOf(a)) bool {
    return a <= b;
}

/// Equal: a == b
pub fn eq(a: anytype, b: @TypeOf(a)) bool {
    return a == b;
}

/// Not equal: a != b
pub fn ne(a: anytype, b: @TypeOf(a)) bool {
    return a != b;
}

/// Greater than or equal: a >= b
pub fn ge(a: anytype, b: @TypeOf(a)) bool {
    return a >= b;
}

/// Greater than: a > b
pub fn gt(a: anytype, b: @TypeOf(a)) bool {
    return a > b;
}

// ============================================================================
// Logical Operations
// ============================================================================

/// Logical not: not a
pub fn not_(a: anytype) bool {
    const T = @TypeOf(a);
    if (T == bool) {
        return !a;
    }
    // For numeric types, 0 is falsy
    if (@typeInfo(T) == .int or @typeInfo(T) == .float) {
        return a == 0;
    }
    // For optionals, null is falsy
    if (@typeInfo(T) == .optional) {
        return a == null;
    }
    return false;
}

/// Logical truth value
pub fn truth(a: anytype) bool {
    return !not_(a);
}

// ============================================================================
// Arithmetic Operations
// ============================================================================

/// Absolute value: abs(a)
pub fn abs(a: anytype) @TypeOf(a) {
    const T = @TypeOf(a);
    if (@typeInfo(T) == .int) {
        return if (a < 0) -a else a;
    }
    if (@typeInfo(T) == .float) {
        return @abs(a);
    }
    return a;
}

/// Addition: a + b
pub fn add(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return a + b;
}

/// Subtraction: a - b
pub fn sub(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return a - b;
}

/// Multiplication: a * b
pub fn mul(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return a * b;
}

/// True division: a / b (floating point)
pub fn truediv(a: anytype, b: @TypeOf(a)) f64 {
    const af: f64 = @floatFromInt(a);
    const bf: f64 = @floatFromInt(b);
    return af / bf;
}

/// Floor division: a // b
pub fn floordiv(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return @divFloor(a, b);
}

/// Modulo: a % b
pub fn mod(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return @mod(a, b);
}

/// Negation: -a
pub fn neg(a: anytype) @TypeOf(a) {
    return -a;
}

/// Positive: +a
pub fn pos(a: anytype) @TypeOf(a) {
    return a;
}

/// Power: a ** b
pub fn pow(base: anytype, exp: @TypeOf(base)) @TypeOf(base) {
    const T = @TypeOf(base);
    if (@typeInfo(T) == .float) {
        return std.math.pow(T, base, exp);
    }
    // Integer power
    if (exp == 0) return 1;
    if (exp == 1) return base;

    var result: T = 1;
    var b = base;
    var e = exp;

    while (e > 0) {
        if (e & 1 == 1) {
            result *= b;
        }
        b *= b;
        e >>= 1;
    }
    return result;
}

// ============================================================================
// Bitwise Operations
// ============================================================================

/// Bitwise and: a & b
pub fn and_(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return a & b;
}

/// Bitwise or: a | b
pub fn or_(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return a | b;
}

/// Bitwise xor: a ^ b
pub fn xor(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return a ^ b;
}

/// Bitwise inversion: ~a
pub fn invert(a: anytype) @TypeOf(a) {
    return ~a;
}

/// Left shift: a << b
pub fn lshift(a: anytype, b: anytype) @TypeOf(a) {
    const shift: std.math.Log2Int(@TypeOf(a)) = @intCast(b);
    return a << shift;
}

/// Right shift: a >> b
pub fn rshift(a: anytype, b: anytype) @TypeOf(a) {
    const shift: std.math.Log2Int(@TypeOf(a)) = @intCast(b);
    return a >> shift;
}

// ============================================================================
// Sequence Operations
// ============================================================================

/// Concatenation: a + b (for sequences)
pub fn concat(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    // For slices, this would need allocation
    // For now, just return a (sequences handled differently in Zig)
    _ = b;
    return a;
}

/// Check containment: b in a
pub fn contains(sequence: anytype, item: anytype) bool {
    for (sequence) |elem| {
        if (elem == item) return true;
    }
    return false;
}

/// Count occurrences
pub fn countOf(sequence: anytype, item: anytype) usize {
    var count: usize = 0;
    for (sequence) |elem| {
        if (elem == item) count += 1;
    }
    return count;
}

/// Index of first occurrence
pub fn indexOf(sequence: anytype, item: anytype) !usize {
    for (sequence, 0..) |elem, i| {
        if (elem == item) return i;
    }
    return error.ValueError;
}

/// Get item at index: a[b]
pub fn getitem(sequence: anytype, index: usize) @typeInfo(@TypeOf(sequence)).pointer.child {
    return sequence[index];
}

/// Get length: len(a)
pub fn length(sequence: anytype) usize {
    return sequence.len;
}

// ============================================================================
// Attribute/Item Access
// ============================================================================

/// Attribute getter - creates a function that gets an attribute
pub fn attrgetter(comptime field: []const u8) fn (anytype) @TypeOf(@field(@as(@TypeOf(undefined), undefined), field)) {
    return struct {
        pub fn get(obj: anytype) @TypeOf(@field(obj, field)) {
            return @field(obj, field);
        }
    }.get;
}

/// Item getter - creates a function that gets an item at index
pub fn itemgetter(comptime index: usize) fn (anytype) @typeInfo(@TypeOf(undefined)).pointer.child {
    return struct {
        pub fn get(seq: anytype) @typeInfo(@TypeOf(seq)).pointer.child {
            return seq[index];
        }
    }.get;
}

// ============================================================================
// In-place Operations (for mutable values)
// ============================================================================

/// In-place addition: a += b
pub fn iadd(a: *anytype, b: @TypeOf(a.*)) void {
    a.* += b;
}

/// In-place subtraction: a -= b
pub fn isub(a: *anytype, b: @TypeOf(a.*)) void {
    a.* -= b;
}

/// In-place multiplication: a *= b
pub fn imul(a: *anytype, b: @TypeOf(a.*)) void {
    a.* *= b;
}

/// In-place floor division: a //= b
pub fn ifloordiv(a: *anytype, b: @TypeOf(a.*)) void {
    a.* = @divFloor(a.*, b);
}

/// In-place modulo: a %= b
pub fn imod(a: *anytype, b: @TypeOf(a.*)) void {
    a.* = @mod(a.*, b);
}

/// In-place and: a &= b
pub fn iand(a: *anytype, b: @TypeOf(a.*)) void {
    a.* &= b;
}

/// In-place or: a |= b
pub fn ior(a: *anytype, b: @TypeOf(a.*)) void {
    a.* |= b;
}

/// In-place xor: a ^= b
pub fn ixor(a: *anytype, b: @TypeOf(a.*)) void {
    a.* ^= b;
}

/// In-place left shift: a <<= b
pub fn ilshift(a: *anytype, b: anytype) void {
    const shift: std.math.Log2Int(@TypeOf(a.*)) = @intCast(b);
    a.* <<= shift;
}

/// In-place right shift: a >>= b
pub fn irshift(a: *anytype, b: anytype) void {
    const shift: std.math.Log2Int(@TypeOf(a.*)) = @intCast(b);
    a.* >>= shift;
}

// ============================================================================
// Special Operations
// ============================================================================

/// Check if object is callable
pub fn is_callable(obj: anytype) bool {
    const T = @TypeOf(obj);
    const info = @typeInfo(T);
    return info == .@"fn" or info == .pointer and @typeInfo(info.pointer.child) == .@"fn";
}

/// Check if a is b (identity)
pub fn is_(a: anytype, b: @TypeOf(a)) bool {
    return &a == &b;
}

/// Check if a is not b
pub fn is_not(a: anytype, b: @TypeOf(a)) bool {
    return &a != &b;
}

// ============================================================================
// Tests
// ============================================================================

test "comparison operators" {
    try std.testing.expect(lt(@as(i32, 1), @as(i32, 2)));
    try std.testing.expect(!lt(@as(i32, 2), @as(i32, 1)));
    try std.testing.expect(le(@as(i32, 1), @as(i32, 1)));
    try std.testing.expect(eq(@as(i32, 5), @as(i32, 5)));
    try std.testing.expect(ne(@as(i32, 5), @as(i32, 6)));
    try std.testing.expect(ge(@as(i32, 5), @as(i32, 5)));
    try std.testing.expect(gt(@as(i32, 6), @as(i32, 5)));
}

test "arithmetic operators" {
    try std.testing.expectEqual(@as(i32, 5), abs(@as(i32, -5)));
    try std.testing.expectEqual(@as(i32, 5), abs(@as(i32, 5)));
    try std.testing.expectEqual(@as(i32, 7), add(@as(i32, 3), @as(i32, 4)));
    try std.testing.expectEqual(@as(i32, 2), sub(@as(i32, 5), @as(i32, 3)));
    try std.testing.expectEqual(@as(i32, 12), mul(@as(i32, 3), @as(i32, 4)));
    try std.testing.expectEqual(@as(i32, 3), floordiv(@as(i32, 10), @as(i32, 3)));
    try std.testing.expectEqual(@as(i32, 1), mod(@as(i32, 10), @as(i32, 3)));
    try std.testing.expectEqual(@as(i32, -5), neg(@as(i32, 5)));
}

test "bitwise operators" {
    try std.testing.expectEqual(@as(u8, 0b1010 & 0b1100), and_(@as(u8, 0b1010), @as(u8, 0b1100)));
    try std.testing.expectEqual(@as(u8, 0b1010 | 0b1100), or_(@as(u8, 0b1010), @as(u8, 0b1100)));
    try std.testing.expectEqual(@as(u8, 0b1010 ^ 0b1100), xor(@as(u8, 0b1010), @as(u8, 0b1100)));
    try std.testing.expectEqual(@as(u8, 0b100), lshift(@as(u8, 1), @as(u8, 2)));
    try std.testing.expectEqual(@as(u8, 0b10), rshift(@as(u8, 8), @as(u8, 2)));
}

test "sequence operators" {
    const arr = [_]i32{ 1, 2, 3, 4, 5 };
    try std.testing.expect(contains(&arr, @as(i32, 3)));
    try std.testing.expect(!contains(&arr, @as(i32, 6)));
    try std.testing.expectEqual(@as(usize, 1), countOf(&arr, @as(i32, 3)));
    try std.testing.expectEqual(@as(usize, 2), try indexOf(&arr, @as(i32, 3)));
    try std.testing.expectEqual(@as(i32, 3), getitem(&arr, 2));
    try std.testing.expectEqual(@as(usize, 5), length(&arr));
}

test "truth and not" {
    try std.testing.expect(truth(true));
    try std.testing.expect(!truth(false));
    try std.testing.expect(truth(@as(i32, 1)));
    try std.testing.expect(!truth(@as(i32, 0)));
    try std.testing.expect(not_(false));
    try std.testing.expect(!not_(true));
}

test "power" {
    try std.testing.expectEqual(@as(i32, 8), pow(@as(i32, 2), @as(i32, 3)));
    try std.testing.expectEqual(@as(i32, 1), pow(@as(i32, 5), @as(i32, 0)));
    try std.testing.expectEqual(@as(i32, 27), pow(@as(i32, 3), @as(i32, 3)));
}

test "in-place operations" {
    var x: i32 = 5;
    iadd(&x, 3);
    try std.testing.expectEqual(@as(i32, 8), x);

    isub(&x, 2);
    try std.testing.expectEqual(@as(i32, 6), x);

    imul(&x, 2);
    try std.testing.expectEqual(@as(i32, 12), x);
}
