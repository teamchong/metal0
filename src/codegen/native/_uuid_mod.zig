/// Python _uuid module - Internal UUID support (C accelerator)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getnode", h.I64(0) },
    .{ "generate_time_safe", h.c(".{ \"\\x00\" ** 16, @as(i32, 0) }") },
    .{ "uuid_create", h.c("\"\\x00\" ** 16") },
    .{ "has_uuid_generate_time_safe", h.c("false") },
});
