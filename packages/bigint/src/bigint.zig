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

/// Parse a string to BigInt with Unicode whitespace handling (like Python's int())
pub fn parseBigIntUnicode(allocator: Allocator, str: []const u8, base: u8) !BigInt {
    // Strip leading/trailing Unicode whitespace
    var s = str;

    // Strip leading whitespace (ASCII and common Unicode)
    while (s.len > 0) {
        if (s[0] == ' ' or s[0] == '\t' or s[0] == '\n' or s[0] == '\r') {
            s = s[1..];
        } else if (s.len >= 3 and s[0] == 0xE2) {
            // Unicode spaces: U+2000-U+200A, U+2028, U+2029, U+202F, U+205F, U+3000
            if ((s[1] == 0x80 and s[2] >= 0x80 and s[2] <= 0x8A) or // U+2000-U+200A
                (s[1] == 0x80 and (s[2] == 0xA8 or s[2] == 0xA9 or s[2] == 0xAF)) or // U+2028, U+2029, U+202F
                (s[1] == 0x81 and s[2] == 0x9F)) // U+205F
            {
                s = s[3..];
            } else {
                break;
            }
        } else if (s.len >= 3 and s[0] == 0xE3 and s[1] == 0x80 and s[2] == 0x80) {
            // U+3000 (ideographic space)
            s = s[3..];
        } else {
            break;
        }
    }

    // Strip trailing whitespace (ASCII and common Unicode)
    while (s.len > 0) {
        const last = s[s.len - 1];
        if (last == ' ' or last == '\t' or last == '\n' or last == '\r') {
            s = s[0 .. s.len - 1];
        } else if (s.len >= 3) {
            const tail = s[s.len - 3 ..];
            if (tail[0] == 0xE2) {
                if ((tail[1] == 0x80 and tail[2] >= 0x80 and tail[2] <= 0x8A) or
                    (tail[1] == 0x80 and (tail[2] == 0xA8 or tail[2] == 0xA9 or tail[2] == 0xAF)) or
                    (tail[1] == 0x81 and tail[2] == 0x9F))
                {
                    s = s[0 .. s.len - 3];
                } else {
                    break;
                }
            } else if (tail[0] == 0xE3 and tail[1] == 0x80 and tail[2] == 0x80) {
                s = s[0 .. s.len - 3];
            } else {
                break;
            }
        } else {
            break;
        }
    }

    // Handle negative
    const is_negative = s.len > 0 and s[0] == '-';
    if (is_negative) s = s[1..];

    // Handle positive sign
    const is_positive = s.len > 0 and s[0] == '+';
    if (is_positive) s = s[1..];

    // Actual base to use (0 = auto-detect)
    var actual_base: u8 = base;

    // Handle base prefixes (when base is 0 or matches the prefix)
    if (s.len >= 2) {
        if ((base == 0 or base == 16) and (std.mem.startsWith(u8, s, "0x") or std.mem.startsWith(u8, s, "0X"))) {
            actual_base = 16;
            s = s[2..];
        } else if ((base == 0 or base == 8) and (std.mem.startsWith(u8, s, "0o") or std.mem.startsWith(u8, s, "0O"))) {
            actual_base = 8;
            s = s[2..];
        } else if ((base == 0 or base == 2) and (std.mem.startsWith(u8, s, "0b") or std.mem.startsWith(u8, s, "0B"))) {
            actual_base = 2;
            s = s[2..];
        } else if (base == 0) {
            actual_base = 10;
        }
    } else if (base == 0) {
        actual_base = 10;
    }

    // Empty string after stripping is invalid
    if (s.len == 0) return error.ValueError;

    // Try standard ASCII parsing first
    var result = BigInt.fromString(allocator, s, actual_base) catch {
        // If that fails, try converting Unicode digits to ASCII
        const ascii_str = convertUnicodeDigitsToAscii(allocator, s) catch return error.ValueError;
        defer allocator.free(ascii_str);

        var r = BigInt.fromString(allocator, ascii_str, actual_base) catch return error.ValueError;
        if (is_negative) r.negate();
        return r;
    };
    if (is_negative) result.negate();
    return result;
}

/// Convert Unicode digit characters to ASCII digits
/// Handles Devanagari (0x0966-0x096F), Arabic-Indic (0x0660-0x0669), etc.
fn convertUnicodeDigitsToAscii(allocator: Allocator, str: []const u8) ![]u8 {
    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < str.len) {
        const byte = str[i];

        // Skip underscores (Python allows 1_000_000)
        if (byte == '_') {
            i += 1;
            continue;
        }

        // ASCII digit
        if (byte >= '0' and byte <= '9') {
            try result.append(allocator, byte);
            i += 1;
            continue;
        }

        // Check for multi-byte Unicode digit
        const cp_len = std.unicode.utf8ByteSequenceLength(byte) catch return error.ValueError;
        if (i + cp_len > str.len) return error.ValueError;

        const codepoint = std.unicode.utf8Decode(str[i..][0..cp_len]) catch return error.ValueError;

        // Check various Unicode digit ranges and convert to '0'-'9'
        const digit: ?u8 = blk: {
            // Devanagari digits (Hindi): U+0966 to U+096F
            if (codepoint >= 0x0966 and codepoint <= 0x096F) break :blk @intCast(codepoint - 0x0966);
            // Arabic-Indic digits: U+0660 to U+0669
            if (codepoint >= 0x0660 and codepoint <= 0x0669) break :blk @intCast(codepoint - 0x0660);
            // Extended Arabic-Indic: U+06F0 to U+06F9
            if (codepoint >= 0x06F0 and codepoint <= 0x06F9) break :blk @intCast(codepoint - 0x06F0);
            // Bengali digits: U+09E6 to U+09EF
            if (codepoint >= 0x09E6 and codepoint <= 0x09EF) break :blk @intCast(codepoint - 0x09E6);
            // Gurmukhi digits: U+0A66 to U+0A6F
            if (codepoint >= 0x0A66 and codepoint <= 0x0A6F) break :blk @intCast(codepoint - 0x0A66);
            // Gujarati digits: U+0AE6 to U+0AEF
            if (codepoint >= 0x0AE6 and codepoint <= 0x0AEF) break :blk @intCast(codepoint - 0x0AE6);
            // Oriya digits: U+0B66 to U+0B6F
            if (codepoint >= 0x0B66 and codepoint <= 0x0B6F) break :blk @intCast(codepoint - 0x0B66);
            // Tamil digits: U+0BE6 to U+0BEF
            if (codepoint >= 0x0BE6 and codepoint <= 0x0BEF) break :blk @intCast(codepoint - 0x0BE6);
            // Telugu digits: U+0C66 to U+0C6F
            if (codepoint >= 0x0C66 and codepoint <= 0x0C6F) break :blk @intCast(codepoint - 0x0C66);
            // Kannada digits: U+0CE6 to U+0CEF
            if (codepoint >= 0x0CE6 and codepoint <= 0x0CEF) break :blk @intCast(codepoint - 0x0CE6);
            // Malayalam digits: U+0D66 to U+0D6F
            if (codepoint >= 0x0D66 and codepoint <= 0x0D6F) break :blk @intCast(codepoint - 0x0D66);
            // Thai digits: U+0E50 to U+0E59
            if (codepoint >= 0x0E50 and codepoint <= 0x0E59) break :blk @intCast(codepoint - 0x0E50);
            // Lao digits: U+0ED0 to U+0ED9
            if (codepoint >= 0x0ED0 and codepoint <= 0x0ED9) break :blk @intCast(codepoint - 0x0ED0);
            // Tibetan digits: U+0F20 to U+0F29
            if (codepoint >= 0x0F20 and codepoint <= 0x0F29) break :blk @intCast(codepoint - 0x0F20);
            // Myanmar digits: U+1040 to U+1049
            if (codepoint >= 0x1040 and codepoint <= 0x1049) break :blk @intCast(codepoint - 0x1040);
            // Fullwidth digits: U+FF10 to U+FF19
            if (codepoint >= 0xFF10 and codepoint <= 0xFF19) break :blk @intCast(codepoint - 0xFF10);
            break :blk null;
        };

        if (digit) |d| {
            try result.append(allocator, '0' + d);
        } else {
            return error.ValueError;
        }
        i += cp_len;
    }

    return result.toOwnedSlice(allocator);
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
