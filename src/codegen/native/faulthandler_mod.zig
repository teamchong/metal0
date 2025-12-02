/// Python faulthandler module - Dump Python tracebacks on fault signals
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "enable", h.c("{}") }, .{ "disable", h.c("{}") }, .{ "is_enabled", h.c("true") },
    .{ "dump_traceback", h.c("{}") }, .{ "dump_traceback_later", h.c("{}") },
    .{ "cancel_dump_traceback_later", h.c("{}") }, .{ "register", h.c("{}") }, .{ "unregister", h.c("{}") },
});
