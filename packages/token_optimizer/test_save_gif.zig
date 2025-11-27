const std = @import("std");
const render = @import("src/render.zig");
const gif = @import("src/gif_zigimg.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const text = "Line 25: Test line with content";
    
    // Render to pixels
    var rendered = try render.renderText(allocator, text);
    defer rendered.deinit();
    
    std.debug.print("Rendered {}x{} image\n", .{rendered.width, rendered.height});
    
    // Encode as GIF (encodeGif takes 2D array)
    const gif_bytes = try gif.encodeGif(allocator, rendered.pixels);
    defer allocator.free(gif_bytes);
    
    std.debug.print("GIF size: {} bytes\n", .{gif_bytes.len});
    
    // Save to file
    const file = try std.fs.cwd().createFile("/tmp/test_line.gif", .{});
    defer file.close();
    
    try file.writeAll(gif_bytes);
    std.debug.print("Saved to /tmp/test_line.gif\n", .{});
}
