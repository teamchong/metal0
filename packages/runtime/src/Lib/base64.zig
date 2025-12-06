/// Base64 - Python-compatible base64 encoding/decoding
/// Pure Zig implementation using std.base64
const std = @import("std");

// ============================================================================
// Standard Base64 (RFC 4648)
// ============================================================================

/// Encode bytes to base64 string
pub fn b64encode(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const encoder = std.base64.standard.Encoder;
    const len = encoder.calcSize(data.len);
    const buf = try allocator.alloc(u8, len);
    _ = encoder.encode(buf, data);
    return buf;
}

/// Decode base64 string to bytes
pub fn b64decode(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const decoder = std.base64.standard.Decoder;
    // Strip whitespace first
    var clean = std.ArrayList(u8){};
    defer clean.deinit(allocator);
    for (data) |c| {
        if (c != ' ' and c != '\n' and c != '\r' and c != '\t') {
            try clean.append(allocator, c);
        }
    }
    const len = try decoder.calcSizeForSlice(clean.items);
    const buf = try allocator.alloc(u8, len);
    try decoder.decode(buf, clean.items);
    return buf;
}

/// Alias for b64encode
pub const standard_b64encode = b64encode;

/// Alias for b64decode
pub const standard_b64decode = b64decode;

// ============================================================================
// URL-safe Base64 (RFC 4648 §5)
// ============================================================================

/// Encode bytes to URL-safe base64 string
pub fn urlsafe_b64encode(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const encoder = std.base64.url_safe.Encoder;
    const len = encoder.calcSize(data.len);
    const buf = try allocator.alloc(u8, len);
    _ = encoder.encode(buf, data);
    return buf;
}

/// Decode URL-safe base64 string to bytes
pub fn urlsafe_b64decode(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const decoder = std.base64.url_safe.Decoder;
    const len = try decoder.calcSizeForSlice(data);
    const buf = try allocator.alloc(u8, len);
    try decoder.decode(buf, data);
    return buf;
}

// ============================================================================
// encodebytes/decodebytes (legacy, with newlines)
// ============================================================================

/// Encode bytes to base64 with newlines every 76 chars
pub fn encodebytes(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const raw = try b64encode(allocator, data);
    defer allocator.free(raw);

    // Count how many newlines we need
    const num_lines = (raw.len + 75) / 76;
    const result_len = raw.len + num_lines;
    const result = try allocator.alloc(u8, result_len);

    var src_pos: usize = 0;
    var dst_pos: usize = 0;
    while (src_pos < raw.len) {
        const chunk_end = @min(src_pos + 76, raw.len);
        const chunk_len = chunk_end - src_pos;
        @memcpy(result[dst_pos .. dst_pos + chunk_len], raw[src_pos..chunk_end]);
        dst_pos += chunk_len;
        result[dst_pos] = '\n';
        dst_pos += 1;
        src_pos = chunk_end;
    }

    return result[0..dst_pos];
}

/// Decode base64 with optional whitespace
pub const decodebytes = b64decode;

// ============================================================================
// Base16 (Hex encoding)
// ============================================================================

/// Encode bytes to uppercase hex string
pub fn b16encode(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    const hex_chars = "0123456789ABCDEF";
    const buf = try allocator.alloc(u8, data.len * 2);
    for (data, 0..) |byte, i| {
        buf[i * 2] = hex_chars[byte >> 4];
        buf[i * 2 + 1] = hex_chars[byte & 0x0f];
    }
    return buf;
}

/// Decode hex string to bytes
pub fn b16decode(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    if (data.len % 2 != 0) return error.InvalidLength;
    const buf = try allocator.alloc(u8, data.len / 2);
    errdefer allocator.free(buf);

    for (0..buf.len) |i| {
        const hi = hexCharToNibble(data[i * 2]) orelse return error.InvalidCharacter;
        const lo = hexCharToNibble(data[i * 2 + 1]) orelse return error.InvalidCharacter;
        buf[i] = (hi << 4) | lo;
    }
    return buf;
}

fn hexCharToNibble(c: u8) ?u4 {
    return switch (c) {
        '0'...'9' => @intCast(c - '0'),
        'A'...'F' => @intCast(c - 'A' + 10),
        'a'...'f' => @intCast(c - 'a' + 10),
        else => null,
    };
}

// ============================================================================
// Base32 (RFC 4648)
// ============================================================================

const base32_alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
const base32_pad = '=';

/// Encode bytes to base32 string
pub fn b32encode(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    if (data.len == 0) return try allocator.alloc(u8, 0);

    // Calculate output length: ceil(len * 8 / 5), padded to multiple of 8
    const bits = data.len * 8;
    const out_chars = (bits + 4) / 5;
    const padded_len = ((out_chars + 7) / 8) * 8;
    const buf = try allocator.alloc(u8, padded_len);

    var bit_buffer: u64 = 0;
    var bits_in_buffer: u6 = 0;
    var out_pos: usize = 0;

    for (data) |byte| {
        bit_buffer = (bit_buffer << 8) | byte;
        bits_in_buffer += 8;

        while (bits_in_buffer >= 5) {
            bits_in_buffer -= 5;
            const idx: u5 = @intCast((bit_buffer >> bits_in_buffer) & 0x1F);
            buf[out_pos] = base32_alphabet[idx];
            out_pos += 1;
        }
    }

    // Handle remaining bits
    if (bits_in_buffer > 0) {
        const shift: u6 = 5 - bits_in_buffer;
        const idx: u5 = @intCast((bit_buffer << shift) & 0x1F);
        buf[out_pos] = base32_alphabet[idx];
        out_pos += 1;
    }

    // Add padding
    while (out_pos < padded_len) {
        buf[out_pos] = base32_pad;
        out_pos += 1;
    }

    return buf;
}

/// Decode base32 string to bytes
pub fn b32decode(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    if (data.len == 0) return try allocator.alloc(u8, 0);

    // Build decode table
    var decode_table: [256]u8 = undefined;
    @memset(&decode_table, 0xFF);
    for (base32_alphabet, 0..) |c, i| {
        decode_table[c] = @intCast(i);
        // Also accept lowercase
        if (c >= 'A' and c <= 'Z') {
            decode_table[c + 32] = @intCast(i);
        }
    }

    // Count non-padding characters
    var input_len: usize = 0;
    for (data) |c| {
        if (c != base32_pad and c != ' ' and c != '\n' and c != '\r') {
            input_len += 1;
        }
    }

    // Calculate output length
    const out_len = (input_len * 5) / 8;
    const buf = try allocator.alloc(u8, out_len);
    errdefer allocator.free(buf);

    var bit_buffer: u64 = 0;
    var bits_in_buffer: u6 = 0;
    var out_pos: usize = 0;

    for (data) |c| {
        if (c == base32_pad or c == ' ' or c == '\n' or c == '\r') continue;

        const val = decode_table[c];
        if (val == 0xFF) return error.InvalidCharacter;

        bit_buffer = (bit_buffer << 5) | val;
        bits_in_buffer += 5;

        if (bits_in_buffer >= 8) {
            bits_in_buffer -= 8;
            if (out_pos < out_len) {
                buf[out_pos] = @intCast((bit_buffer >> bits_in_buffer) & 0xFF);
                out_pos += 1;
            }
        }
    }

    return buf[0..out_pos];
}

// ============================================================================
// ASCII85 (Adobe/btoa encoding)
// ============================================================================

/// Encode bytes to ASCII85 string
pub fn a85encode(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    if (data.len == 0) return try allocator.dupe(u8, "<~~>");

    // Worst case: 5 chars per 4 bytes + header/trailer
    const max_len = ((data.len + 3) / 4) * 5 + 4;
    var buf = try allocator.alloc(u8, max_len);
    errdefer allocator.free(buf);

    buf[0] = '<';
    buf[1] = '~';
    var pos: usize = 2;

    var i: usize = 0;
    while (i < data.len) {
        // Get 4 bytes (pad with zeros if needed)
        var val: u32 = 0;
        const remaining = data.len - i;
        const chunk_len = @min(remaining, 4);

        for (0..4) |j| {
            val <<= 8;
            if (j < chunk_len) {
                val |= data[i + j];
            }
        }

        if (val == 0 and chunk_len == 4) {
            // Special case: 4 zero bytes encode as 'z'
            buf[pos] = 'z';
            pos += 1;
        } else {
            // Encode as 5 base-85 digits
            var encoded: [5]u8 = undefined;
            var v = val;
            for (0..5) |j| {
                encoded[4 - j] = @intCast((v % 85) + 33);
                v /= 85;
            }
            // Only output needed characters for partial blocks
            const out_chars: usize = if (chunk_len == 4) 5 else chunk_len + 1;
            @memcpy(buf[pos .. pos + out_chars], encoded[0..out_chars]);
            pos += out_chars;
        }

        i += chunk_len;
    }

    buf[pos] = '~';
    buf[pos + 1] = '>';
    pos += 2;

    return try allocator.realloc(buf, pos);
}

/// Decode ASCII85 string to bytes
pub fn a85decode(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    // Skip <~ header and ~> trailer if present
    var start: usize = 0;
    var end: usize = data.len;

    if (data.len >= 2 and data[0] == '<' and data[1] == '~') {
        start = 2;
    }
    if (end >= 2 and data[end - 2] == '~' and data[end - 1] == '>') {
        end -= 2;
    }

    const input = data[start..end];
    if (input.len == 0) return try allocator.alloc(u8, 0);

    // Maximum output: 4 bytes per 5 chars
    const max_out = ((input.len + 4) / 5) * 4;
    var buf = try allocator.alloc(u8, max_out);
    errdefer allocator.free(buf);

    var pos: usize = 0;
    var i: usize = 0;
    var group: [5]u8 = undefined;
    var group_len: usize = 0;

    while (i < input.len) {
        const c = input[i];
        i += 1;

        // Skip whitespace
        if (c == ' ' or c == '\n' or c == '\r' or c == '\t') continue;

        // Handle 'z' special case (4 zero bytes)
        if (c == 'z') {
            if (group_len != 0) return error.InvalidData;
            @memset(buf[pos .. pos + 4], 0);
            pos += 4;
            continue;
        }

        // Regular character
        if (c < 33 or c > 117) return error.InvalidCharacter;
        group[group_len] = c - 33;
        group_len += 1;

        if (group_len == 5) {
            // Decode 5 chars to 4 bytes
            var val: u32 = 0;
            for (group[0..5]) |g| {
                val = val * 85 + g;
            }
            buf[pos] = @intCast((val >> 24) & 0xFF);
            buf[pos + 1] = @intCast((val >> 16) & 0xFF);
            buf[pos + 2] = @intCast((val >> 8) & 0xFF);
            buf[pos + 3] = @intCast(val & 0xFF);
            pos += 4;
            group_len = 0;
        }
    }

    // Handle remaining partial group
    if (group_len > 0) {
        // Pad with 'u' (84)
        while (group_len < 5) {
            group[group_len] = 84;
            group_len += 1;
        }
        var val: u32 = 0;
        for (group[0..5]) |g| {
            val = val * 85 + g;
        }
        const out_bytes = group_len - 1;
        if (out_bytes >= 1) buf[pos] = @intCast((val >> 24) & 0xFF);
        if (out_bytes >= 2) buf[pos + 1] = @intCast((val >> 16) & 0xFF);
        if (out_bytes >= 3) buf[pos + 2] = @intCast((val >> 8) & 0xFF);
        if (out_bytes >= 4) buf[pos + 3] = @intCast(val & 0xFF);
        pos += out_bytes - 1;
    }

    return try allocator.realloc(buf, pos);
}

// ============================================================================
// Tests
// ============================================================================

test "b64encode" {
    const allocator = std.testing.allocator;
    const result = try b64encode(allocator, "Hello, World!");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("SGVsbG8sIFdvcmxkIQ==", result);
}

test "b64decode" {
    const allocator = std.testing.allocator;
    const result = try b64decode(allocator, "SGVsbG8sIFdvcmxkIQ==");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Hello, World!", result);
}

test "b16encode" {
    const allocator = std.testing.allocator;
    const result = try b16encode(allocator, "Hi");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("4869", result);
}

test "b32encode" {
    const allocator = std.testing.allocator;
    const result = try b32encode(allocator, "Hello");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("JBSWY3DP", result);
}
