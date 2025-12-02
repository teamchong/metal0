/// Python encodings module - Standard Encodings Package
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "search_function", h.discard(".{ .encode = null, .decode = null, .streamreader = null, .streamwriter = null, .incrementalencoder = null, .incrementaldecoder = null, .name = \"\" }") },
    .{ "normalize_encoding", h.discard("\"utf_8\"") },
    .{ "CodecInfo", h.c(".{ .encode = null, .decode = null, .streamreader = null, .streamwriter = null, .incrementalencoder = null, .incrementaldecoder = null, .name = \"\" }") },
    .{ "aliases", h.c(".{ .ascii = \"ascii\", .utf_8 = \"utf-8\", .utf_16 = \"utf-16\", .utf_32 = \"utf-32\", .latin_1 = \"iso8859-1\", .iso_8859_1 = \"iso8859-1\" }") },
});
