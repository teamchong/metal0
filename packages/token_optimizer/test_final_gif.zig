const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Import the actual modules used by proxy
    const render = @import("src/render.zig");
    const compress = @import("src/compress.zig");
    
    const test_text = 
        \\def fibonacci(n):
        \\    if n <= 1:
        \\        return n
        \\    return fibonacci(n-1) + fibonacci(n-2)
        \\
        \\print(fibonacci(10))
    ;

    // Render text
    var rendered = try render.renderText(allocator, test_text);
    defer rendered.deinit();

    std.debug.print("Rendered: {d}x{d} pixels\n", .{ rendered.width, rendered.height });

    // Encode as GIF using our gif module
    const gif_mod = @import("src/gif_zigimg.zig");
    const gif_bytes = try gif_mod.encodeGif(allocator, rendered.pixels);
    defer allocator.free(gif_bytes);

    std.debug.print("GIF: {d} bytes\n", .{gif_bytes.len});

    // Save to file
    const file = try std.fs.cwd().createFile("/tmp/test_final.gif", .{});
    defer file.close();
    try file.writeAll(gif_bytes);

    std.debug.print("✅ Saved to /tmp/test_final.gif\n", .{});
}
