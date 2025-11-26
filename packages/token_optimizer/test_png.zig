const std = @import("std");
const render = @import("src/render.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var rendered = try render.renderText(allocator, "Hello");
    defer rendered.deinit();

    // Write as PGM (simple grayscale format - no compression)
    const file = try std.fs.cwd().createFile("/tmp/test.pgm", .{});
    defer file.close();
    
    const writer = file.writer();
    try writer.print("P2\n{d} {d}\n255\n", .{rendered.width, rendered.height});
    
    for (rendered.pixels) |row| {
        for (row) |pixel| {
            const gray = if (pixel == 1) 0 else if (pixel == 2) 128 else 255;
            try writer.print("{d} ", .{gray});
        }
        try writer.print("\n", .{});
    }
    
    std.debug.print("✅ /tmp/test.pgm\n", .{});
}
