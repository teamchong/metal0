const std = @import("std");

test "ArrayList API" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();
    
    try list.append(1);
}
