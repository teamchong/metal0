/// Python lib2to3 module - Python 2 to 3 conversion library
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "main", h.c("0") }, .{ "refactoring_tool", h.c(".{}") }, .{ "base_fix", h.c(".{}") },
    .{ "base", h.c(".{}") }, .{ "node", h.c(".{}") }, .{ "leaf", h.c(".{}") },
    .{ "python_grammar", h.c(".{}") }, .{ "python_grammar_no_print_statement", h.c(".{}") },
});
