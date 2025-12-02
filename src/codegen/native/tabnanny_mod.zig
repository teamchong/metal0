/// Python tabnanny module - Detection of ambiguous indentation
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "check", h.c("{}") }, .{ "process_tokens", h.c("{}") },
    .{ "NannyNag", h.err("NannyNag") },
    .{ "verbose", h.I32(0) }, .{ "filename_only", h.I32(0) },
});
