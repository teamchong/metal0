/// Python codeop module - Compile Python code with compiler flags
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "compile_command", h.c("@as(?*anyopaque, null)") }, .{ "Compile", h.c(".{ .flags = @as(i32, 0) }") },
    .{ "CommandCompiler", h.c(".{ .compiler = .{ .flags = @as(i32, 0) } }") },
    .{ "PyCF_DONT_IMPLY_DEDENT", h.hex32(0x200) }, .{ "PyCF_ALLOW_INCOMPLETE_INPUT", h.hex32(0x4000) },
});
