/// Python _sitebuiltins module - Internal site builtins support
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "quitter", h.c(".{ .name = \"quit\", .eof = \"Ctrl-D (i.e. EOF)\" }") },
    .{ "printer", h.c(".{ .name = \"\", .data = \"\" }") },
    .{ "helper", h.c(".{}") },
});
