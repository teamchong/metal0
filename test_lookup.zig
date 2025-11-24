const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Test FunctionDef structure
    const ast = @import("src/ast.zig");
    
    std.debug.print("Testing async function lookup\n", .{});
}
