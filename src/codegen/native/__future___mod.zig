/// Python __future__ module - Future statement definitions
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "annotations", h.c(".{ .compiler_flag = 0x100000 }") },
    .{ "division", h.c(".{ .compiler_flag = 0x2000 }") },
    .{ "absolute_import", h.c(".{ .compiler_flag = 0x4000 }") },
    .{ "with_statement", h.c(".{ .compiler_flag = 0x8000 }") },
    .{ "print_function", h.c(".{ .compiler_flag = 0x10000 }") },
    .{ "unicode_literals", h.c(".{ .compiler_flag = 0x20000 }") },
    .{ "generator_stop", h.c(".{ .compiler_flag = 0x80000 }") },
    .{ "nested_scopes", h.c(".{ .compiler_flag = 0x10 }") },
    .{ "generators", h.c(".{ .compiler_flag = 0x1000 }") },
});
