const std = @import("std");
const render = @import("src/render.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Simple single character
    var rendered = try render.renderText(allocator, "H");
    defer rendered.deinit();

    std.debug.print("Dimensions: {d}x{d}\n", .{ rendered.width, rendered.height });
    std.debug.print("Pixels:\n", .{});
    
    for (rendered.pixels) |row| {
        for (row) |pixel| {
            std.debug.print("{d}", .{pixel});
        }
        std.debug.print("\n", .{});
    }
}
