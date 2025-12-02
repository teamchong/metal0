/// Python token module - Token constants and utilities
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "ENDMARKER", h.I32(0) }, .{ "NAME", h.I32(1) }, .{ "NUMBER", h.I32(2) }, .{ "STRING", h.I32(3) },
    .{ "NEWLINE", h.I32(4) }, .{ "INDENT", h.I32(5) }, .{ "DEDENT", h.I32(6) }, .{ "OP", h.I32(54) },
    .{ "ERRORTOKEN", h.I32(59) }, .{ "COMMENT", h.I32(60) }, .{ "NL", h.I32(61) }, .{ "ENCODING", h.I32(62) },
    .{ "N_TOKENS", h.I32(63) }, .{ "NT_OFFSET", h.I32(256) },
    .{ "tok_name", h.c("metal0_runtime.PyDict(i32, []const u8).init()") },
    .{ "EXACT_TOKEN_TYPES", h.c("metal0_runtime.PyDict([]const u8, i32).init()") },
    .{ "ISTERMINAL", h.checkCond("x < 256") }, .{ "ISNONTERMINAL", h.checkCond("x >= 256") }, .{ "ISEOF", h.checkCond("x == 0") },
});
