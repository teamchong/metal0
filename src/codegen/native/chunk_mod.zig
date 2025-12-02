/// Python chunk module - Read IFF chunked data
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Chunk", h.wrap("blk: { const file = ", "; _ = file; break :blk .{ .closed = false, .align = true, .bigendian = true, .inclheader = false, .chunkname = &[_]u8{0} ** 4, .chunksize = 0, .size_read = 0 }; }", ".{ .closed = false, .align = true, .bigendian = true, .inclheader = false, .chunkname = &[_]u8{0} ** 4, .chunksize = 0, .size_read = 0 }") }, .{ "getname", h.c("\"\"") }, .{ "getsize", h.I64(0) },
    .{ "close", h.c("{}") }, .{ "isatty", h.c("false") }, .{ "seek", h.c("{}") },
    .{ "tell", h.I64(0) }, .{ "read", h.c("\"\"") }, .{ "skip", h.c("{}") },
});
