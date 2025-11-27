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

    // Use unique port to avoid conflicts (can override with PORT env var)
    const port: u16 = blk: {
        const env_port = std.posix.getenv("PORT") orelse break :blk 19847;
        break :blk std.fmt.parseInt(u16, env_port, 10) catch 19847;
    };

    try server.listen(port);
}
