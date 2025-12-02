/// Python getpass module - Portable password input
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getpass", h.discard("getpass_blk: { const stdin = std.io.getStdIn().reader(); var buf: [256]u8 = undefined; break :getpass_blk stdin.readUntilDelimiter(&buf, '\\n') catch \"\"; }") },
    .{ "getuser", h.c("getuser_blk: { const user = std.posix.getenv(\"USER\") orelse std.posix.getenv(\"LOGNAME\") orelse \"unknown\"; break :getuser_blk user; }") },
    .{ "GetPassWarning", h.c("\"GetPassWarning\"") },
});
