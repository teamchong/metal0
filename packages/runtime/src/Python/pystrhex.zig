/// pystrhex - Python String Hex Conversion
/// Mirrors cpython/Python/pystrhex.c
///
/// This module provides hex encoding/decoding for bytes:
/// - Convert bytes to hex string
/// - Convert hex string to bytes
/// - Support for separators and case options

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Hex Tables
// ============================================================================

/// Lowercase hex characters
const hex_lower: [16]u8 = "0123456789abcdef".*;

/// Uppercase hex characters
const hex_upper: [16]u8 = "0123456789ABCDEF".*;

/// Hex value lookup table (256 entries, 255 = invalid)
const hex_values: [256]u8 = init: {
    var table: [256]u8 = [_]u8{255} ** 256;

    // Digits 0-9
    for ('0'..'9' + 1) |c| {
        table[c] = @intCast(c - '0');
    }

    // Lowercase a-f
    for ('a'..'f' + 1) |c| {
        table[c] = @intCast(c - 'a' + 10);
    }

    // Uppercase A-F
    for ('A'..'F' + 1) |c| {
        table[c] = @intCast(c - 'A' + 10);
    }

    break :init table;
};

// ============================================================================
// Hex Encoding
// ============================================================================

/// Encode bytes to hex string (lowercase)
pub fn bytesToHex(allocator: Allocator, bytes: []const u8) ![]u8 {
    return bytesToHexWithOptions(allocator, bytes, .{});
}

/// Encode bytes to hex string (uppercase)
pub fn bytesToHexUpper(allocator: Allocator, bytes: []const u8) ![]u8 {
    return bytesToHexWithOptions(allocator, bytes, .{ .uppercase = true });
}

/// Hex encoding options
pub const HexOptions = struct {
    uppercase: bool = false,
    separator: ?u8 = null,
    bytes_per_sep: usize = 1,
};

/// Encode bytes to hex with options
pub fn bytesToHexWithOptions(allocator: Allocator, bytes: []const u8, options: HexOptions) ![]u8 {
    if (bytes.len == 0) {
        return try allocator.alloc(u8, 0);
    }

    const table = if (options.uppercase) hex_upper else hex_lower;

    // Calculate output size
    var size = bytes.len * 2;
    if (options.separator) |_| {
        // Add separators between groups
        const num_groups = (bytes.len + options.bytes_per_sep - 1) / options.bytes_per_sep;
        if (num_groups > 1) {
            size += num_groups - 1;
        }
    }

    var result = try allocator.alloc(u8, size);
    var out_idx: usize = 0;
    var bytes_in_group: usize = 0;

    for (bytes, 0..) |byte, i| {
        // Add separator if needed
        if (options.separator) |sep| {
            if (i > 0 and bytes_in_group == 0) {
                result[out_idx] = sep;
                out_idx += 1;
            }
        }

        result[out_idx] = table[byte >> 4];
        result[out_idx + 1] = table[byte & 0x0F];
        out_idx += 2;

        bytes_in_group += 1;
        if (bytes_in_group >= options.bytes_per_sep) {
            bytes_in_group = 0;
        }
    }

    return result;
}

/// Encode to hex into existing buffer
pub fn bytesToHexBuf(bytes: []const u8, buf: []u8) !usize {
    if (buf.len < bytes.len * 2) {
        return error.BufferTooSmall;
    }

    for (bytes, 0..) |byte, i| {
        buf[i * 2] = hex_lower[byte >> 4];
        buf[i * 2 + 1] = hex_lower[byte & 0x0F];
    }

    return bytes.len * 2;
}

// ============================================================================
// Hex Decoding
// ============================================================================

pub const HexError = error{
    InvalidHexCharacter,
    OddLength,
    OutOfMemory,
    BufferTooSmall,
};

/// Decode hex string to bytes
pub fn hexToBytes(allocator: Allocator, hex: []const u8) HexError![]u8 {
    if (hex.len == 0) {
        return try allocator.alloc(u8, 0);
    }

    if (hex.len % 2 != 0) {
        return HexError.OddLength;
    }

    var result = allocator.alloc(u8, hex.len / 2) catch return HexError.OutOfMemory;
    errdefer allocator.free(result);

    var i: usize = 0;
    while (i < hex.len) : (i += 2) {
        const high = hex_values[hex[i]];
        const low = hex_values[hex[i + 1]];

        if (high == 255 or low == 255) {
            allocator.free(result);
            return HexError.InvalidHexCharacter;
        }

        result[i / 2] = (high << 4) | low;
    }

    return result;
}

/// Decode hex into existing buffer
pub fn hexToBytesBuf(hex: []const u8, buf: []u8) HexError!usize {
    if (hex.len == 0) return 0;

    if (hex.len % 2 != 0) {
        return HexError.OddLength;
    }

    if (buf.len < hex.len / 2) {
        return HexError.BufferTooSmall;
    }

    var i: usize = 0;
    while (i < hex.len) : (i += 2) {
        const high = hex_values[hex[i]];
        const low = hex_values[hex[i + 1]];

        if (high == 255 or low == 255) {
            return HexError.InvalidHexCharacter;
        }

        buf[i / 2] = (high << 4) | low;
    }

    return hex.len / 2;
}

// ============================================================================
// Validation
// ============================================================================

/// Check if character is a hex digit
pub fn isHexDigit(c: u8) bool {
    return hex_values[c] != 255;
}

/// Check if string is valid hex
pub fn isValidHex(s: []const u8) bool {
    if (s.len % 2 != 0) return false;

    for (s) |c| {
        if (!isHexDigit(c)) return false;
    }
    return true;
}

/// Get hex digit value (0-15) or null if invalid
pub fn hexDigitValue(c: u8) ?u8 {
    const v = hex_values[c];
    return if (v == 255) null else v;
}

// ============================================================================
// Formatting Helpers
// ============================================================================

/// Format byte as hex (2 characters)
pub fn formatByte(byte: u8) [2]u8 {
    return .{
        hex_lower[byte >> 4],
        hex_lower[byte & 0x0F],
    };
}

/// Format byte as hex uppercase
pub fn formatByteUpper(byte: u8) [2]u8 {
    return .{
        hex_upper[byte >> 4],
        hex_upper[byte & 0x0F],
    };
}

/// Format integer as hex string
pub fn formatInt(allocator: Allocator, value: u64) ![]u8 {
    if (value == 0) {
        var result = try allocator.alloc(u8, 1);
        result[0] = '0';
        return result;
    }

    // Count hex digits
    var v = value;
    var digits: usize = 0;
    while (v > 0) {
        digits += 1;
        v >>= 4;
    }

    var result = try allocator.alloc(u8, digits);
    v = value;
    var i: usize = digits;
    while (v > 0) {
        i -= 1;
        result[i] = hex_lower[@intCast(v & 0xF)];
        v >>= 4;
    }

    return result;
}

// ============================================================================
// Python API Compatibility
// ============================================================================

/// _Py_strhex (lowercase)
pub fn _Py_strhex(bytes: []const u8, buf: []u8) !usize {
    return bytesToHexBuf(bytes, buf);
}

/// _Py_strhex_bytes (return allocated)
pub fn _Py_strhex_bytes(allocator: Allocator, bytes: []const u8) ![]u8 {
    return bytesToHex(allocator, bytes);
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "bytes to hex" {
    const result = try bytesToHex(std.testing.allocator, &[_]u8{ 0xde, 0xad, 0xbe, 0xef });
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("deadbeef", result);
}

test "bytes to hex upper" {
    const result = try bytesToHexUpper(std.testing.allocator, &[_]u8{ 0xde, 0xad, 0xbe, 0xef });
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("DEADBEEF", result);
}

test "bytes to hex with separator" {
    const result = try bytesToHexWithOptions(
        std.testing.allocator,
        &[_]u8{ 0xde, 0xad, 0xbe, 0xef },
        .{ .separator = ':', .bytes_per_sep = 1 },
    );
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("de:ad:be:ef", result);
}

test "hex to bytes" {
    const result = try hexToBytes(std.testing.allocator, "deadbeef");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xde, 0xad, 0xbe, 0xef }, result);
}

test "hex to bytes uppercase" {
    const result = try hexToBytes(std.testing.allocator, "DEADBEEF");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xde, 0xad, 0xbe, 0xef }, result);
}

test "hex to bytes invalid" {
    try std.testing.expectError(HexError.InvalidHexCharacter, hexToBytes(std.testing.allocator, "ghij"));
    try std.testing.expectError(HexError.OddLength, hexToBytes(std.testing.allocator, "abc"));
}

test "isHexDigit" {
    try std.testing.expect(isHexDigit('0'));
    try std.testing.expect(isHexDigit('9'));
    try std.testing.expect(isHexDigit('a'));
    try std.testing.expect(isHexDigit('f'));
    try std.testing.expect(isHexDigit('A'));
    try std.testing.expect(isHexDigit('F'));
    try std.testing.expect(!isHexDigit('g'));
    try std.testing.expect(!isHexDigit('G'));
}

test "isValidHex" {
    try std.testing.expect(isValidHex("deadbeef"));
    try std.testing.expect(isValidHex("DEADBEEF"));
    try std.testing.expect(isValidHex("DeAdBeEf"));
    try std.testing.expect(!isValidHex("abc")); // odd length
    try std.testing.expect(!isValidHex("ghij")); // invalid chars
}

test "formatByte" {
    try std.testing.expectEqualSlices(u8, "ff", &formatByte(0xFF));
    try std.testing.expectEqualSlices(u8, "00", &formatByte(0x00));
    try std.testing.expectEqualSlices(u8, "a5", &formatByte(0xA5));
}

test "formatInt" {
    const r1 = try formatInt(std.testing.allocator, 255);
    defer std.testing.allocator.free(r1);
    try std.testing.expectEqualStrings("ff", r1);

    const r2 = try formatInt(std.testing.allocator, 0);
    defer std.testing.allocator.free(r2);
    try std.testing.expectEqualStrings("0", r2);

    const r3 = try formatInt(std.testing.allocator, 0xDEADBEEF);
    defer std.testing.allocator.free(r3);
    try std.testing.expectEqualStrings("deadbeef", r3);
}

test "empty input" {
    const r1 = try bytesToHex(std.testing.allocator, &[_]u8{});
    defer std.testing.allocator.free(r1);
    try std.testing.expectEqual(@as(usize, 0), r1.len);

    const r2 = try hexToBytes(std.testing.allocator, "");
    defer std.testing.allocator.free(r2);
    try std.testing.expectEqual(@as(usize, 0), r2.len);
}
