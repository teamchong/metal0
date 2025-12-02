/// Python _wmi module - Windows Management Instrumentation
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "exec_query", h.c("&[_]@TypeOf(.{}){}") },
});
