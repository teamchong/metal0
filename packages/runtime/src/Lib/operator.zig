//! CPython source: Lib/operator.py
//!
//! Provides functions corresponding to Python's intrinsic operators.
//! These are useful for functional programming and with functions like map/reduce.
//!
//! Mirrors: CPython Lib/operator.py
//!
//! NOTE: Comparison operations dispatch to comparison_ops.zig for common types
//! to reduce monomorphization. Use runtime.comparison_ops.eqI64 etc. directly
//! in generated code for known concrete types.

const std = @import("std");
const comparison = @import("../runtime/comparison.zig");
const PyValue = @import("../Objects/object.zig").PyValue;

// ============================================================================
// Comparison Operations
// THE ONE SOURCE OF TRUTH: All comparisons go through runtime/comparison.zig
// ============================================================================

/// Less than: a < b
pub fn lt(a: anytype, b: @TypeOf(a)) bool {
    return comparison.lessThan(a, b);
}

/// Less than or equal: a <= b
pub fn le(a: anytype, b: @TypeOf(a)) bool {
    return comparison.lessThanOrEqual(a, b);
}

/// Equal: a == b
pub fn eq(a: anytype, b: @TypeOf(a)) bool {
    return comparison.equal(a, b);
}

/// Not equal: a != b
pub fn ne(a: anytype, b: @TypeOf(a)) bool {
    return comparison.notEqual(a, b);
}

/// Greater than or equal: a >= b
pub fn ge(a: anytype, b: @TypeOf(a)) bool {
    return comparison.greaterThanOrEqual(a, b);
}

/// Greater than: a > b
pub fn gt(a: anytype, b: @TypeOf(a)) bool {
    return comparison.greaterThan(a, b);
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
/// Returns error for invalid operations like 0**-1 (ZeroDivisionError)
pub fn pow(base: anytype, exp: @TypeOf(base)) !@TypeOf(base) {
    const T = @TypeOf(base);
    const op_ops = @import("../runtime/operator_ops.zig");

    // Dispatch to error-checking implementations
    if (T == i64) return op_ops.powI64(base, exp);
    if (T == f64) return op_ops.powF64(base, exp);

    // Fallback for other numeric types
    if (@typeInfo(T) == .float) {
        return @floatCast(try op_ops.powF64(@floatCast(base), @floatCast(exp)));
    }
    // Integer fallback
    const base_f: f64 = @floatFromInt(base);
    const exp_f: f64 = @floatFromInt(exp);
    const result = try op_ops.powF64(base_f, exp_f);
    return @intFromFloat(result);
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
/// Returns a new slice containing elements from both a and b
/// Caller must free the returned slice using the provided allocator
pub fn concat(allocator: std.mem.Allocator, a: anytype, b: @TypeOf(a)) !@TypeOf(a) {
    const T = @TypeOf(a);
    const info = @typeInfo(T);

    if (info == .pointer and info.pointer.size == .Slice) {
        // Slice concatenation - allocate new slice with combined length
        const ElemType = info.pointer.child;
        const result = try allocator.alloc(ElemType, a.len + b.len);
        @memcpy(result[0..a.len], a);
        @memcpy(result[a.len..], b);
        return result;
    } else {
        // For non-slices, just return a (no allocation possible)
        return a;
    }
}

/// Concatenation without allocation (in-place for ArrayList)
pub fn concatInPlace(list: anytype, items: anytype) !void {
    try list.appendSlice(items);
}

/// Check containment: b in a
/// Dispatches to concrete functions for common types to reduce monomorphization
pub fn contains(sequence: anytype, item: anytype) bool {
    const SeqT = @TypeOf(sequence);
    const ItemT = @TypeOf(item);

    // Fast path: both are PyValue slices
    if (SeqT == []const PyValue and ItemT == PyValue) {
        return containsPyValue(sequence, item);
    }

    // Fast path: string slice containment
    if (SeqT == []const u8 and ItemT == []const u8) {
        return std.mem.indexOf(u8, sequence, item) != null;
    }

    // Standard iteration for same types
    for (sequence) |elem| {
        if (@TypeOf(elem) == ItemT) {
            if (elem == item) return true;
        }
    }
    return false;
}

/// PyValue containment - compiles ONCE
fn containsPyValue(sequence: []const PyValue, item: PyValue) bool {
    const equality = @import("../runtime/equality.zig");
    for (sequence) |elem| {
        if (equality.pyValueEql(elem, item)) return true;
    }
    return false;
}

/// Count occurrences
/// Dispatches to concrete functions for common types to reduce monomorphization
pub fn countOf(sequence: anytype, item: anytype) usize {
    const SeqT = @TypeOf(sequence);
    const ItemT = @TypeOf(item);

    // Fast path: both are PyValue slices
    if (SeqT == []const PyValue and ItemT == PyValue) {
        return countOfPyValue(sequence, item);
    }

    // Standard iteration for same types
    var count: usize = 0;
    for (sequence) |elem| {
        if (@TypeOf(elem) == ItemT) {
            if (elem == item) count += 1;
        }
    }
    return count;
}

/// PyValue count - compiles ONCE
fn countOfPyValue(sequence: []const PyValue, item: PyValue) usize {
    const equality = @import("../runtime/equality.zig");
    var count: usize = 0;
    for (sequence) |elem| {
        if (equality.pyValueEql(elem, item)) count += 1;
    }
    return count;
}

/// Index of first occurrence
/// Dispatches to concrete functions for common types to reduce monomorphization
pub fn indexOf(sequence: anytype, item: anytype) !usize {
    const SeqT = @TypeOf(sequence);
    const ItemT = @TypeOf(item);

    // Fast path: both are PyValue slices
    if (SeqT == []const PyValue and ItemT == PyValue) {
        return indexOfPyValue(sequence, item);
    }

    // Standard iteration for same types
    for (sequence, 0..) |elem, i| {
        if (@TypeOf(elem) == ItemT) {
            if (elem == item) return i;
        }
    }
    return error.ValueError;
}

/// PyValue indexOf - compiles ONCE
fn indexOfPyValue(sequence: []const PyValue, item: PyValue) !usize {
    const equality = @import("../runtime/equality.zig");
    for (sequence, 0..) |elem, i| {
        if (equality.pyValueEql(elem, item)) return i;
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
pub fn iadd(comptime T: type, a: *T, b: T) void {
    a.* += b;
}

/// In-place subtraction: a -= b
pub fn isub(comptime T: type, a: *T, b: T) void {
    a.* -= b;
}

/// In-place multiplication: a *= b
pub fn imul(comptime T: type, a: *T, b: T) void {
    a.* *= b;
}

/// In-place floor division: a //= b
pub fn ifloordiv(comptime T: type, a: *T, b: T) void {
    a.* = @divFloor(a.*, b);
}

/// In-place modulo: a %= b
pub fn imod(comptime T: type, a: *T, b: T) void {
    a.* = @mod(a.*, b);
}

/// In-place and: a &= b
pub fn iand(comptime T: type, a: *T, b: T) void {
    a.* &= b;
}

/// In-place or: a |= b
pub fn ior(comptime T: type, a: *T, b: T) void {
    a.* |= b;
}

/// In-place xor: a ^= b
pub fn ixor(comptime T: type, a: *T, b: T) void {
    a.* ^= b;
}

/// In-place left shift: a <<= b
pub fn ilshift(comptime T: type, comptime S: type, a: *T, b: S) void {
    const shift: std.math.Log2Int(T) = @intCast(b);
    a.* <<= shift;
}

/// In-place right shift: a >>= b
pub fn irshift(comptime T: type, comptime S: type, a: *T, b: S) void {
    const shift: std.math.Log2Int(T) = @intCast(b);
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
