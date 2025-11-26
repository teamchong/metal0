const std = @import("std");
const render = @import("src/render.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var rendered = try render.renderText(allocator, "Hello");
    defer rendered.deinit();

    const file = try std.fs.cwd().createFile("/tmp/test.pgm", .{});
    defer file.close();
    
    var header_buf: [100]u8 = undefined;
    const header = try std.fmt.bufPrint(&header_buf, "P2\n{d} {d}\n255\n", .{rendered.width, rendered.height});
    try file.writeAll(header);
    
    for (rendered.pixels) |row| {
        for (row) |pixel| {
            const gray: u8 = if (pixel == 1) 0 else if (pixel == 2) 128 else 255;
            var pixel_buf: [10]u8 = undefined;
            const pixel_str = try std.fmt.bufPrint(&pixel_buf, "{d} ", .{gray});
            try file.writeAll(pixel_str);
        }
        try file.writeAll("\n");
    }
    
    std.debug.print("✅ /tmp/test.pgm\n", .{});
}
