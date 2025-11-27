const std = @import("std");

/// Encodes a pixel buffer to PNG format using indexed color (palette)
/// Pixels: [][]u8 where values 0-7 map to our 8-color palette
pub fn encodePng(allocator: std.mem.Allocator, pixels: []const []const u8) ![]u8 {
    if (pixels.len == 0) return error.EmptyImage;
    const height: u32 = @intCast(pixels.len);
    const width: u32 = @intCast(pixels[0].len);

    var buffer = std.ArrayList(u8){};
    errdefer buffer.deinit(allocator);

    // PNG Signature
    try buffer.appendSlice(allocator, &[_]u8{ 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A });

    // IHDR chunk (image header)
    var ihdr: [13]u8 = undefined;
    std.mem.writeInt(u32, ihdr[0..4], width, .big);    // Width
    std.mem.writeInt(u32, ihdr[4..8], height, .big);   // Height
    ihdr[8] = 8;   // Bit depth (8 bits per pixel for indexed)
    ihdr[9] = 3;   // Color type 3 = indexed color (palette)
    ihdr[10] = 0;  // Compression method (deflate)
    ihdr[11] = 0;  // Filter method
    ihdr[12] = 0;  // Interlace method (none)
    try writeChunk(&buffer, allocator, "IHDR", &ihdr);

    // PLTE chunk (palette) - 8 colors matching RenderColor enum
    const palette = [_]u8{
        255, 255, 255, // 0: White (background)
        0,   0,   0,   // 1: Black (default text)
        180, 180, 180, // 2: Gray (whitespace)
        0,   100, 200, // 3: Blue (user)
        0,   150, 50,  // 4: Green (assistant)
        200, 50,  50,  // 5: Red (system)
        230, 120, 0,   // 6: Orange (tool)
        0,   180, 180, // 7: Cyan (result)
    };
    try writeChunk(&buffer, allocator, "PLTE", &palette);

    // IDAT chunk (compressed image data)
    // Build raw scanlines with filter byte prefix
    const scanline_size = 1 + width; // filter byte + pixel data
    const raw_data = try allocator.alloc(u8, scanline_size * height);
    defer allocator.free(raw_data);

    for (0..height) |y| {
        const offset = y * scanline_size;
        raw_data[offset] = 0; // Filter type: None
        @memcpy(raw_data[offset + 1 .. offset + 1 + width], pixels[y][0..width]);
    }

    // Compress with zlib using std.compress.flate with zlib container
    var compressed_list = std.ArrayList(u8){};
    defer compressed_list.deinit(allocator);

    var compressor = std.compress.flate.Compress(.zlib).init(compressed_list.writer(allocator), .{});
    try compressor.write(raw_data);
    try compressor.finish();

    const compressed = try compressed_list.toOwnedSlice(allocator);
    defer allocator.free(compressed);

    try writeChunk(&buffer, allocator, "IDAT", compressed);

    // IEND chunk (image end)
    try writeChunk(&buffer, allocator, "IEND", &[_]u8{});

    return buffer.toOwnedSlice(allocator);
}

fn writeChunk(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, chunk_type: *const [4]u8, data: []const u8) !void {
    // Length (4 bytes, big-endian)
    var len_bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &len_bytes, @intCast(data.len), .big);
    try buffer.appendSlice(allocator, &len_bytes);

    // Chunk type (4 bytes)
    try buffer.appendSlice(allocator, chunk_type);

    // Data
    try buffer.appendSlice(allocator, data);

    // CRC32 (over type + data)
    var crc_data = std.ArrayList(u8){};
    defer crc_data.deinit(allocator);
    try crc_data.appendSlice(allocator, chunk_type);
    try crc_data.appendSlice(allocator, data);

    const crc = crc32(crc_data.items);
    var crc_bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &crc_bytes, crc, .big);
    try buffer.appendSlice(allocator, &crc_bytes);
}

/// CRC32 as used in PNG (polynomial 0xedb88320)
fn crc32(data: []const u8) u32 {
    var crc: u32 = 0xFFFFFFFF;
    for (data) |byte| {
        crc ^= byte;
        for (0..8) |_| {
            if (crc & 1 == 1) {
                crc = (crc >> 1) ^ 0xEDB88320;
            } else {
                crc >>= 1;
            }
        }
    }
    return ~crc;
}

test "encode simple png" {
    const allocator = std.testing.allocator;

    // Create 4x4 test image with different colors
    var pixels: [4][]u8 = undefined;
    for (&pixels, 0..) |*row, y| {
        row.* = try allocator.alloc(u8, 4);
        for (row.*, 0..) |*pixel, x| {
            pixel.* = @intCast((x + y) % 8);
        }
    }
    defer for (&pixels) |row| allocator.free(row);

    const png_data = try encodePng(allocator, &pixels);
    defer allocator.free(png_data);

    // Verify PNG signature
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A }, png_data[0..8]);

    // Verify IHDR chunk type
    try std.testing.expectEqualSlices(u8, "IHDR", png_data[12..16]);
}
