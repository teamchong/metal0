const std = @import("std");

test "ArrayList" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Try different ways
    var list: std.ArrayList(u8) = .{};
    list.deinit(allocator);
}
