/// Python _codecs module - C accelerator for codecs (internal)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "encode", h.pass("\"\"") }, .{ "decode", h.pass("\"\"") },
    .{ "register", h.c("{}") }, .{ "lookup", h.c(".{ .encode = null, .decode = null, .streamreader = null, .streamwriter = null }") },
    .{ "register_error", h.c("{}") }, .{ "lookup_error", h.c("null") },
    .{ "utf_8_encode", h.codecResult(".{ \"\", 0 }") }, .{ "utf_8_decode", h.codecResult(".{ \"\", 0 }") },
    .{ "ascii_encode", h.codecResult(".{ \"\", 0 }") }, .{ "ascii_decode", h.codecResult(".{ \"\", 0 }") },
    .{ "latin_1_encode", h.codecResult(".{ \"\", 0 }") }, .{ "latin_1_decode", h.codecResult(".{ \"\", 0 }") },
    .{ "escape_encode", h.codecResult(".{ \"\", 0 }") }, .{ "escape_decode", h.codecResult(".{ \"\", 0 }") },
    .{ "raw_unicode_escape_encode", h.codecResult(".{ \"\", 0 }") }, .{ "raw_unicode_escape_decode", h.codecResult(".{ \"\", 0 }") },
    .{ "unicode_escape_encode", h.codecResult(".{ \"\", 0 }") }, .{ "unicode_escape_decode", h.codecResult(".{ \"\", 0 }") },
    .{ "charmap_encode", h.codecResult(".{ \"\", 0 }") }, .{ "charmap_decode", h.codecResult(".{ \"\", 0 }") },
    .{ "charmap_build", h.c("&[_]u8{} ** 256") },
    .{ "mbcs_encode", h.codecResult(".{ \"\", 0 }") }, .{ "mbcs_decode", h.codecResult(".{ \"\", 0 }") },
    .{ "readbuffer_encode", h.pass("\"\"") },
});
