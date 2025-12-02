/// Python traceback module - Print or retrieve a stack traceback
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "print_tb", h.c("{}") }, .{ "print_exception", h.c("{}") }, .{ "print_exc", h.c("{}") },
    .{ "print_last", h.c("{}") }, .{ "print_stack", h.c("{}") }, .{ "clear_frames", h.c("{}") },
    .{ "extract_tb", h.c("&[_]struct { filename: []const u8, lineno: i64, name: []const u8, line: []const u8 }{}") },
    .{ "extract_stack", h.c("&[_]struct { filename: []const u8, lineno: i64, name: []const u8, line: []const u8 }{}") },
    .{ "walk_tb", h.c("&[_]struct { frame: ?*anyopaque, lineno: i64 }{}") },
    .{ "walk_stack", h.c("&[_]struct { frame: ?*anyopaque, lineno: i64 }{}") },
    .{ "format_list", h.c("&[_][]const u8{}") }, .{ "format_exception_only", h.c("&[_][]const u8{}") },
    .{ "format_exception", h.c("&[_][]const u8{}") }, .{ "format_tb", h.c("&[_][]const u8{}") }, .{ "format_stack", h.c("&[_][]const u8{}") },
    .{ "format_exc", h.c("\"\"") },
    .{ "TracebackException", h.c("struct { exc_type: []const u8 = \"\", exc_value: []const u8 = \"\", stack: []struct { filename: []const u8, lineno: i64, name: []const u8 } = &.{}, cause: ?*@This() = null, context: ?*@This() = null, pub fn format(__self: *@This()) [][]const u8 { _ = __self; return &[_][]const u8{}; } pub fn format_exception_only(__self: *@This()) [][]const u8 { _ = __self; return &[_][]const u8{}; } pub fn from_exception(exc: anytype) @This() { _ = exc; return @This(){}; } }{}") },
    .{ "StackSummary", h.c("struct { frames: []struct { filename: []const u8, lineno: i64, name: []const u8, line: []const u8 } = &.{}, pub fn extract(tb: anytype) @This() { _ = tb; return @This(){}; } pub fn from_list(frames: anytype) @This() { _ = frames; return @This(){}; } pub fn format(__self: *@This()) [][]const u8 { _ = __self; return &[_][]const u8{}; } }{}") },
    .{ "FrameSummary", h.c("struct { filename: []const u8 = \"\", lineno: i64 = 0, name: []const u8 = \"\", line: []const u8 = \"\", locals: ?hashmap_helper.StringHashMap([]const u8) = null }{}") },
});
