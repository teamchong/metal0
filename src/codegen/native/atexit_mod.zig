/// Python atexit module - Exit handlers
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "register", h.pass("@as(?*anyopaque, null)") }, .{ "unregister", h.c("{}") }, .{ "_run_exitfuncs", h.c("{}") },
    .{ "_clear", h.c("{}") }, .{ "_ncallbacks", h.I64(0) },
});
