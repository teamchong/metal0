const std = @import("std");
const render = @import("src/render.zig");
const gif = @import("src/gif.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var rendered = try render.renderText(allocator, "A");
    defer rendered.deinit();

    std.debug.print("Dimensions: {d}x{d}\n", .{ rendered.width, rendered.height });
    
    for (rendered.pixels, 0..) |row, y| {
        std.debug.print("Row {d}: ", .{y});
        for (row) |pixel| {
            const ch: u8 = if (pixel == 1) '#' else '.';
            std.debug.print("{c}", .{ch});
        }
        std.debug.print("\n", .{});
    }

    const gif_bytes = try gif.encodeGif(allocator, rendered.pixels);
    defer allocator.free(gif_bytes);

    const file = try std.fs.cwd().createFile("/tmp/test_A.gif", .{});
    defer file.close();
    try file.writeAll(gif_bytes);

    std.debug.print("✅ /tmp/test_A.gif\n", .{});
}
