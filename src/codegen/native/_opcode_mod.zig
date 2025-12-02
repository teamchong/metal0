/// Python _opcode module - Internal opcode support
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "stack_effect", h.I32(0) }, .{ "is_valid", h.c("true") }, .{ "has_arg", h.c("true") },
    .{ "has_const", h.c("false") }, .{ "has_name", h.c("false") }, .{ "has_jump", h.c("false") },
    .{ "has_free", h.c("false") }, .{ "has_local", h.c("false") }, .{ "has_exc", h.c("false") },
});
