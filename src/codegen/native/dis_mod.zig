/// Python dis module - Disassembler for Python bytecode
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "dis", h.c("{}") }, .{ "disassemble", h.c("{}") }, .{ "distb", h.c("{}") }, .{ "disco", h.c("{}") },
    .{ "code_info", h.c("\"\"") }, .{ "show_code", h.c("{}") },
    .{ "get_instructions", h.c("&[_]@TypeOf(.{ .opname = \"\", .opcode = @as(i32, 0), .arg = @as(i32, 0), .argval = @as(?*anyopaque, null), .argrepr = \"\", .offset = @as(i32, 0), .starts_line = @as(?i32, null), .is_jump_target = false }){}") },
    .{ "findlinestarts", h.c("&[_]struct { offset: i32, line: i32 }{}") },
    .{ "findlabels", h.c("&[_]i32{}") },
    .{ "stack_effect", h.I32(0) },
    .{ "Bytecode", h.c(".{ .codeobj = @as(?*anyopaque, null), .first_line = @as(i32, 0), .current_offset = @as(?i32, null) }") },
    .{ "Instruction", h.c(".{ .opname = \"\", .opcode = @as(i32, 0), .arg = @as(i32, 0), .argval = @as(?*anyopaque, null), .argrepr = \"\", .offset = @as(i32, 0), .starts_line = @as(?i32, null), .is_jump_target = false }") },
    .{ "HAVE_ARGUMENT", h.I32(90) }, .{ "EXTENDED_ARG", h.I32(144) },
});
