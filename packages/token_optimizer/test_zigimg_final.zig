const std = @import("std");
const render = @import("src/render.zig");
const gif = @import("src/gif_zigimg.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var rendered = try render.renderText(allocator, "Hello World\nLine 2");
    defer rendered.deinit();

    std.debug.print("Size: {d}x{d}\n", .{ rendered.width, rendered.height });

    const gif_bytes = try gif.encodeGif(allocator, rendered.pixels);
    defer allocator.free(gif_bytes);

    std.debug.print("GIF: {d} bytes\n", .{gif_bytes.len});

    const file = try std.fs.cwd().createFile("/tmp/test_zigimg_final.gif", .{});
    defer file.close();
    try file.writeAll(gif_bytes);

    std.debug.print("✅ /tmp/test_zigimg_final.gif\n", .{});
}
