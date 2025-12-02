/// Python html.parser module - HTML parsing
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "HTMLParser", h.c(".{ .convert_charrefs = true }") },
    .{ "HTMLParseError", h.err("HTMLParseError") },
});
