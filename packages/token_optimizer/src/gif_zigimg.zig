const std = @import("std");
const zigimg = @import("zigimg");

/// Encodes a pixel buffer to GIF using zigimg library
/// Pixels: [][]u8 where 0=white, 1=black, 2=gray
pub fn encodeGif(allocator: std.mem.Allocator, pixels: []const []const u8) ![]u8 {
    if (pixels.len == 0) return error.EmptyImage;
    const height = pixels.len;
    const width = pixels[0].len;

    // Create zigimg Image with indexed color (palette)
    var image = try zigimg.Image.create(allocator, width, height, .indexed8);
    defer image.deinit(allocator);

    // Set up 4-color palette: white, black, gray, unused
    image.pixels.indexed8.palette[0] = .{ .r = 255, .g = 255, .b = 255, .a = 255 }; // White
    image.pixels.indexed8.palette[1] = .{ .r = 0, .g = 0, .b = 0, .a = 255 };       // Black
    image.pixels.indexed8.palette[2] = .{ .r = 128, .g = 128, .b = 128, .a = 255 }; // Gray
    image.pixels.indexed8.palette[3] = .{ .r = 0, .g = 0, .b = 0, .a = 255 };       // Unused

    // Copy pixels
    for (pixels, 0..) |row, y| {
        for (row, 0..) |pixel, x| {
            image.pixels.indexed8.indices[y * width + x] = pixel;
        }
    }

    // Encode to GIF in memory
    var write_buffer: [8192]u8 = undefined;
    return try image.writeToMemory(allocator, &write_buffer, .gif);
}
