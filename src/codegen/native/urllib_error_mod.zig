/// Python urllib.error module - URL error exceptions
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "URLError", h.err("URLError") },
    .{ "HTTPError", h.err("HTTPError") },
    .{ "ContentTooShortError", h.err("ContentTooShortError") },
});
