/// mysnprintf - Safe sprintf Wrappers
/// Mirrors cpython/Python/mysnprintf.c
///
/// This module provides safe snprintf/vsnprintf wrappers that:
/// - Always null-terminate the buffer
/// - Return consistent values across platforms
/// - Handle buffer size edge cases

const std = @import("std");

// ============================================================================
// Main Functions
// ============================================================================

/// Safe snprintf wrapper
/// Returns number of characters written (excluding null terminator)
/// or negative on error. Buffer is always null-terminated.
pub fn snprintf(buf: []u8, comptime fmt: []const u8, args: anytype) i32 {
    if (buf.len == 0) {
        return -1;
    }

    const result = std.fmt.bufPrint(buf[0 .. buf.len - 1], fmt, args) catch {
        // Truncated - fill what we can
        buf[buf.len - 1] = 0;
        return @intCast(buf.len - 1);
    };

    // Null terminate
    if (result.len < buf.len) {
        buf[result.len] = 0;
    } else {
        buf[buf.len - 1] = 0;
    }

    return @intCast(result.len);
}

/// Safe string copy with length limit
pub fn strncpy(dest: []u8, src: []const u8) usize {
    const copy_len = @min(dest.len - 1, src.len);
    @memcpy(dest[0..copy_len], src[0..copy_len]);
    dest[copy_len] = 0;
    return copy_len;
}

/// Safe string concatenation with length limit
pub fn strncat(dest: []u8, src: []const u8) usize {
    // Find current string end
    var dest_len: usize = 0;
    while (dest_len < dest.len and dest[dest_len] != 0) {
        dest_len += 1;
    }

    // Calculate space remaining
    const remaining = dest.len - dest_len;
    if (remaining <= 1) {
        return dest_len;
    }

    // Copy src
    const copy_len = @min(remaining - 1, src.len);
    @memcpy(dest[dest_len .. dest_len + copy_len], src[0..copy_len]);
    dest[dest_len + copy_len] = 0;

    return dest_len + copy_len;
}

// ============================================================================
// Format Functions
// ============================================================================

/// Format integer to buffer
pub fn formatInt(buf: []u8, value: i64) i32 {
    return snprintf(buf, "{d}", .{value});
}

/// Format unsigned integer to buffer
pub fn formatUint(buf: []u8, value: u64) i32 {
    return snprintf(buf, "{d}", .{value});
}

/// Format float to buffer
pub fn formatFloat(buf: []u8, value: f64) i32 {
    return snprintf(buf, "{d}", .{value});
}

/// Format hex to buffer (lowercase)
pub fn formatHex(buf: []u8, value: u64) i32 {
    return snprintf(buf, "{x}", .{value});
}

/// Format hex to buffer (uppercase)
pub fn formatHexUpper(buf: []u8, value: u64) i32 {
    return snprintf(buf, "{X}", .{value});
}

/// Format pointer to buffer
pub fn formatPtr(buf: []u8, ptr: ?*const anyopaque) i32 {
    if (ptr) |p| {
        return snprintf(buf, "0x{x}", .{@intFromPtr(p)});
    } else {
        return snprintf(buf, "(nil)", .{});
    }
}

/// Format string to buffer with width
pub fn formatString(buf: []u8, str: []const u8) i32 {
    return snprintf(buf, "{s}", .{str});
}

// ============================================================================
// Buffer Writer
// ============================================================================

/// Writer that writes to a fixed buffer, tracking position
pub const BufferWriter = struct {
    buf: []u8,
    pos: usize = 0,

    const Self = @This();

    pub fn init(buf: []u8) Self {
        return .{ .buf = buf };
    }

    /// Write string to buffer
    pub fn write(self: *Self, str: []const u8) void {
        if (self.pos >= self.buf.len - 1) return;

        const remaining = self.buf.len - 1 - self.pos;
        const copy_len = @min(remaining, str.len);

        @memcpy(self.buf[self.pos .. self.pos + copy_len], str[0..copy_len]);
        self.pos += copy_len;
        self.buf[self.pos] = 0;
    }

    /// Write formatted value to buffer
    pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) void {
        if (self.pos >= self.buf.len - 1) return;

        const remaining = self.buf.len - 1 - self.pos;
        const result = std.fmt.bufPrint(self.buf[self.pos..][0..remaining], fmt, args) catch {
            // Truncated
            self.pos = self.buf.len - 1;
            self.buf[self.pos] = 0;
            return;
        };
        self.pos += result.len;
        self.buf[self.pos] = 0;
    }

    /// Write single character
    pub fn writeChar(self: *Self, c: u8) void {
        if (self.pos < self.buf.len - 1) {
            self.buf[self.pos] = c;
            self.pos += 1;
            self.buf[self.pos] = 0;
        }
    }

    /// Get current string
    pub fn getWritten(self: Self) []const u8 {
        return self.buf[0..self.pos];
    }

    /// Get remaining capacity
    pub fn remaining(self: Self) usize {
        if (self.pos >= self.buf.len - 1) return 0;
        return self.buf.len - 1 - self.pos;
    }

    /// Reset to beginning
    pub fn reset(self: *Self) void {
        self.pos = 0;
        if (self.buf.len > 0) {
            self.buf[0] = 0;
        }
    }
};

// ============================================================================
// Utility Functions
// ============================================================================

/// Calculate buffer size needed for integer
pub fn intDigits(value: i64) usize {
    if (value == 0) return 1;

    var v = if (value < 0) -value else value;
    var digits: usize = if (value < 0) 1 else 0; // space for minus sign

    while (v > 0) {
        digits += 1;
        v = @divTrunc(v, 10);
    }

    return digits;
}

/// Calculate buffer size needed for unsigned integer
pub fn uintDigits(value: u64) usize {
    if (value == 0) return 1;

    var v = value;
    var digits: usize = 0;

    while (v > 0) {
        digits += 1;
        v = v / 10;
    }

    return digits;
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "snprintf basic" {
    var buf: [32]u8 = undefined;

    const n1 = snprintf(&buf, "hello", .{});
    try std.testing.expectEqual(@as(i32, 5), n1);
    try std.testing.expectEqualStrings("hello", buf[0..5]);
}

test "snprintf int" {
    var buf: [32]u8 = undefined;

    const n1 = snprintf(&buf, "{d}", .{@as(i32, 42)});
    try std.testing.expectEqual(@as(i32, 2), n1);
    try std.testing.expectEqualStrings("42", buf[0..2]);
}

test "snprintf truncation" {
    var buf: [5]u8 = undefined;

    const n1 = snprintf(&buf, "hello world", .{});
    try std.testing.expectEqual(@as(i32, 4), n1);
    try std.testing.expectEqual(@as(u8, 0), buf[4]);
}

test "strncpy" {
    var buf: [10]u8 = undefined;

    const n1 = strncpy(&buf, "hello");
    try std.testing.expectEqual(@as(usize, 5), n1);
    try std.testing.expectEqualStrings("hello", buf[0..5]);
}

test "strncat" {
    var buf: [20]u8 = undefined;
    _ = strncpy(&buf, "hello");

    const n1 = strncat(&buf, " world");
    try std.testing.expectEqual(@as(usize, 11), n1);
    try std.testing.expectEqualStrings("hello world", buf[0..11]);
}

test "buffer writer" {
    var buf: [32]u8 = undefined;
    var writer = BufferWriter.init(&buf);

    writer.write("hello");
    writer.writeChar(' ');
    writer.print("{d}", .{@as(i32, 42)});

    try std.testing.expectEqualStrings("hello 42", writer.getWritten());
}

test "int digits" {
    try std.testing.expectEqual(@as(usize, 1), intDigits(0));
    try std.testing.expectEqual(@as(usize, 1), intDigits(5));
    try std.testing.expectEqual(@as(usize, 2), intDigits(42));
    try std.testing.expectEqual(@as(usize, 3), intDigits(100));
    try std.testing.expectEqual(@as(usize, 2), intDigits(-5));
    try std.testing.expectEqual(@as(usize, 4), intDigits(-100));
}

test "format functions" {
    var buf: [32]u8 = undefined;

    _ = formatInt(&buf, -42);
    try std.testing.expectEqualStrings("-42", buf[0..3]);

    _ = formatUint(&buf, 255);
    try std.testing.expectEqualStrings("255", buf[0..3]);

    _ = formatHex(&buf, 255);
    try std.testing.expectEqualStrings("ff", buf[0..2]);

    _ = formatHexUpper(&buf, 255);
    try std.testing.expectEqualStrings("FF", buf[0..2]);
}
