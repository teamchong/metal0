const std = @import("std");
const gif = @import("src/gif.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create test pattern
    std.debug.print("Creating test image...\n", .{});
    const pixels = try gif.createTestImage(allocator);
    defer gif.freePixels(allocator, pixels);

    // Encode to GIF
    std.debug.print("Encoding to GIF...\n", .{});
    const gif_data = try gif.encodeGif(allocator, pixels);
    defer allocator.free(gif_data);

    std.debug.print("GIF size: {} bytes\n", .{gif_data.len});

    // Write to file
    const file = try std.fs.cwd().createFile("/tmp/test.gif", .{});
    defer file.close();
    try file.writeAll(gif_data);

    std.debug.print("Written to /tmp/test.gif\n", .{});
    std.debug.print("Open with: open /tmp/test.gif\n", .{});
}
