const std = @import("std");
const zigimg = @import("zigimg");
const render = @import("src/render.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var rendered = try render.renderText(allocator, "Hello");
    defer rendered.deinit();

    // Create zigimg Image
    var image = try zigimg.Image.create(allocator, rendered.width, rendered.height, .grayscale8);
    defer image.deinit();

    // Copy pixels
    for (rendered.pixels, 0..) |row, y| {
        for (row, 0..) |pixel, x| {
            const gray: u8 = if (pixel == 1) 0 else if (pixel == 2) 128 else 255;
            image.pixels.grayscale8[y * rendered.width + x].value = gray;
        }
    }

    // Save as GIF
    try image.writeToFilePath("/tmp/test_zigimg.gif", .{ .gif = .{} });

    std.debug.print("✅ /tmp/test_zigimg.gif\n", .{});
}
