/// Python traceback module - Print or retrieve a stack traceback
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "print_tb", genConst("{}") }, .{ "print_exception", genConst("{}") }, .{ "print_exc", genConst("{}") },
    .{ "print_last", genConst("{}") }, .{ "print_stack", genConst("{}") }, .{ "clear_frames", genConst("{}") },
    .{ "extract_tb", genConst("&[_]struct { filename: []const u8, lineno: i64, name: []const u8, line: []const u8 }{}") },
    .{ "extract_stack", genConst("&[_]struct { filename: []const u8, lineno: i64, name: []const u8, line: []const u8 }{}") },
    .{ "walk_tb", genConst("&[_]struct { frame: ?*anyopaque, lineno: i64 }{}") },
    .{ "walk_stack", genConst("&[_]struct { frame: ?*anyopaque, lineno: i64 }{}") },
    .{ "format_list", genConst("&[_][]const u8{}") }, .{ "format_exception_only", genConst("&[_][]const u8{}") },
    .{ "format_exception", genConst("&[_][]const u8{}") }, .{ "format_tb", genConst("&[_][]const u8{}") }, .{ "format_stack", genConst("&[_][]const u8{}") },
    .{ "format_exc", genConst("\"\"") },
    .{ "TracebackException", genConst("struct { exc_type: []const u8 = \"\", exc_value: []const u8 = \"\", stack: []struct { filename: []const u8, lineno: i64, name: []const u8 } = &.{}, cause: ?*@This() = null, context: ?*@This() = null, pub fn format(__self: *@This()) [][]const u8 { _ = __self; return &[_][]const u8{}; } pub fn format_exception_only(__self: *@This()) [][]const u8 { _ = __self; return &[_][]const u8{}; } pub fn from_exception(exc: anytype) @This() { _ = exc; return @This(){}; } }{}") },
    .{ "StackSummary", genConst("struct { frames: []struct { filename: []const u8, lineno: i64, name: []const u8, line: []const u8 } = &.{}, pub fn extract(tb: anytype) @This() { _ = tb; return @This(){}; } pub fn from_list(frames: anytype) @This() { _ = frames; return @This(){}; } pub fn format(__self: *@This()) [][]const u8 { _ = __self; return &[_][]const u8{}; } }{}") },
    .{ "FrameSummary", genConst("struct { filename: []const u8 = \"\", lineno: i64 = 0, name: []const u8 = \"\", line: []const u8 = \"\", locals: ?hashmap_helper.StringHashMap([]const u8) = null }{}") },
});
