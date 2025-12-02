/// Python fileinput module - Iterate over lines from multiple input streams
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "input", h.c(".{ .files = &[_][]const u8{}, .inplace = false, .backup = \"\", .mode = \"r\" }") },
    .{ "filename", h.c("\"\"") }, .{ "fileno", h.I32(-1) },
    .{ "lineno", h.I64(0) }, .{ "filelineno", h.I64(0) },
    .{ "isfirstline", h.c("false") }, .{ "isstdin", h.c("false") }, .{ "nextfile", h.c("{}") }, .{ "close", h.c("{}") },
    .{ "FileInput", h.c(".{ .files = &[_][]const u8{}, .inplace = false, .backup = \"\", .mode = \"r\", .encoding = null, .errors = null }") },
    .{ "hook_compressed", h.c("null") }, .{ "hook_encoded", h.c("null") },
});
