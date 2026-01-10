//! test.test_ctypes.test_bytes - Tests for ctypes byte handling
//! Reference: cpython/Lib/test/test_ctypes/test_bytes.py
//!
//! Tests for byte array and bytes handling in ctypes including
//! string conversions, encoding, and raw byte manipulation.

const std = @import("std");
const _support = @import("_support.zig");

// ============================================================================
// Byte Types
// ============================================================================

/// c_char type for single bytes
pub const c_char = struct {
    const Self = @This();

    value: u8 = 0,

    pub fn init(v: u8) Self {
        return .{ .value = v };
    }

    pub fn fromChar(c: u8) Self {
        return .{ .value = c };
    }

    pub fn toChar(self: Self) u8 {
        return self.value;
    }
};

/// c_byte type (signed)
pub const c_byte = struct {
    const Self = @This();

    value: i8 = 0,

    pub fn init(v: i8) Self {
        return .{ .value = v };
    }
};

/// c_ubyte type (unsigned)
pub const c_ubyte = struct {
    const Self = @This();

    value: u8 = 0,

    pub fn init(v: u8) Self {
        return .{ .value = v };
    }
};

// ============================================================================
// Byte Array Types
// ============================================================================

/// Fixed-size byte array
pub fn ByteArray(comptime N: usize) type {
    return struct {
        const Self = @This();
        pub const length = N;

        data: [N]u8 = undefined,

        pub fn init() Self {
            var self = Self{};
            @memset(&self.data, 0);
            return self;
        }

        pub fn fromBytes(bytes: []const u8) Self {
            var self = Self.init();
            const len = @min(bytes.len, N);
            @memcpy(self.data[0..len], bytes[0..len]);
            return self;
        }

        pub fn fromString(s: []const u8) Self {
            return fromBytes(s);
        }

        /// Get value as string (up to null terminator)
        pub fn value(self: *const Self) []const u8 {
            var end: usize = 0;
            while (end < N and self.data[end] != 0) : (end += 1) {}
            return self.data[0..end];
        }

        /// Get raw bytes
        pub fn raw(self: *const Self) []const u8 {
            return &self.data;
        }

        /// Set from bytes
        pub fn set(self: *Self, bytes: []const u8) void {
            @memset(&self.data, 0);
            const len = @min(bytes.len, N);
            @memcpy(self.data[0..len], bytes[0..len]);
        }

        /// Get byte at index
        pub fn get(self: *const Self, index: usize) ?u8 {
            if (index >= N) return null;
            return self.data[index];
        }

        /// Set byte at index
        pub fn setByte(self: *Self, index: usize, byte: u8) bool {
            if (index >= N) return false;
            self.data[index] = byte;
            return true;
        }
    };
}

// ============================================================================
// Byte Operations
// ============================================================================

/// Convert bytes to hex string
pub fn bytesToHex(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const hex_chars = "0123456789abcdef";
    var result = try allocator.alloc(u8, bytes.len * 2);
    for (bytes, 0..) |b, i| {
        result[i * 2] = hex_chars[b >> 4];
        result[i * 2 + 1] = hex_chars[b & 0x0F];
    }
    return result;
}

/// Convert hex string to bytes
pub fn hexToBytes(allocator: std.mem.Allocator, hex: []const u8) ![]u8 {
    if (hex.len % 2 != 0) return error.InvalidHexLength;
    var result = try allocator.alloc(u8, hex.len / 2);
    errdefer allocator.free(result);

    for (0..result.len) |i| {
        const high = try hexCharToNibble(hex[i * 2]);
        const low = try hexCharToNibble(hex[i * 2 + 1]);
        result[i] = (high << 4) | low;
    }
    return result;
}

fn hexCharToNibble(c: u8) !u4 {
    return switch (c) {
        '0'...'9' => @intCast(c - '0'),
        'a'...'f' => @intCast(c - 'a' + 10),
        'A'...'F' => @intCast(c - 'A' + 10),
        else => error.InvalidHexChar,
    };
}

/// Escape bytes for display
pub fn escapeBytes(bytes: []const u8, buf: []u8) usize {
    var pos: usize = 0;
    for (bytes) |b| {
        if (pos + 4 > buf.len) break;
        if (b >= 32 and b < 127 and b != '\\') {
            buf[pos] = b;
            pos += 1;
        } else {
            buf[pos] = '\\';
            buf[pos + 1] = 'x';
            const hex_chars = "0123456789abcdef";
            buf[pos + 2] = hex_chars[b >> 4];
            buf[pos + 3] = hex_chars[b & 0x0F];
            pos += 4;
        }
    }
    return pos;
}

// ============================================================================
// Test Types
// ============================================================================

pub const Bytes16 = ByteArray(16);
pub const Bytes64 = ByteArray(64);
pub const Bytes256 = ByteArray(256);

// ============================================================================
// Test Cases
// ============================================================================

fn testCChar() !void {
    const c = c_char.fromChar('A');
    try std.testing.expectEqual(@as(u8, 'A'), c.toChar());
    try std.testing.expectEqual(@as(u8, 65), c.value);
}

fn testCByte() !void {
    const b = c_byte.init(-1);
    try std.testing.expectEqual(@as(i8, -1), b.value);

    const ub = c_ubyte.init(255);
    try std.testing.expectEqual(@as(u8, 255), ub.value);
}

fn testByteArrayInit() !void {
    const arr = Bytes16.init();
    for (arr.data) |b| {
        try std.testing.expectEqual(@as(u8, 0), b);
    }
}

fn testByteArrayFromString() !void {
    const arr = Bytes16.fromString("Hello");
    try std.testing.expectEqualStrings("Hello", arr.value());
}

fn testByteArrayTruncation() !void {
    // String longer than array
    const arr = Bytes16.fromString("This is a very long string that exceeds 16 bytes");
    try std.testing.expectEqual(@as(usize, 16), arr.raw().len);
}

fn testByteArraySetGet() !void {
    var arr = Bytes16.init();
    try std.testing.expect(arr.setByte(0, 0xAA));
    try std.testing.expect(arr.setByte(15, 0xBB));
    try std.testing.expect(!arr.setByte(16, 0xCC)); // Out of bounds

    try std.testing.expectEqual(@as(?u8, 0xAA), arr.get(0));
    try std.testing.expectEqual(@as(?u8, 0xBB), arr.get(15));
    try std.testing.expectEqual(@as(?u8, null), arr.get(16));
}

fn testBytesToHex() !void {
    const allocator = std.testing.allocator;
    const bytes = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF };
    const hex = try bytesToHex(allocator, &bytes);
    defer allocator.free(hex);

    try std.testing.expectEqualStrings("deadbeef", hex);
}

fn testHexToBytes() !void {
    const allocator = std.testing.allocator;
    const bytes = try hexToBytes(allocator, "cafebabe");
    defer allocator.free(bytes);

    try std.testing.expectEqual(@as(u8, 0xCA), bytes[0]);
    try std.testing.expectEqual(@as(u8, 0xFE), bytes[1]);
    try std.testing.expectEqual(@as(u8, 0xBA), bytes[2]);
    try std.testing.expectEqual(@as(u8, 0xBE), bytes[3]);
}

fn testHexRoundtrip() !void {
    const allocator = std.testing.allocator;
    const original = [_]u8{ 0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF };

    const hex = try bytesToHex(allocator, &original);
    defer allocator.free(hex);

    const bytes = try hexToBytes(allocator, hex);
    defer allocator.free(bytes);

    try std.testing.expectEqualSlices(u8, &original, bytes);
}

fn testEscapeBytes() !void {
    var buf: [64]u8 = undefined;

    // Printable chars stay as-is
    const len1 = escapeBytes("ABC", &buf);
    try std.testing.expectEqualStrings("ABC", buf[0..len1]);

    // Non-printable chars get escaped
    const len2 = escapeBytes(&[_]u8{ 0x00, 0x01, 0x02 }, &buf);
    try std.testing.expectEqualStrings("\\x00\\x01\\x02", buf[0..len2]);
}

fn testByteArrayRaw() !void {
    var arr = Bytes16.fromString("Test");
    arr.data[5] = 0xFF; // Set a byte after the string

    // value() stops at null
    try std.testing.expectEqualStrings("Test", arr.value());

    // raw() returns all bytes
    try std.testing.expectEqual(@as(usize, 16), arr.raw().len);
    try std.testing.expectEqual(@as(u8, 0xFF), arr.raw()[5]);
}

fn testInvalidHex() !void {
    const allocator = std.testing.allocator;

    // Invalid length
    try std.testing.expectError(error.InvalidHexLength, hexToBytes(allocator, "abc"));

    // Invalid character
    try std.testing.expectError(error.InvalidHexChar, hexToBytes(allocator, "gg"));
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "c_char" {
    try testCChar();
}

test "c_byte" {
    try testCByte();
}

test "byte_array_init" {
    try testByteArrayInit();
}

test "byte_array_from_string" {
    try testByteArrayFromString();
}

test "byte_array_truncation" {
    try testByteArrayTruncation();
}

test "byte_array_set_get" {
    try testByteArraySetGet();
}

test "bytes_to_hex" {
    try testBytesToHex();
}

test "hex_to_bytes" {
    try testHexToBytes();
}

test "hex_roundtrip" {
    try testHexRoundtrip();
}

test "escape_bytes" {
    try testEscapeBytes();
}

test "byte_array_raw" {
    try testByteArrayRaw();
}

test "invalid_hex" {
    try testInvalidHex();
}
