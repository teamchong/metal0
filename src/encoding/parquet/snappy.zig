//! Snappy decompression for Parquet files.
//!
//! Snappy is a fast compression algorithm developed by Google.
//! See: https://github.com/google/snappy/blob/main/format_description.txt
//!
//! Format:
//! 1. Varint: Uncompressed length
//! 2. Elements: Each starts with a tag byte
//!    - Tag bits 1-0 = element type:
//!      - 00: Literal
//!      - 01: Copy with 1-byte offset
//!      - 10: Copy with 2-byte offset
//!      - 11: Copy with 4-byte offset

const std = @import("std");

pub const SnappyError = error{
    UnexpectedEndOfData,
    InvalidFormat,
    OutputOverflow,
    InvalidCopyOffset,
    OutOfMemory,
};

/// SIMD-accelerated copy for non-overlapping regions
/// Uses 32-byte vectors when possible, falls back to 16-byte, then scalar
inline fn simdCopy(dst: [*]u8, src: [*]const u8, len: usize) void {
    var i: usize = 0;

    // 32-byte SIMD (AVX/NEON)
    while (i + 32 <= len) : (i += 32) {
        const v: @Vector(32, u8) = src[i..][0..32].*;
        dst[i..][0..32].* = v;
    }

    // 16-byte SIMD for remainder
    while (i + 16 <= len) : (i += 16) {
        const v: @Vector(16, u8) = src[i..][0..16].*;
        dst[i..][0..16].* = v;
    }

    // Scalar fallback for tail
    while (i < len) : (i += 1) {
        dst[i] = src[i];
    }
}

/// Decompress Snappy-compressed data
pub fn decompress(compressed: []const u8, allocator: std.mem.Allocator) SnappyError![]u8 {
    if (compressed.len == 0) {
        return SnappyError.UnexpectedEndOfData;
    }

    var pos: usize = 0;

    // Read uncompressed length (varint) - inline fast path
    var uncompressed_len: usize = 0;
    {
        var shift: u6 = 0;
        while (pos < compressed.len) {
            const byte = compressed[pos];
            pos += 1;
            uncompressed_len |= @as(usize, byte & 0x7F) << shift;
            if (byte & 0x80 == 0) break;
            shift += 7;
            if (shift >= 35) return SnappyError.InvalidFormat;
        }
    }

    // Allocate output buffer
    const output = try allocator.alloc(u8, uncompressed_len);
    errdefer allocator.free(output);

    var out_pos: usize = 0;

    // Process elements - hot loop
    while (pos < compressed.len) {
        const tag = compressed[pos];
        pos += 1;

        const element_type = tag & 0x03;

        if (element_type == 0x00) {
            // Literal - most common case
            const len_minus_1 = tag >> 2;
            var len: usize = undefined;

            if (len_minus_1 < 60) {
                len = @as(usize, len_minus_1) + 1;
            } else {
                const extra_bytes: usize = @as(usize, len_minus_1) - 59;
                if (pos + extra_bytes > compressed.len) return SnappyError.UnexpectedEndOfData;
                len = 1;
                for (0..extra_bytes) |i| {
                    len += @as(usize, compressed[pos + i]) << @intCast(i * 8);
                }
                pos += extra_bytes;
            }

            if (pos + len > compressed.len) return SnappyError.UnexpectedEndOfData;
            if (out_pos + len > uncompressed_len) return SnappyError.OutputOverflow;

            simdCopy(output.ptr + out_pos, compressed.ptr + pos, len);
            pos += len;
            out_pos += len;
        } else if (element_type == 0x01) {
            // Copy with 1-byte offset (most common copy type)
            const len: usize = ((tag >> 2) & 0x07) + 4;
            if (pos >= compressed.len) return SnappyError.UnexpectedEndOfData;
            const offset: usize = (@as(usize, tag & 0xE0) << 3) | compressed[pos];
            pos += 1;

            if (offset == 0 or offset > out_pos) return SnappyError.InvalidCopyOffset;
            if (out_pos + len > uncompressed_len) return SnappyError.OutputOverflow;

            const src_start = out_pos - offset;
            if (len <= offset) {
                // Non-overlapping
                simdCopy(output.ptr + out_pos, output.ptr + src_start, len);
            } else {
                // Overlapping - chunk copy
                var remaining = len;
                var dst = out_pos;
                while (remaining > 0) {
                    const chunk = @min(remaining, offset);
                    simdCopy(output.ptr + dst, output.ptr + src_start, chunk);
                    dst += chunk;
                    remaining -= chunk;
                }
            }
            out_pos += len;
        } else if (element_type == 0x02) {
            // Copy with 2-byte offset
            const len: usize = (tag >> 2) + 1;
            if (pos + 2 > compressed.len) return SnappyError.UnexpectedEndOfData;
            const offset: usize = std.mem.readInt(u16, compressed[pos..][0..2], .little);
            pos += 2;

            if (offset == 0 or offset > out_pos) return SnappyError.InvalidCopyOffset;
            if (out_pos + len > uncompressed_len) return SnappyError.OutputOverflow;

            const src_start = out_pos - offset;
            if (len <= offset) {
                simdCopy(output.ptr + out_pos, output.ptr + src_start, len);
            } else {
                var remaining = len;
                var dst = out_pos;
                while (remaining > 0) {
                    const chunk = @min(remaining, offset);
                    simdCopy(output.ptr + dst, output.ptr + src_start, chunk);
                    dst += chunk;
                    remaining -= chunk;
                }
            }
            out_pos += len;
        } else {
            // Copy with 4-byte offset (rare)
            const len: usize = (tag >> 2) + 1;
            if (pos + 4 > compressed.len) return SnappyError.UnexpectedEndOfData;
            const offset: usize = std.mem.readInt(u32, compressed[pos..][0..4], .little);
            pos += 4;

            if (offset == 0 or offset > out_pos) return SnappyError.InvalidCopyOffset;
            if (out_pos + len > uncompressed_len) return SnappyError.OutputOverflow;

            const src_start = out_pos - offset;
            if (len <= offset) {
                simdCopy(output.ptr + out_pos, output.ptr + src_start, len);
            } else {
                var remaining = len;
                var dst = out_pos;
                while (remaining > 0) {
                    const chunk = @min(remaining, offset);
                    simdCopy(output.ptr + dst, output.ptr + src_start, chunk);
                    dst += chunk;
                    remaining -= chunk;
                }
            }
            out_pos += len;
        }
    }

    if (out_pos != uncompressed_len) {
        return SnappyError.InvalidFormat;
    }

    return output;
}

/// Read varint (up to 32 bits)
fn readVarint(data: []const u8, pos: *usize) SnappyError!usize {
    var result: usize = 0;
    var shift: u6 = 0;

    while (pos.* < data.len) {
        const byte = data[pos.*];
        pos.* += 1;

        result |= @as(usize, byte & 0x7F) << shift;

        if (byte & 0x80 == 0) {
            return result;
        }

        shift += 7;
        if (shift >= 35) {
            return SnappyError.InvalidFormat;
        }
    }

    return SnappyError.UnexpectedEndOfData;
}

/// Decode literal length from tag byte
fn decodeLiteralLength(data: []const u8, pos: *usize, tag: u8) SnappyError!usize {
    const len_minus_1 = tag >> 2;

    if (len_minus_1 < 60) {
        // Length encoded directly in tag
        return @as(usize, len_minus_1) + 1;
    }

    // Length encoded in subsequent bytes
    const extra_bytes: usize = @as(usize, len_minus_1) - 59;
    if (pos.* + extra_bytes > data.len) {
        return SnappyError.UnexpectedEndOfData;
    }

    var len: usize = 0;
    for (0..extra_bytes) |i| {
        len |= @as(usize, data[pos.* + i]) << @intCast(i * 8);
    }
    pos.* += extra_bytes;

    return len + 1;
}

/// Copy bytes from earlier in output (handles overlapping copies)
fn copyBytes(output: []u8, out_pos: *usize, max_len: usize, offset: usize, len: usize) SnappyError!void {
    if (offset == 0 or offset > out_pos.*) {
        return SnappyError.InvalidCopyOffset;
    }
    if (out_pos.* + len > max_len) {
        return SnappyError.OutputOverflow;
    }

    const src_start = out_pos.* - offset;

    // Handle overlapping copy (when len > offset, we need to copy in chunks)
    if (len <= offset) {
        // Non-overlapping copy - single memcpy
        @memcpy(output[out_pos.*..][0..len], output[src_start..][0..len]);
    } else {
        // Overlapping copy - copy in chunks of 'offset' bytes
        // This avoids per-byte modulo and leverages memcpy
        var remaining = len;
        var dst = out_pos.*;
        while (remaining > 0) {
            const chunk = @min(remaining, offset);
            @memcpy(output[dst..][0..chunk], output[src_start..][0..chunk]);
            dst += chunk;
            remaining -= chunk;
        }
    }

    out_pos.* += len;
}

// ============================================================================
// Tests
// ============================================================================

test "decompress literal only" {
    // Simple literal: "hello"
    // Varint length: 5 = 0x05
    // Tag: literal, len=5-1=4, so tag = 4 << 2 | 0 = 0x10
    const compressed = [_]u8{ 0x05, 0x10, 'h', 'e', 'l', 'l', 'o' };

    const result = try decompress(&compressed, std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("hello", result);
}

test "decompress with copy" {
    // "abcabcabc" - 9 bytes uncompressed
    // Literal "abc" (3 bytes) + copy offset=3, len=6
    // Varint length: 9 = 0x09
    // Literal tag: len=3-1=2, tag = 2 << 2 | 0 = 0x08
    // Copy tag (type 01): len=6, but type 01 has len-4, so len_field=2
    //   tag = (2 << 2) | 0x01 = 0x09
    //   Since type 01: len = ((tag >> 2) & 0x07) + 4 = 2 + 4 = 6 ✓
    //   offset = ((tag & 0xE0) << 3) | next_byte = 0 | 3 = 3 ✓
    const compressed = [_]u8{ 0x09, 0x08, 'a', 'b', 'c', 0x09, 0x03 };

    const result = try decompress(&compressed, std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("abcabcabc", result);
}

test "decompress with 2-byte offset copy" {
    // Literal of 64 'a's, then copy with 2-byte offset
    // For simplicity, just test the offset decoding

    // "aaaa" (4 bytes) + copy 4 more = "aaaaaaaa"
    // Literal tag: len=4-1=3, tag = 3 << 2 | 0 = 0x0C
    // Copy type 02: len=4, tag = (4-1) << 2 | 2 = 0x0E
    //   offset = 4 (little-endian 2 bytes)
    const compressed = [_]u8{ 0x08, 0x0C, 'a', 'a', 'a', 'a', 0x0E, 0x04, 0x00 };

    const result = try decompress(&compressed, std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("aaaaaaaa", result);
}

test "decompress overlapping copy (run-length)" {
    // "aaaaaa" - created by copying a single 'a' 5 more times
    // Literal "a" + copy offset=1, len=5
    // Type 01 copy: len = ((tag >> 2) & 0x07) + 4, so for len=5, we need len_field=1
    //   tag = (1 << 2) | 0x01 = 0x05
    //   offset byte = 1
    const compressed = [_]u8{ 0x06, 0x00, 'a', 0x05, 0x01 };

    const result = try decompress(&compressed, std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("aaaaaa", result);
}
