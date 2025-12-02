/// Python _aix_support module - AIX platform support
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "aix_platform", h.c("\"\"") },
    .{ "aix_buildtag", h.c("\"\"") },
});
