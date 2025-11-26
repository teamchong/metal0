const std = @import("std");
const proxy = @import("proxy.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var server = proxy.ProxyServer.init(allocator);

    try server.listen(8080);
}
