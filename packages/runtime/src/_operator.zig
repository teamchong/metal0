/// _operator - C accelerator module for operator
/// Provides efficient implementations of standard operators as functions
const std = @import("std");

// ============================================================================
// Comparison Operations
// ============================================================================

/// eq(a, b) -- Same as a == b
pub fn eq(comptime T: type) fn (T, T) bool {
    return struct {
        fn f(a: T, b: T) bool {
            return a == b;
        }
    }.f;
}

/// ne(a, b) -- Same as a != b
pub fn ne(comptime T: type) fn (T, T) bool {
    return struct {
        fn f(a: T, b: T) bool {
            return a != b;
        }
    }.f;
}

/// lt(a, b) -- Same as a < b
pub fn lt(comptime T: type) fn (T, T) bool {
    return struct {
        fn f(a: T, b: T) bool {
            return a < b;
        }
    }.f;
}

/// le(a, b) -- Same as a <= b
pub fn le(comptime T: type) fn (T, T) bool {
    return struct {
        fn f(a: T, b: T) bool {
            return a <= b;
        }
    }.f;
}

/// gt(a, b) -- Same as a > b
pub fn gt(comptime T: type) fn (T, T) bool {
    return struct {
        fn f(a: T, b: T) bool {
            return a > b;
        }
    }.f;
}

/// ge(a, b) -- Same as a >= b
pub fn ge(comptime T: type) fn (T, T) bool {
    return struct {
        fn f(a: T, b: T) bool {
            return a >= b;
        }
    }.f;
}

// ============================================================================
// Arithmetic Operations
// ============================================================================

/// add(a, b) -- Same as a + b
pub fn add(comptime T: type) fn (T, T) T {
    return struct {
        fn f(a: T, b: T) T {
            return a + b;
        }
    }.f;
}

/// sub(a, b) -- Same as a - b
pub fn sub(comptime T: type) fn (T, T) T {
    return struct {
        fn f(a: T, b: T) T {
            return a - b;
        }
    }.f;
}

/// mul(a, b) -- Same as a * b
pub fn mul(comptime T: type) fn (T, T) T {
    return struct {
        fn f(a: T, b: T) T {
            return a * b;
        }
    }.f;
}

/// truediv(a, b) -- Same as a / b (true division)
pub fn truediv(comptime T: type) fn (T, T) f64 {
    return struct {
        fn f(a: T, b: T) f64 {
            const af: f64 = if (@typeInfo(T) == .int) @floatFromInt(a) else a;
            const bf: f64 = if (@typeInfo(T) == .int) @floatFromInt(b) else b;
            return af / bf;
        }
    }.f;
}

/// floordiv(a, b) -- Same as a // b
pub fn floordiv(comptime T: type) fn (T, T) T {
    return struct {
        fn f(a: T, b: T) T {
            return @divFloor(a, b);
        }
    }.f;
}

/// mod(a, b) -- Same as a % b
pub fn mod(comptime T: type) fn (T, T) T {
    return struct {
        fn f(a: T, b: T) T {
            return @mod(a, b);
        }
    }.f;
}

/// neg(a) -- Same as -a
pub fn neg(comptime T: type) fn (T) T {
    return struct {
        fn f(a: T) T {
            return -a;
        }
    }.f;
}

/// pos(a) -- Same as +a
pub fn pos(comptime T: type) fn (T) T {
    return struct {
        fn f(a: T) T {
            return a;
        }
    }.f;
}

/// abs(a) -- Same as abs(a)
pub fn abs(comptime T: type) fn (T) T {
    return struct {
        fn f(a: T) T {
            return if (a < 0) -a else a;
        }
    }.f;
}

/// pow(a, b) -- Same as a ** b
pub fn pow(comptime T: type) fn (T, T) T {
    return struct {
        fn f(base: T, exp: T) T {
            return std.math.pow(T, base, exp);
        }
    }.f;
}

// ============================================================================
// Bitwise Operations
// ============================================================================

/// and_(a, b) -- Same as a & b
pub fn and_(comptime T: type) fn (T, T) T {
    return struct {
        fn f(a: T, b: T) T {
            return a & b;
        }
    }.f;
}

/// or_(a, b) -- Same as a | b
pub fn or_(comptime T: type) fn (T, T) T {
    return struct {
        fn f(a: T, b: T) T {
            return a | b;
        }
    }.f;
}

/// xor(a, b) -- Same as a ^ b
pub fn xor(comptime T: type) fn (T, T) T {
    return struct {
        fn f(a: T, b: T) T {
            return a ^ b;
        }
    }.f;
}

/// invert(a) -- Same as ~a
pub fn invert(comptime T: type) fn (T) T {
    return struct {
        fn f(a: T) T {
            return ~a;
        }
    }.f;
}

/// lshift(a, b) -- Same as a << b
pub fn lshift(comptime T: type) fn (T, u6) T {
    return struct {
        fn f(a: T, b: u6) T {
            return a << b;
        }
    }.f;
}

/// rshift(a, b) -- Same as a >> b
pub fn rshift(comptime T: type) fn (T, u6) T {
    return struct {
        fn f(a: T, b: u6) T {
            return a >> b;
        }
    }.f;
}

// ============================================================================
// Logical Operations
// ============================================================================

/// not_(a) -- Same as not a
pub fn not_(a: bool) bool {
    return !a;
}

/// truth(a) -- Return True if a is true, False otherwise
pub fn truth(a: anytype) bool {
    const T = @TypeOf(a);
    if (T == bool) return a;
    if (@typeInfo(T) == .int) return a != 0;
    if (@typeInfo(T) == .float) return a != 0.0;
    if (@typeInfo(T) == .optional) return a != null;
    if (@typeInfo(T) == .pointer) {
        if (@typeInfo(T).pointer.size == .Slice) return a.len > 0;
    }
    return true;
}

/// is_(a, b) -- Same as a is b
pub fn is_(a: anytype, b: @TypeOf(a)) bool {
    return &a == &b;
}

/// is_not(a, b) -- Same as a is not b
pub fn is_not(a: anytype, b: @TypeOf(a)) bool {
    return &a != &b;
}

// ============================================================================
// Sequence Operations
// ============================================================================

/// concat(a, b) -- Same as a + b, for sequences
pub fn concat(comptime T: type, a: []const T, b: []const T, allocator: std.mem.Allocator) ![]T {
    const result = try allocator.alloc(T, a.len + b.len);
    @memcpy(result[0..a.len], a);
    @memcpy(result[a.len..], b);
    return result;
}

/// contains(a, b) -- Same as b in a
pub fn contains(comptime T: type) fn ([]const T, T) bool {
    return struct {
        fn f(seq: []const T, item: T) bool {
            for (seq) |elem| {
                if (elem == item) return true;
            }
            return false;
        }
    }.f;
}

/// countOf(a, b) -- Return the number of times b occurs in a
pub fn countOf(comptime T: type) fn ([]const T, T) usize {
    return struct {
        fn f(seq: []const T, item: T) usize {
            var count: usize = 0;
            for (seq) |elem| {
                if (elem == item) count += 1;
            }
            return count;
        }
    }.f;
}

/// indexOf(a, b) -- Return the first index of b in a
pub fn indexOf(comptime T: type) fn ([]const T, T) ?usize {
    return struct {
        fn f(seq: []const T, item: T) ?usize {
            for (seq, 0..) |elem, i| {
                if (elem == item) return i;
            }
            return null;
        }
    }.f;
}

/// getitem(a, b) -- Same as a[b]
pub fn getitem(comptime T: type, seq: []const T, idx: usize) T {
    return seq[idx];
}

/// setitem(a, b, c) -- Same as a[b] = c
pub fn setitem(comptime T: type, seq: []T, idx: usize, value: T) void {
    seq[idx] = value;
}

/// delitem(a, b) -- Same as del a[b] (not directly possible in Zig slices)
/// Returns a new slice without the element at index
pub fn delitem(comptime T: type, seq: []const T, idx: usize, allocator: std.mem.Allocator) ![]T {
    if (idx >= seq.len) return error.IndexError;
    const result = try allocator.alloc(T, seq.len - 1);
    @memcpy(result[0..idx], seq[0..idx]);
    @memcpy(result[idx..], seq[idx + 1 ..]);
    return result;
}

/// length_hint(obj) -- Return estimated length of obj
pub fn length_hint(seq: anytype) usize {
    const T = @TypeOf(seq);
    if (@typeInfo(T) == .pointer) {
        if (@typeInfo(T).pointer.size == .Slice) return seq.len;
    }
    return 0;
}

// ============================================================================
// Attribute and Item Getters
// ============================================================================

/// itemgetter(item, ...) -> callable
/// Return a callable that fetches item from its operand
pub fn ItemGetter(comptime T: type, comptime idx: usize) type {
    return struct {
        pub fn get(seq: []const T) T {
            return seq[idx];
        }
    };
}

/// attrgetter - would need runtime reflection, simplified version
pub fn AttrGetter(comptime T: type, comptime field: []const u8) type {
    return struct {
        pub fn get(obj: T) @TypeOf(@field(obj, field)) {
            return @field(obj, field);
        }
    };
}

/// methodcaller - simplified version for known method signatures
pub fn MethodCaller(comptime T: type, comptime method: []const u8) type {
    return struct {
        pub fn call(obj: *T) @typeInfo(@TypeOf(@field(obj.*, method))).@"fn".return_type.? {
            return @field(obj.*, method)();
        }
    };
}

// ============================================================================
// In-place Operations (return modified value since Zig is pass-by-value)
// ============================================================================

/// iadd(a, b) -- Same as a += b
pub const iadd = add;

/// isub(a, b) -- Same as a -= b
pub const isub = sub;

/// imul(a, b) -- Same as a *= b
pub const imul = mul;

/// ifloordiv(a, b) -- Same as a //= b
pub const ifloordiv = floordiv;

/// imod(a, b) -- Same as a %= b
pub const imod = mod;

/// iand(a, b) -- Same as a &= b
pub const iand = and_;

/// ior(a, b) -- Same as a |= b
pub const ior = or_;

/// ixor(a, b) -- Same as a ^= b
pub const ixor = xor;

/// ilshift(a, b) -- Same as a <<= b
pub const ilshift = lshift;

/// irshift(a, b) -- Same as a >>= b
pub const irshift = rshift;

// ============================================================================
// Special
// ============================================================================

/// getIndex(a) -- Same as a.__index__()
pub fn getIndex(a: anytype) i64 {
    const T = @TypeOf(a);
    if (@typeInfo(T) == .int) return @intCast(a);
    return 0;
}

/// inv(a) -- Same as ~a (alias for invert)
pub const inv = invert;

// ============================================================================
// Tests
// ============================================================================

test "comparison operators" {
    const lt_i32 = lt(i32);
    try std.testing.expect(lt_i32(1, 2));
    try std.testing.expect(!lt_i32(2, 1));
    try std.testing.expect(!lt_i32(1, 1));

    const eq_i32 = eq(i32);
    try std.testing.expect(eq_i32(1, 1));
    try std.testing.expect(!eq_i32(1, 2));
}

test "arithmetic operators" {
    const add_i32 = add(i32);
    try std.testing.expectEqual(@as(i32, 5), add_i32(2, 3));

    const mul_i32 = mul(i32);
    try std.testing.expectEqual(@as(i32, 6), mul_i32(2, 3));

    const neg_i32 = neg(i32);
    try std.testing.expectEqual(@as(i32, -5), neg_i32(5));

    const abs_i32 = abs(i32);
    try std.testing.expectEqual(@as(i32, 5), abs_i32(-5));
    try std.testing.expectEqual(@as(i32, 5), abs_i32(5));
}

test "bitwise operators" {
    const and_u8 = and_(u8);
    try std.testing.expectEqual(@as(u8, 0b1010 & 0b1100), and_u8(0b1010, 0b1100));

    const or_u8 = or_(u8);
    try std.testing.expectEqual(@as(u8, 0b1010 | 0b1100), or_u8(0b1010, 0b1100));

    const xor_u8 = xor(u8);
    try std.testing.expectEqual(@as(u8, 0b1010 ^ 0b1100), xor_u8(0b1010, 0b1100));
}

test "sequence operators" {
    const contains_i32 = contains(i32);
    const items = [_]i32{ 1, 2, 3, 4, 5 };
    try std.testing.expect(contains_i32(&items, 3));
    try std.testing.expect(!contains_i32(&items, 6));

    const countOf_i32 = countOf(i32);
    const items2 = [_]i32{ 1, 2, 2, 3, 2 };
    try std.testing.expectEqual(@as(usize, 3), countOf_i32(&items2, 2));

    const indexOf_i32 = indexOf(i32);
    try std.testing.expectEqual(@as(?usize, 1), indexOf_i32(&items, 2));
    try std.testing.expectEqual(@as(?usize, null), indexOf_i32(&items, 6));
}

test "truth" {
    try std.testing.expect(truth(true));
    try std.testing.expect(!truth(false));
    try std.testing.expect(truth(@as(i32, 1)));
    try std.testing.expect(!truth(@as(i32, 0)));
    try std.testing.expect(truth(@as(f64, 1.0)));
    try std.testing.expect(!truth(@as(f64, 0.0)));
}

test "itemgetter" {
    const items = [_]i32{ 10, 20, 30, 40 };
    const get1 = ItemGetter(i32, 1);
    try std.testing.expectEqual(@as(i32, 20), get1.get(&items));
}
