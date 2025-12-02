/// Python opcode module - Opcode definitions for Python bytecode
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "opname", h.c("&[_][]const u8{ \"CACHE\", \"POP_TOP\", \"PUSH_NULL\", \"INTERPRETER_EXIT\", \"END_FOR\", \"END_SEND\", \"<6>\", \"<7>\", \"<8>\", \"NOP\", \"<10>\", \"UNARY_NEGATIVE\", \"UNARY_NOT\", \"<13>\", \"<14>\", \"UNARY_INVERT\", \"EXIT_INIT_CHECK\" }") },
    .{ "opmap", h.c(".{ .CACHE = 0, .POP_TOP = 1, .PUSH_NULL = 2, .INTERPRETER_EXIT = 3, .END_FOR = 4, .END_SEND = 5, .NOP = 9, .UNARY_NEGATIVE = 11, .UNARY_NOT = 12, .UNARY_INVERT = 15 }") },
    .{ "cmp_op", h.c("&[_][]const u8{ \"<\", \"<=\", \"==\", \"!=\", \">\", \">=\"}") },
    .{ "hasarg", h.c("&[_]u8{}") }, .{ "hasconst", h.c("&[_]u8{ 100 }") },
    .{ "hasname", h.c("&[_]u8{ 90, 91, 95, 96, 97, 98, 101, 106, 108, 109, 116 }") },
    .{ "hasjrel", h.c("&[_]u8{ 93, 110, 111, 112, 114, 115, 120, 149, 172 }") },
    .{ "hasjabs", h.c("&[_]u8{}") }, .{ "haslocal", h.c("&[_]u8{ 124, 125, 126, 180 }") },
    .{ "hascompare", h.c("&[_]u8{ 107 }") }, .{ "hasfree", h.c("&[_]u8{ 135, 136, 137, 138 }") },
    .{ "hasexc", h.c("&[_]u8{ 121 }") },
    .{ "HAVE_ARGUMENT", h.U8(90) }, .{ "EXTENDED_ARG", h.U8(144) },
    .{ "stack_effect", h.I32(0) }, .{ "_specialized_opmap", h.c(".{}") },
    .{ "_intrinsic_1_descs", h.c("&[_][]const u8{ \"INTRINSIC_1_INVALID\", \"INTRINSIC_PRINT\", \"INTRINSIC_IMPORT_STAR\", \"INTRINSIC_STOPITERATION_ERROR\", \"INTRINSIC_ASYNC_GEN_WRAP\", \"INTRINSIC_UNARY_POSITIVE\", \"INTRINSIC_LIST_TO_TUPLE\", \"INTRINSIC_TYPEVAR\", \"INTRINSIC_PARAMSPEC\", \"INTRINSIC_TYPEVARTUPLE\", \"INTRINSIC_SUBSCRIPT_GENERIC\", \"INTRINSIC_TYPEALIAS\" }") },
    .{ "_intrinsic_2_descs", h.c("&[_][]const u8{ \"INTRINSIC_2_INVALID\", \"INTRINSIC_PREP_RERAISE_STAR\", \"INTRINSIC_TYPEVAR_WITH_BOUND\", \"INTRINSIC_TYPEVAR_WITH_CONSTRAINTS\", \"INTRINSIC_SET_FUNCTION_TYPE_PARAMS\" }") },
});
