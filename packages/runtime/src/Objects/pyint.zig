/// UnifiedInt - Unified Python Integer Type
/// Auto-promotes from i64 to BigInt on overflow, matching Python's unlimited precision semantics.
///
/// Use cases:
/// - i64: Loop counters, array indices, known-small values (fast path)
/// - UnifiedInt: Function params/returns, user input, arithmetic that may overflow
/// - BigInt: Explicitly large numbers (crypto, etc.)
const std = @import("std");
const Allocator = std.mem.Allocator;
const bigint_mod = @import("bigint");
const BigInt = bigint_mod.BigInt;

/// UnifiedInt: Tagged union for Python integers
/// Fast path uses i64, auto-promotes to BigInt on overflow.
pub const UnifiedInt = union(enum) {
    small: i64,
    big: *BigInt,

    const Self = @This();

    // ============================================================================
    // Constructors
    // ============================================================================

    /// Create from i64 (always small)
    pub fn fromI64(value: i64) Self {
        return .{ .small = value };
    }

    /// Create from BigInt (takes ownership)
    pub fn fromBigInt(big: *BigInt) Self {
        // Try to demote to i64 if it fits
        if (big.toInt64()) |small_val| {
            big.deinit();
            return .{ .small = small_val };
        }
        return .{ .big = big };
    }

    /// Create from BigInt value (allocates)
    pub fn fromBigIntValue(allocator: Allocator, big: *const BigInt) !Self {
        // Try to demote to i64 if it fits
        if (big.toInt64()) |small_val| {
            return .{ .small = small_val };
        }
        const cloned = try allocator.create(BigInt);
        cloned.* = try big.clone(allocator);
        return .{ .big = cloned };
    }

    /// Create from any integer type
    pub fn from(comptime T: type, value: T) Self {
        if (@typeInfo(T) == .int) {
            const info = @typeInfo(T).int;
            // Fits in i64?
            if (info.bits <= 64 and (info.signedness == .signed or info.bits < 64)) {
                return .{ .small = @intCast(value) };
            }
        }
        // Large value - should use fromBigInt
        @compileError("Use fromBigInt for values that may exceed i64");
    }

    // ============================================================================
    // Arithmetic with overflow detection
    // ============================================================================

    /// Add two PyInts
    pub fn add(self: Self, other: Self, allocator: Allocator) !Self {
        switch (self) {
            .small => |a| switch (other) {
                .small => |b| {
                    const result = @addWithOverflow(a, b);
                    if (result[1] == 0) {
                        return .{ .small = result[0] };
                    }
                    // Overflow - promote to BigInt
                    return try promotedAdd(a, b, allocator);
                },
                .big => |b_big| {
                    var a_big = try BigInt.fromInt(allocator, a);
                    defer a_big.deinit();
                    var result_big = try a_big.add(b_big, allocator);
                    return demoteOrWrap(&result_big, allocator);
                },
            },
            .big => |a_big| switch (other) {
                .small => |b| {
                    var b_big = try BigInt.fromInt(allocator, b);
                    defer b_big.deinit();
                    var result_big = try a_big.add(&b_big, allocator);
                    return demoteOrWrap(&result_big, allocator);
                },
                .big => |b_big| {
                    var result_big = try a_big.add(b_big, allocator);
                    return demoteOrWrap(&result_big, allocator);
                },
            },
        }
    }

    /// Subtract two PyInts
    pub fn sub(self: Self, other: Self, allocator: Allocator) !Self {
        switch (self) {
            .small => |a| switch (other) {
                .small => |b| {
                    const result = @subWithOverflow(a, b);
                    if (result[1] == 0) {
                        return .{ .small = result[0] };
                    }
                    return try promotedSub(a, b, allocator);
                },
                .big => |b_big| {
                    var a_big = try BigInt.fromInt(allocator, a);
                    defer a_big.deinit();
                    var result_big = try a_big.sub(b_big, allocator);
                    return demoteOrWrap(&result_big, allocator);
                },
            },
            .big => |a_big| switch (other) {
                .small => |b| {
                    var b_big = try BigInt.fromInt(allocator, b);
                    defer b_big.deinit();
                    var result_big = try a_big.sub(&b_big, allocator);
                    return demoteOrWrap(&result_big, allocator);
                },
                .big => |b_big| {
                    var result_big = try a_big.sub(b_big, allocator);
                    return demoteOrWrap(&result_big, allocator);
                },
            },
        }
    }

    /// Multiply two PyInts
    pub fn mul(self: Self, other: Self, allocator: Allocator) !Self {
        switch (self) {
            .small => |a| switch (other) {
                .small => |b| {
                    const result = @mulWithOverflow(a, b);
                    if (result[1] == 0) {
                        return .{ .small = result[0] };
                    }
                    return try promotedMul(a, b, allocator);
                },
                .big => |b_big| {
                    var a_big = try BigInt.fromInt(allocator, a);
                    defer a_big.deinit();
                    var result_big = try a_big.mul(b_big, allocator);
                    return demoteOrWrap(&result_big, allocator);
                },
            },
            .big => |a_big| switch (other) {
                .small => |b| {
                    var b_big = try BigInt.fromInt(allocator, b);
                    defer b_big.deinit();
                    var result_big = try a_big.mul(&b_big, allocator);
                    return demoteOrWrap(&result_big, allocator);
                },
                .big => |b_big| {
                    var result_big = try a_big.mul(b_big, allocator);
                    return demoteOrWrap(&result_big, allocator);
                },
            },
        }
    }

    /// Floor divide (Python //)
    pub fn floorDiv(self: Self, other: Self, allocator: Allocator) !Self {
        switch (self) {
            .small => |a| switch (other) {
                .small => |b| {
                    if (b == 0) return error.DivisionByZero;
                    return .{ .small = @divFloor(a, b) };
                },
                .big => |b_big| {
                    var a_big = try BigInt.fromInt(allocator, a);
                    defer a_big.deinit();
                    var result_big = try a_big.floorDiv(b_big, allocator);
                    return demoteOrWrap(&result_big, allocator);
                },
            },
            .big => |a_big| switch (other) {
                .small => |b| {
                    var b_big = try BigInt.fromInt(allocator, b);
                    defer b_big.deinit();
                    var result_big = try a_big.floorDiv(&b_big, allocator);
                    return demoteOrWrap(&result_big, allocator);
                },
                .big => |b_big| {
                    var result_big = try a_big.floorDiv(b_big, allocator);
                    return demoteOrWrap(&result_big, allocator);
                },
            },
        }
    }

    /// Modulo (Python %)
    pub fn mod(self: Self, other: Self, allocator: Allocator) !Self {
        switch (self) {
            .small => |a| switch (other) {
                .small => |b| {
                    if (b == 0) return error.DivisionByZero;
                    // Python's modulo: result has same sign as divisor
                    const r = @mod(a, b);
                    return .{ .small = r };
                },
                .big => |b_big| {
                    var a_big = try BigInt.fromInt(allocator, a);
                    defer a_big.deinit();
                    var result_big = try a_big.mod(b_big, allocator);
                    return demoteOrWrap(&result_big, allocator);
                },
            },
            .big => |a_big| switch (other) {
                .small => |b| {
                    var b_big = try BigInt.fromInt(allocator, b);
                    defer b_big.deinit();
                    var result_big = try a_big.mod(&b_big, allocator);
                    return demoteOrWrap(&result_big, allocator);
                },
                .big => |b_big| {
                    var result_big = try a_big.mod(b_big, allocator);
                    return demoteOrWrap(&result_big, allocator);
                },
            },
        }
    }

    /// Left shift
    pub fn shl(self: Self, shift: u32, allocator: Allocator) !Self {
        switch (self) {
            .small => |a| {
                // Check if shift would overflow
                if (shift >= 64 or (a != 0 and shift > @clz(@as(u64, @abs(a))))) {
                    var a_big = try BigInt.fromInt(allocator, a);
                    defer a_big.deinit();
                    var result_big = try a_big.shl(shift, allocator);
                    return demoteOrWrap(&result_big, allocator);
                }
                return .{ .small = a << @intCast(shift) };
            },
            .big => |a_big| {
                var result_big = try a_big.shl(shift, allocator);
                return demoteOrWrap(&result_big, allocator);
            },
        }
    }

    /// Right shift
    pub fn shr(self: Self, shift: u32, allocator: Allocator) !Self {
        switch (self) {
            .small => |a| {
                if (shift >= 64) return .{ .small = if (a < 0) -1 else 0 };
                return .{ .small = a >> @intCast(shift) };
            },
            .big => |a_big| {
                var result_big = try a_big.shr(shift, allocator);
                return demoteOrWrap(&result_big, allocator);
            },
        }
    }

    /// Power (a ** b)
    pub fn pow(self: Self, exp: u32, allocator: Allocator) !Self {
        switch (self) {
            .small => |a| {
                // Quick check: small base with small exponent
                if (exp <= 1) {
                    return if (exp == 0) .{ .small = 1 } else .{ .small = a };
                }
                // For larger exponents, always use BigInt to avoid overflow
                var a_big = try BigInt.fromInt(allocator, a);
                defer a_big.deinit();
                var result_big = try a_big.pow(exp, allocator);
                return demoteOrWrap(&result_big, allocator);
            },
            .big => |a_big| {
                var result_big = try a_big.pow(exp, allocator);
                return demoteOrWrap(&result_big, allocator);
            },
        }
    }

    /// Negate
    pub fn neg(self: Self, allocator: Allocator) !Self {
        switch (self) {
            .small => |a| {
                // Only i64 min overflows on negation
                if (a == std.math.minInt(i64)) {
                    var a_big = try BigInt.fromInt(allocator, a);
                    var result_big = try a_big.neg(allocator);
                    a_big.deinit();
                    return demoteOrWrap(&result_big, allocator);
                }
                return .{ .small = -a };
            },
            .big => |a_big| {
                var result_big = try a_big.neg(allocator);
                return demoteOrWrap(&result_big, allocator);
            },
        }
    }

    /// Absolute value
    pub fn abs(self: Self, allocator: Allocator) !Self {
        switch (self) {
            .small => |a| {
                if (a == std.math.minInt(i64)) {
                    var a_big = try BigInt.fromInt(allocator, a);
                    var result_big = try a_big.abs(allocator);
                    a_big.deinit();
                    return demoteOrWrap(&result_big, allocator);
                }
                return .{ .small = if (a < 0) -a else a };
            },
            .big => |a_big| {
                var result_big = try a_big.abs(allocator);
                return demoteOrWrap(&result_big, allocator);
            },
        }
    }

    // ============================================================================
    // Bitwise Operations
    // ============================================================================

    /// Bitwise AND: self & other
    pub fn bitAnd(self: Self, other: Self, allocator: Allocator) !Self {
        switch (self) {
            .small => |a| switch (other) {
                .small => |b| {
                    return .{ .small = a & b };
                },
                .big => |b_big| {
                    var a_big = try BigInt.fromInt(allocator, a);
                    defer a_big.deinit();
                    var result_big = try a_big.bitAnd(b_big, allocator);
                    return demoteOrWrap(&result_big, allocator);
                },
            },
            .big => |a_big| switch (other) {
                .small => |b| {
                    var b_big = try BigInt.fromInt(allocator, b);
                    defer b_big.deinit();
                    var result_big = try a_big.bitAnd(&b_big, allocator);
                    return demoteOrWrap(&result_big, allocator);
                },
                .big => |b_big| {
                    var result_big = try a_big.bitAnd(b_big, allocator);
                    return demoteOrWrap(&result_big, allocator);
                },
            },
        }
    }

    /// Bitwise OR: self | other
    pub fn bitOr(self: Self, other: Self, allocator: Allocator) !Self {
        switch (self) {
            .small => |a| switch (other) {
                .small => |b| {
                    return .{ .small = a | b };
                },
                .big => |b_big| {
                    var a_big = try BigInt.fromInt(allocator, a);
                    defer a_big.deinit();
                    var result_big = try a_big.bitOr(b_big, allocator);
                    return demoteOrWrap(&result_big, allocator);
                },
            },
            .big => |a_big| switch (other) {
                .small => |b| {
                    var b_big = try BigInt.fromInt(allocator, b);
                    defer b_big.deinit();
                    var result_big = try a_big.bitOr(&b_big, allocator);
                    return demoteOrWrap(&result_big, allocator);
                },
                .big => |b_big| {
                    var result_big = try a_big.bitOr(b_big, allocator);
                    return demoteOrWrap(&result_big, allocator);
                },
            },
        }
    }

    /// Bitwise XOR: self ^ other
    pub fn bitXor(self: Self, other: Self, allocator: Allocator) !Self {
        switch (self) {
            .small => |a| switch (other) {
                .small => |b| {
                    return .{ .small = a ^ b };
                },
                .big => |b_big| {
                    var a_big = try BigInt.fromInt(allocator, a);
                    defer a_big.deinit();
                    var result_big = try a_big.bitXor(b_big, allocator);
                    return demoteOrWrap(&result_big, allocator);
                },
            },
            .big => |a_big| switch (other) {
                .small => |b| {
                    var b_big = try BigInt.fromInt(allocator, b);
                    defer b_big.deinit();
                    var result_big = try a_big.bitXor(&b_big, allocator);
                    return demoteOrWrap(&result_big, allocator);
                },
                .big => |b_big| {
                    var result_big = try a_big.bitXor(b_big, allocator);
                    return demoteOrWrap(&result_big, allocator);
                },
            },
        }
    }

    // ============================================================================
    // Comparison
    // ============================================================================

    /// Compare: -1 if self < other, 0 if equal, 1 if self > other
    pub fn compare(self: Self, other: Self, allocator: Allocator) !i32 {
        switch (self) {
            .small => |a| switch (other) {
                .small => |b| {
                    return if (a < b) @as(i32, -1) else if (a > b) @as(i32, 1) else @as(i32, 0);
                },
                .big => |b_big| {
                    var a_big = try BigInt.fromInt(allocator, a);
                    defer a_big.deinit();
                    return a_big.compare(b_big);
                },
            },
            .big => |a_big| switch (other) {
                .small => |b| {
                    var b_big = try BigInt.fromInt(allocator, b);
                    defer b_big.deinit();
                    return a_big.compare(&b_big);
                },
                .big => |b_big| {
                    return a_big.compare(b_big);
                },
            },
        }
    }

    /// Equality check
    pub fn eql(self: Self, other: Self, allocator: Allocator) !bool {
        return (try self.compare(other, allocator)) == 0;
    }

    // ============================================================================
    // Conversions
    // ============================================================================

    /// Try to get as i64 (returns null if too large)
    pub fn toI64(self: Self) ?i64 {
        return switch (self) {
            .small => |v| v,
            .big => |b| b.toInt64(),
        };
    }

    /// Convert to f64
    pub fn toFloat(self: Self) f64 {
        return switch (self) {
            .small => |v| @floatFromInt(v),
            .big => |b| b.toFloat(),
        };
    }

    /// Convert to BigInt (always succeeds)
    pub fn toBigInt(self: Self, allocator: Allocator) !BigInt {
        return switch (self) {
            .small => |v| try BigInt.fromInt(allocator, v),
            .big => |b| try b.clone(allocator),
        };
    }

    /// Python-compatible hash
    pub fn hash(self: Self, allocator: Allocator) !i64 {
        switch (self) {
            .small => |v| {
                // Python hashes small ints to themselves (mostly)
                const HASH_MODULUS: i64 = 2305843009213693951; // 2^61 - 1
                var h = @mod(v, HASH_MODULUS);
                if (h == -1) h = -2;
                return h;
            },
            .big => |b| {
                _ = allocator;
                return b.hash();
            },
        }
    }

    /// Check if zero
    pub fn isZero(self: Self) bool {
        return switch (self) {
            .small => |v| v == 0,
            .big => |b| b.isZero(),
        };
    }

    /// Check if negative
    pub fn isNegative(self: Self) bool {
        return switch (self) {
            .small => |v| v < 0,
            .big => |b| b.isNegative(),
        };
    }

    /// Get underlying BigInt pointer (for compatibility)
    pub fn asBigInt(self: Self) ?*BigInt {
        return switch (self) {
            .small => null,
            .big => |b| b,
        };
    }

    // ============================================================================
    // Memory management
    // ============================================================================

    /// Free BigInt memory if allocated
    pub fn deinit(self: *Self, allocator: Allocator) void {
        switch (self.*) {
            .small => {},
            .big => |b| {
                b.deinit();
                allocator.destroy(b);
            },
        }
    }

    /// Clone this PyInt
    pub fn clone(self: Self, allocator: Allocator) !Self {
        return switch (self) {
            .small => |v| .{ .small = v },
            .big => |b| {
                const new_big = try allocator.create(BigInt);
                new_big.* = try b.clone(allocator);
                return .{ .big = new_big };
            },
        };
    }

    // ============================================================================
    // Formatting
    // ============================================================================

    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .small => |v| try writer.print("{d}", .{v}),
            .big => |b| try b.format("", .{}, writer),
        }
    }

    // ============================================================================
    // Internal helpers
    // ============================================================================

    fn promotedAdd(a: i64, b: i64, allocator: Allocator) !Self {
        var a_big = try BigInt.fromInt(allocator, a);
        defer a_big.deinit();
        var b_big = try BigInt.fromInt(allocator, b);
        defer b_big.deinit();
        var result = try a_big.add(&b_big, allocator);
        return demoteOrWrap(&result, allocator);
    }

    fn promotedSub(a: i64, b: i64, allocator: Allocator) !Self {
        var a_big = try BigInt.fromInt(allocator, a);
        defer a_big.deinit();
        var b_big = try BigInt.fromInt(allocator, b);
        defer b_big.deinit();
        var result = try a_big.sub(&b_big, allocator);
        return demoteOrWrap(&result, allocator);
    }

    fn promotedMul(a: i64, b: i64, allocator: Allocator) !Self {
        var a_big = try BigInt.fromInt(allocator, a);
        defer a_big.deinit();
        var b_big = try BigInt.fromInt(allocator, b);
        defer b_big.deinit();
        var result = try a_big.mul(&b_big, allocator);
        return demoteOrWrap(&result, allocator);
    }

    /// Try to demote BigInt back to i64 if it fits, otherwise wrap in heap pointer
    fn demoteOrWrap(big: *BigInt, allocator: Allocator) !Self {
        if (big.toInt64()) |small_val| {
            big.deinit();
            return .{ .small = small_val };
        }
        // Heap allocate and store pointer
        const heap_big = try allocator.create(BigInt);
        heap_big.* = big.*;
        return .{ .big = heap_big };
    }
};

// ============================================================================
// Convenience functions for codegen
// ============================================================================

/// Create UnifiedInt from i64
pub fn unifiedInt(value: i64) UnifiedInt {
    return UnifiedInt.fromI64(value);
}

/// Create UnifiedInt from BigInt pointer (takes ownership)
pub fn unifiedIntFromBig(big: *BigInt) UnifiedInt {
    return UnifiedInt.fromBigInt(big);
}

// ============================================================================
// Tests
// ============================================================================

test "UnifiedInt basic small operations" {
    const allocator = std.testing.allocator;

    const a = UnifiedInt.fromI64(42);
    const b = UnifiedInt.fromI64(10);

    var sum = try a.add(b, allocator);
    defer sum.deinit(allocator);
    try std.testing.expectEqual(@as(?i64, 52), sum.toI64());

    var diff = try a.sub(b, allocator);
    defer diff.deinit(allocator);
    try std.testing.expectEqual(@as(?i64, 32), diff.toI64());

    var prod = try a.mul(b, allocator);
    defer prod.deinit(allocator);
    try std.testing.expectEqual(@as(?i64, 420), prod.toI64());
}

test "UnifiedInt overflow promotion" {
    const allocator = std.testing.allocator;

    const max = UnifiedInt.fromI64(std.math.maxInt(i64));
    const one = UnifiedInt.fromI64(1);

    var result = try max.add(one, allocator);
    defer result.deinit(allocator);

    // Should have promoted to BigInt
    try std.testing.expectEqual(@as(?i64, null), result.toI64());
    try std.testing.expect(result.asBigInt() != null);
}

test "UnifiedInt shift overflow" {
    const allocator = std.testing.allocator;

    const one = UnifiedInt.fromI64(1);
    var result = try one.shl(100, allocator);
    defer result.deinit(allocator);

    // Should be big
    try std.testing.expectEqual(@as(?i64, null), result.toI64());
}
