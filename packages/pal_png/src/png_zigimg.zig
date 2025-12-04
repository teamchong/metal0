const std = @import("std");
const zigimg = @import("zigimg");

/// Encodes a pixel buffer to PNG using zigimg library
/// Pixels: [][]u8 where:
///   0=white (bg), 1=black, 2=gray, 3=blue (user), 4=green (assistant),
///   5=yellow (tool), 6=cyan (result), 7=purple (error)
pub fn encodePng(allocator: std.mem.Allocator, pixels: []const []const u8) ![]u8 {
    if (pixels.len == 0) return error.EmptyImage;
    const height = pixels.len;
    const width = pixels[0].len;

    // Create zigimg Image with indexed color (palette)
    var image = zigimg.Image.create(allocator, width, height, .indexed8) catch |err| {
        std.debug.print("ERROR: PNG encode failed ({d}x{d}): {any}\n", .{width, height, err});
        return err;
    };
    defer image.deinit(allocator);

    // Set up color palette matching RenderColor enum
    // Index must match render.zig RoleColor.toIndex()
    image.pixels.indexed8.palette[0] = .{ .r = 255, .g = 255, .b = 255, .a = 255 }; // 0: White (bg)
    image.pixels.indexed8.palette[1] = .{ .r = 0, .g = 0, .b = 0, .a = 255 };       // 1: Black (unused)
    image.pixels.indexed8.palette[2] = .{ .r = 204, .g = 204, .b = 204, .a = 255 }; // 2: Gray #CCC (whitespace)
    image.pixels.indexed8.palette[3] = .{ .r = 59, .g = 130, .b = 246, .a = 255 };  // 3: Blue (user)
    image.pixels.indexed8.palette[4] = .{ .r = 34, .g = 197, .b = 94, .a = 255 };   // 4: Green (assistant)
    image.pixels.indexed8.palette[5] = .{ .r = 234, .g = 179, .b = 8, .a = 255 };   // 5: Yellow (system)
    image.pixels.indexed8.palette[6] = .{ .r = 239, .g = 68, .b = 68, .a = 255 };   // 6: Red (tool_use)
    image.pixels.indexed8.palette[7] = .{ .r = 168, .g = 85, .b = 247, .a = 255 };  // 7: Purple (tool_result)

    // Copy pixels
    for (pixels, 0..) |row, y| {
        for (row, 0..) |pixel, x| {
            image.pixels.indexed8.indices[y * width + x] = pixel;
        }
    }

    // Encode to PNG via temp file (zigimg's writeToMemory has fixed buffer limits)
    // This approach handles any image size dynamically
    const tmp_path = try std.fmt.allocPrint(allocator, "/tmp/png_encode_{d}.png", .{std.time.timestamp()});
    defer allocator.free(tmp_path);

    // Temp buffer for writeToFilePath (it still needs one but won't overflow since it writes to file)
    var temp_buf: [8192]u8 = undefined;

    // Write to temp file as PNG
    const encoder_options = zigimg.Image.EncoderOptions{ .png = .{} };
    image.writeToFilePath(allocator, tmp_path, &temp_buf, encoder_options) catch |err| {
        std.debug.print("ERROR: PNG write failed: {any}\n", .{err});
        return err;
    };
    defer std.fs.deleteFileAbsolute(tmp_path) catch {};

    // Read back into memory
    const file = try std.fs.openFileAbsolute(tmp_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    if (file_size == 0) {
        std.debug.print("ERROR: PNG encoder wrote 0 bytes!\n", .{});
        return error.EmptyPng;
    }

    const png_bytes = try allocator.alloc(u8, file_size);
    errdefer allocator.free(png_bytes);

    _ = try file.readAll(png_bytes);
    return png_bytes;
}
