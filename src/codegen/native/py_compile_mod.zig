/// Python py_compile module - Compile Python source files
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "compile", h.c("@as(?[]const u8, null)") },
    .{ "main", h.I32(0) },
    .{ "PyCompileError", h.err("PyCompileError") },
    .{ "PycInvalidationMode", h.c(".{ .TIMESTAMP = @as(i32, 1), .CHECKED_HASH = @as(i32, 2), .UNCHECKED_HASH = @as(i32, 3) }") },
});
