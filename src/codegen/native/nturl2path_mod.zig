/// Python nturl2path module - Convert NT URLs to pathnames
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "url2pathname", h.pass("\"\"") },
    .{ "pathname2url", h.pass("\"\"") },
});
