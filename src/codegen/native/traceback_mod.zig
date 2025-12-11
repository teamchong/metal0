/// Python traceback module - Print or retrieve a stack traceback
const std = @import("std");
const h = @import("mod_helper.zig");

/// Frame struct type for extract_tb/extract_stack return
const FrameStruct = "&[_]struct { filename: []const u8, lineno: i64, name: []const u8, line: []const u8 }{}";
const WalkStruct = "&[_]struct { frame: ?*anyopaque, lineno: i64 }{}";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    // Functions that take arguments - use discard() to suppress unused variable warnings
    .{ "print_tb", h.discard("{}") },
    .{ "print_exception", h.discard("{}") },
    .{ "print_exc", h.c("{}") }, // No args
    .{ "print_last", h.c("{}") }, // No args
    .{ "print_stack", h.c("{}") }, // No args
    .{ "clear_frames", h.discard("{}") },
    .{ "extract_tb", h.discard(FrameStruct) },
    .{ "extract_stack", h.c(FrameStruct) }, // No args (optional)
    .{ "walk_tb", h.discard(WalkStruct) },
    .{ "walk_stack", h.c(WalkStruct) }, // No args (optional)
    .{ "format_list", h.discard("&[_][]const u8{}") },
    .{ "format_exception_only", h.discard("&[_][]const u8{}") },
    .{ "format_exception", h.discard("&[_][]const u8{}") },
    .{ "format_tb", h.discard("&[_][]const u8{}") },
    .{ "format_stack", h.c("&[_][]const u8{}") }, // No args (optional)
    .{ "format_exc", h.c("\"\"") }, // No args
    .{ "TracebackException", h.c("struct { exc_type: []const u8 = \"\", exc_value: []const u8 = \"\", stack: []struct { filename: []const u8, lineno: i64, name: []const u8 } = &.{}, cause: ?*@This() = null, context: ?*@This() = null, pub fn format(__self: *@This()) [][]const u8 { _ = __self; return &[_][]const u8{}; } pub fn format_exception_only(__self: *@This()) [][]const u8 { _ = __self; return &[_][]const u8{}; } pub fn from_exception(exc: anytype) @This() { _ = exc; return @This(){}; } }{}") },
    .{ "StackSummary", h.c("struct { frames: []struct { filename: []const u8, lineno: i64, name: []const u8, line: []const u8 } = &.{}, pub fn extract(tb: anytype) @This() { _ = tb; return @This(){}; } pub fn from_list(frames: anytype) @This() { _ = frames; return @This(){}; } pub fn format(__self: *@This()) [][]const u8 { _ = __self; return &[_][]const u8{}; } }{}") },
    .{ "FrameSummary", h.c("struct { filename: []const u8 = \"\", lineno: i64 = 0, name: []const u8 = \"\", line: []const u8 = \"\", locals: ?hashmap_helper.StringHashMap([]const u8) = null }{}") },
});
