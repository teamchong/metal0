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

    // Encode to GIF via temp file (zigimg's writeToMemory has fixed buffer limits)
    // This approach handles any image size dynamically
    const tmp_path = try std.fmt.allocPrint(allocator, "/tmp/gif_encode_{d}.gif", .{std.time.timestamp()});
    defer allocator.free(tmp_path);

    // Temp buffer for writeToFilePath (it still needs one but won't overflow since it writes to file)
    var temp_buf: [8192]u8 = undefined;

    // Write to temp file
    const encoder_options = zigimg.Image.EncoderOptions{ .gif = {} };
    try image.writeToFilePath(allocator, tmp_path, &temp_buf, encoder_options);
    defer std.fs.deleteFileAbsolute(tmp_path) catch {};

    // Read back into memory
    const file = try std.fs.openFileAbsolute(tmp_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const gif_bytes = try allocator.alloc(u8, file_size);
    errdefer allocator.free(gif_bytes);

    _ = try file.readAll(gif_bytes);
    return gif_bytes;
}
