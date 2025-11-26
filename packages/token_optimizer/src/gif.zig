const std = @import("std");

/// Encodes a pixel buffer to GIF89a format (uncompressed)
/// Pixels: [][]u8 where 0=white, 1=black, 2=gray
pub fn encodeGif(allocator: std.mem.Allocator, pixels: []const []const u8) ![]u8 {
    if (pixels.len == 0) return error.EmptyImage;
    const height = pixels.len;
    const width = pixels[0].len;

    // Calculate total size (conservative estimate)
    var buffer = std.ArrayList(u8){};
    errdefer buffer.deinit(allocator);

    // GIF Header: "GIF89a"
    try buffer.appendSlice(allocator, "GIF89a");

    // Logical Screen Descriptor
    try writeU16LE(&buffer, allocator, @intCast(width));   // Width
    try writeU16LE(&buffer, allocator, @intCast(height));  // Height
    try buffer.append(allocator, 0b10000001);  // Global color table: 4 colors (2 bits)
    try buffer.append(allocator, 0);           // Background color index
    try buffer.append(allocator, 0);           // Pixel aspect ratio

    // Global Color Table (4 colors: white, black, gray, unused)
    try buffer.appendSlice(allocator, &[_]u8{ 255, 255, 255 }); // Color 0: White
    try buffer.appendSlice(allocator, &[_]u8{ 0, 0, 0 });       // Color 1: Black
    try buffer.appendSlice(allocator, &[_]u8{ 128, 128, 128 }); // Color 2: Gray (50% lighter)
    try buffer.appendSlice(allocator, &[_]u8{ 0, 0, 0 });       // Color 3: Unused (black)

    // Image Descriptor
    try buffer.append(allocator, 0x2C);        // Image separator
    try writeU16LE(&buffer, allocator, 0);     // Left position
    try writeU16LE(&buffer, allocator, 0);     // Top position
    try writeU16LE(&buffer, allocator, @intCast(width));   // Image width
    try writeU16LE(&buffer, allocator, @intCast(height));  // Image height
    try buffer.append(allocator, 0);           // No local color table

    // Image Data (uncompressed using minimum code size)
    try buffer.append(allocator, 2);           // LZW minimum code size

    // Convert pixels to uncompressed LZW data
    try encodeUncompressedLZW(&buffer, allocator, pixels);

    // Block terminator
    try buffer.append(allocator, 0x00);

    // GIF Trailer
    try buffer.append(allocator, 0x3B);

    return buffer.toOwnedSlice(allocator);
}

fn writeU16LE(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u16) !void {
    try buffer.append(allocator, @intCast(value & 0xFF));
    try buffer.append(allocator, @intCast((value >> 8) & 0xFF));
}

/// Encode image data using uncompressed LZW format
/// For 4-color images, we use codes 0-7: {0, 1, 2, 3, clear, end}
fn encodeUncompressedLZW(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, pixels: []const []const u8) !void {
    const clear_code: u16 = 4;  // Clear code (2^2 = 4)
    const end_code: u16 = 5;    // End code

    var bit_buffer: u32 = 0;
    var bits_in_buffer: u5 = 0;
    const code_size: u5 = 3;  // Start with 3 bits (codes 0-7)

    // Start with clear code
    try writeLZWCode(buffer, allocator, &bit_buffer, &bits_in_buffer, clear_code, code_size);

    // Write each pixel
    for (pixels) |row| {
        for (row) |pixel| {
            const code: u16 = pixel;
            try writeLZWCode(buffer, allocator, &bit_buffer, &bits_in_buffer, code, code_size);
        }
    }

    // End code
    try writeLZWCode(buffer, allocator, &bit_buffer, &bits_in_buffer, end_code, code_size);

    // Flush remaining bits
    if (bits_in_buffer > 0) {
        try writeSubBlock(buffer, allocator, @intCast(bit_buffer & 0xFF));
    }
}

/// Write LZW code to bit stream
fn writeLZWCode(
    buffer: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    bit_buffer: *u32,
    bits_in_buffer: *u5,
    code: u16,
    code_size: u5
) !void {
    // Add code to bit buffer (LSB first)
    bit_buffer.* |= @as(u32, code) << bits_in_buffer.*;
    bits_in_buffer.* += code_size;

    // Write complete bytes to sub-blocks
    while (bits_in_buffer.* >= 8) {
        const byte: u8 = @intCast(bit_buffer.* & 0xFF);
        try writeSubBlock(buffer, allocator, byte);
        bit_buffer.* >>= 8;
        bits_in_buffer.* -= 8;
    }
}

/// Sub-block state for writing GIF data blocks
var sub_block_buffer: [255]u8 = undefined;
var sub_block_size: u8 = 0;

fn writeSubBlock(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, byte: u8) !void {
    sub_block_buffer[sub_block_size] = byte;
    sub_block_size += 1;

    if (sub_block_size == 255) {
        try flushSubBlock(buffer, allocator);
    }
}

fn flushSubBlock(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    if (sub_block_size > 0) {
        try buffer.append(allocator, sub_block_size);
        try buffer.appendSlice(allocator, sub_block_buffer[0..sub_block_size]);
        sub_block_size = 0;
    }
}

// Test helper
pub fn createTestImage(allocator: std.mem.Allocator) ![][]u8 {
    // Create simple 8x8 checkerboard pattern with 3 colors
    const pixels = try allocator.alloc([]u8, 8);
    for (pixels, 0..) |*row, y| {
        row.* = try allocator.alloc(u8, 8);
        for (row.*, 0..) |*pixel, x| {
            pixel.* = if ((x + y) % 3 == 0) 0 else if ((x + y) % 3 == 1) 1 else 2;
        }
    }
    return pixels;
}

pub fn freePixels(allocator: std.mem.Allocator, pixels: [][]u8) void {
    for (pixels) |row| {
        allocator.free(row);
    }
    allocator.free(pixels);
}

test "encode simple gif" {
    const allocator = std.testing.allocator;

    const pixels = try createTestImage(allocator);
    defer freePixels(allocator, pixels);

    const gif_data = try encodeGif(allocator, pixels);
    defer allocator.free(gif_data);

    // Verify GIF header
    try std.testing.expectEqualSlices(u8, "GIF89a", gif_data[0..6]);

    // Verify dimensions (8x8)
    try std.testing.expectEqual(@as(u8, 8), gif_data[6]);
    try std.testing.expectEqual(@as(u8, 0), gif_data[7]);
    try std.testing.expectEqual(@as(u8, 8), gif_data[8]);
    try std.testing.expectEqual(@as(u8, 0), gif_data[9]);

    // Verify trailer
    try std.testing.expectEqual(@as(u8, 0x3B), gif_data[gif_data.len - 1]);
}
