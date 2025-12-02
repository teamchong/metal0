/// Python _csv module - C accelerator for csv (internal)
const std = @import("std");
const h = @import("mod_helper.zig");

const genRW = h.wrap("blk: { const csvfile = ", "; break :blk .{ .file = csvfile, .dialect = \"excel\" }; }", ".{ .file = null, .dialect = \"excel\" }");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "reader", genRW }, .{ "writer", genRW },
    .{ "register_dialect", h.c("{}") }, .{ "unregister_dialect", h.c("{}") },
    .{ "get_dialect", h.c(".{ .delimiter = ',', .quotechar = '\"', .escapechar = null, .doublequote = true, .skipinitialspace = false, .lineterminator = \"\\r\\n\", .quoting = 0, .strict = false }") },
    .{ "list_dialects", h.c("&[_][]const u8{ \"excel\", \"excel-tab\", \"unix\" }") }, .{ "field_size_limit", h.pass("@as(i64, 131072)") },
    .{ "QUOTE_ALL", h.I32(1) }, .{ "QUOTE_MINIMAL", h.I32(0) }, .{ "QUOTE_NONNUMERIC", h.I32(2) }, .{ "QUOTE_NONE", h.I32(3) },
    .{ "Error", h.err("CsvError") },
});
