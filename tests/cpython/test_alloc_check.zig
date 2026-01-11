const std = @import("std");
pub fn main() !void {
    var l = std.ArrayList(u8){};
    try l.append(std.heap.page_allocator, 1);
    l.deinit(std.heap.page_allocator);
}
