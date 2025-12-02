/// Python compileall module - Byte-compile Python libraries
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "compile_dir", h.c("true") }, .{ "compile_file", h.c("true") },
    .{ "compile_path", h.c("true") }, .{ "PycInvalidationMode", h.I32(1) },
});
