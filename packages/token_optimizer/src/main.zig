const std = @import("std");
const proxy = @import("proxy.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Check COMPRESS environment variable
    const compress_enabled = blk: {
        const env_value = std.posix.getenv("COMPRESS") orelse break :blk false;
        break :blk std.mem.eql(u8, env_value, "1");
    };

    std.debug.print("Text-to-image compression: {s}\n", .{if (compress_enabled) "ENABLED" else "DISABLED"});

    var server = proxy.ProxyServer.init(allocator, compress_enabled);

    try server.listen(8080);
}
