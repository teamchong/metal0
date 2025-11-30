/// BigInt - Arbitrary Precision Integer for metal0
/// Wraps std.math.big.int.Managed for Python-compatible arbitrary precision integers
const std = @import("std");
const Managed = std.math.big.int.Managed;
const Allocator = std.mem.Allocator;

/// BigInt type for arbitrary precision integers
/// Uses std.math.big.int.Managed internally
pub const BigInt = struct {
    managed: Managed,

    const Self = @This();

    /// Create a BigInt from an i64 value
    pub fn fromInt(allocator: Allocator, value: i64) !Self {
        var m = try Managed.init(allocator);
        try m.set(value);
        return Self{ .managed = m };
    }

    /// Create a BigInt from an i128 value
    pub fn fromInt128(allocator: Allocator, value: i128) !Self {
        var m = try Managed.init(allocator);
        try m.set(value);
        return Self{ .managed = m };
    }

    /// Create a BigInt from a string in given base
    pub fn fromString(allocator: Allocator, str: []const u8, base: u8) !Self {
        var m = try Managed.init(allocator);
        errdefer m.deinit();
        try m.setString(base, str);
        return Self{ .managed = m };
    }

    /// Create a BigInt from a float (truncates towards zero)
    pub fn fromFloat(allocator: Allocator, value: f64) !Self {
        var m = try Managed.init(allocator);
        // Handle infinity and NaN
        if (std.math.isNan(value) or std.math.isInf(value)) {
            return error.InvalidFloat;
        }
        // Truncate float to integer
        const truncated = @trunc(value);
        // Check if it fits in i128 first (fast path)
        if (@abs(truncated) < @as(f64, @floatFromInt(@as(i128, std.math.maxInt(i128))))) {
            const int_val: i128 = @intFromFloat(truncated);
            try m.set(int_val);
        } else {
            // Large float - convert via string
            var buf: [512]u8 = undefined;
            const str = std.fmt.bufPrint(&buf, "{d:.0}", .{truncated}) catch return error.FloatTooLarge;
            // Remove any trailing .0 and leading spaces
            var clean = std.mem.trim(u8, str, " ");
            if (std.mem.indexOf(u8, clean, ".")) |dot| {
                clean = clean[0..dot];
            }
            // Remove negative sign temporarily for parsing
            const is_negative = clean.len > 0 and clean[0] == '-';
            if (is_negative) clean = clean[1..];
            try m.setString(10, clean);
            if (is_negative) m.negate();
        }
        return Self{ .managed = m };
    }

    /// Free the BigInt memory
    pub fn deinit(self: *Self) void {
        self.managed.deinit();
    }

    /// Clone this BigInt
    pub fn clone(self: *const Self, allocator: Allocator) !Self {
        return Self{ .managed = try self.managed.cloneWithDifferentAllocator(allocator) };
    }

    /// Add two BigInts
    pub fn add(self: *const Self, other: *const Self, allocator: Allocator) !Self {
        var result = try Managed.init(allocator);
        try result.add(&self.managed, &other.managed);
        return Self{ .managed = result };
    }

    /// Subtract two BigInts
    pub fn sub(self: *const Self, other: *const Self, allocator: Allocator) !Self {
        var result = try Managed.init(allocator);
        try result.sub(&self.managed, &other.managed);
        return Self{ .managed = result };
    }

    /// Multiply two BigInts
    pub fn mul(self: *const Self, other: *const Self, allocator: Allocator) !Self {
        var result = try Managed.init(allocator);
        try result.mul(&self.managed, &other.managed);
        return Self{ .managed = result };
    }

    /// Floor divide two BigInts (Python //)
    pub fn floorDiv(self: *const Self, other: *const Self, allocator: Allocator) !Self {
        var q = try Managed.init(allocator);
        var r = try Managed.init(allocator);
        defer r.deinit();
        try q.divFloor(&r, &self.managed, &other.managed);
        return Self{ .managed = q };
    }

    /// Modulo (Python %)
    pub fn mod(self: *const Self, other: *const Self, allocator: Allocator) !Self {
        var q = try Managed.init(allocator);
        defer q.deinit();
        var r = try Managed.init(allocator);
        try q.divFloor(&r, &self.managed, &other.managed);
        return Self{ .managed = r };
    }

    /// Negate
    pub fn negate(self: *Self) void {
        self.managed.negate();
    }

    /// Absolute value
    pub fn abs(self: *const Self, allocator: Allocator) !Self {
        var result = try self.clone(allocator);
        result.managed.setSign(.positive);
        return result;
    }

    /// Compare two BigInts: -1 if self < other, 0 if equal, 1 if self > other
    pub fn compare(self: *const Self, other: *const Self) i32 {
        const order = self.managed.order(other.managed);
        return switch (order) {
            .lt => -1,
            .eq => 0,
            .gt => 1,
        };
    }

    /// Check equality
    pub fn eql(self: *const Self, other: *const Self) bool {
        return self.compare(other) == 0;
    }

    /// Check if zero
    pub fn isZero(self: *const Self) bool {
        return self.managed.eqlZero();
    }

    /// Check if negative
    pub fn isNegative(self: *const Self) bool {
        return !self.managed.isPositive() and !self.managed.eqlZero();
    }

    /// Try to convert to i64 (returns null if too large)
    pub fn toInt64(self: *const Self) ?i64 {
        return self.managed.toConst().toInt(i64) catch return null;
    }

    /// Try to convert to i128 (returns null if too large)
    pub fn toInt128(self: *const Self) ?i128 {
        return self.managed.toConst().toInt(i128) catch return null;
    }

    /// Convert to string in given base
    pub fn toString(self: *const Self, allocator: Allocator, base: u8) ![]u8 {
        return self.managed.toString(allocator, base, .lower);
    }

    /// Convert to string in base 10
    pub fn toDecimalString(self: *const Self, allocator: Allocator) ![]u8 {
        return self.toString(allocator, 10);
    }

    /// Get bit count
    pub fn bitCount(self: *const Self) usize {
        return self.managed.bitCountAbs();
    }

    /// Get bit length (Python's int.bit_length())
    /// Returns number of bits required to represent the absolute value
    pub fn bit_length(self: *const Self) i64 {
        return @intCast(self.managed.bitCountAbs());
    }

    /// Left shift
    pub fn shl(self: *const Self, shift: usize, allocator: Allocator) !Self {
        var result = try Managed.init(allocator);
        try result.shiftLeft(&self.managed, shift);
        return Self{ .managed = result };
    }

    /// Right shift (arithmetic)
    pub fn shr(self: *const Self, shift: usize, allocator: Allocator) !Self {
        var result = try Managed.init(allocator);
        try result.shiftRight(&self.managed, shift);
        return Self{ .managed = result };
    }

    /// Bitwise AND
    pub fn bitAnd(self: *const Self, other: *const Self, allocator: Allocator) !Self {
        var result = try Managed.init(allocator);
        try result.bitAnd(&self.managed, &other.managed);
        return Self{ .managed = result };
    }

    /// Bitwise OR
    pub fn bitOr(self: *const Self, other: *const Self, allocator: Allocator) !Self {
        var result = try Managed.init(allocator);
        try result.bitOr(&self.managed, &other.managed);
        return Self{ .managed = result };
    }

    /// Bitwise XOR
    pub fn bitXor(self: *const Self, other: *const Self, allocator: Allocator) !Self {
        var result = try Managed.init(allocator);
        try result.bitXor(&self.managed, &other.managed);
        return Self{ .managed = result };
    }

    /// Power (a ** b)
    pub fn pow(self: *const Self, exp: u32, allocator: Allocator) !Self {
        var result = try Managed.init(allocator);
        try result.pow(&self.managed, exp);
        return Self{ .managed = result };
    }

    /// Format for std.fmt (allows printing with {})
    pub fn format(
        self: *const Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try self.writeToWriter(writer);
    }

    /// Format for numeric specifiers like {d} (called by std.fmt for integer-like types)
    pub fn formatNumber(self: *const Self, writer: anytype, _: anytype) !void {
        try self.writeToWriter(writer);
    }

    /// Write BigInt value to any writer
    fn writeToWriter(self: *const Self, writer: anytype) !void {
        // Use a stack buffer for small numbers, heap for large
        var buf: [256]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buf);

        // Try to format with stack buffer first
        if (self.managed.toString(fba.allocator(), 10, .lower)) |str| {
            try writer.writeAll(str);
        } else |_| {
            // Fall back to heap allocation for very large numbers
            var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            defer _ = gpa.deinit();
            const str = self.managed.toString(gpa.allocator(), 10, .lower) catch return;
            defer gpa.allocator().free(str);
            try writer.writeAll(str);
        }
    }
};

/// Error types for BigInt operations
pub const BigIntError = error{
    InvalidFloat,
    FloatTooLarge,
    DivisionByZero,
    OutOfMemory,
};

// ============================================================================
// Convenience functions for codegen
// ============================================================================

/// Parse a decimal string to BigInt
pub fn parseBigInt(allocator: Allocator, str: []const u8) !BigInt {
    return BigInt.fromString(allocator, str, 10);
}

/// Parse a string with optional base prefix (0x, 0o, 0b)
pub fn parseBigIntAuto(allocator: Allocator, str: []const u8) !BigInt {
    var s = str;
    var base: u8 = 10;

    // Handle negative
    const is_negative = s.len > 0 and s[0] == '-';
    if (is_negative) s = s[1..];

    // Handle base prefixes
    if (s.len >= 2) {
        if (std.mem.startsWith(u8, s, "0x") or std.mem.startsWith(u8, s, "0X")) {
            base = 16;
            s = s[2..];
        } else if (std.mem.startsWith(u8, s, "0o") or std.mem.startsWith(u8, s, "0O")) {
            base = 8;
            s = s[2..];
        } else if (std.mem.startsWith(u8, s, "0b") or std.mem.startsWith(u8, s, "0B")) {
            base = 2;
            s = s[2..];
        }
    }

    var result = try BigInt.fromString(allocator, s, base);
    if (is_negative) result.negate();
    return result;
}

/// Create BigInt from float (for int(float) builtin)
pub fn bigIntFromFloat(allocator: Allocator, value: f64) !BigInt {
    return BigInt.fromFloat(allocator, value);
}

// ============================================================================
// Tests
// ============================================================================

test "BigInt basic operations" {
    const allocator = std.testing.allocator;

    var a = try BigInt.fromInt(allocator, 42);
    defer a.deinit();

    var b = try BigInt.fromInt(allocator, 10);
    defer b.deinit();

    var sum = try a.add(&b, allocator);
    defer sum.deinit();
    try std.testing.expectEqual(@as(?i64, 52), sum.toInt64());

    var diff = try a.sub(&b, allocator);
    defer diff.deinit();
    try std.testing.expectEqual(@as(?i64, 32), diff.toInt64());

    var prod = try a.mul(&b, allocator);
    defer prod.deinit();
    try std.testing.expectEqual(@as(?i64, 420), prod.toInt64());
}

test "BigInt large numbers" {
    const allocator = std.testing.allocator;

    // Test sys.maxsize + 1
    var maxsize = try BigInt.fromInt128(allocator, std.math.maxInt(i64));
    defer maxsize.deinit();

    var one = try BigInt.fromInt(allocator, 1);
    defer one.deinit();

    var result = try maxsize.add(&one, allocator);
    defer result.deinit();

    // Should exceed i64 but fit in i128
    try std.testing.expectEqual(@as(?i64, null), result.toInt64());
    try std.testing.expectEqual(@as(?i128, 9223372036854775808), result.toInt128());
}

test "BigInt from string" {
    const allocator = std.testing.allocator;

    // Large number from string (100 digits of 1s)
    const large_str = "1" ** 100; // 100 ones = 1111...111
    var large = try BigInt.fromString(allocator, large_str, 10);
    defer large.deinit();

    // Should not fit in i64 or i128
    try std.testing.expectEqual(@as(?i64, null), large.toInt64());
    try std.testing.expectEqual(@as(?i128, null), large.toInt128());

    // But should convert back to string correctly
    const str = try large.toDecimalString(allocator);
    defer allocator.free(str);
    try std.testing.expectEqualStrings(large_str, str);
}

test "BigInt from float" {
    const allocator = std.testing.allocator;

    // Normal float
    var a = try BigInt.fromFloat(allocator, 42.7);
    defer a.deinit();
    try std.testing.expectEqual(@as(?i64, 42), a.toInt64());

    // Negative float
    var b = try BigInt.fromFloat(allocator, -123.9);
    defer b.deinit();
    try std.testing.expectEqual(@as(?i64, -123), b.toInt64());
}

test "BigInt comparison" {
    const allocator = std.testing.allocator;

    var a = try BigInt.fromInt(allocator, 100);
    defer a.deinit();

    var b = try BigInt.fromInt(allocator, 50);
    defer b.deinit();

    var c = try BigInt.fromInt(allocator, 100);
    defer c.deinit();

    try std.testing.expectEqual(@as(i32, 1), a.compare(&b)); // 100 > 50
    try std.testing.expectEqual(@as(i32, -1), b.compare(&a)); // 50 < 100
    try std.testing.expectEqual(@as(i32, 0), a.compare(&c)); // 100 == 100
    try std.testing.expect(a.eql(&c));
}
