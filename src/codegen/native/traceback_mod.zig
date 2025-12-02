/// Python traceback module - Print or retrieve a stack traceback
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "print_tb", genUnit }, .{ "print_exception", genUnit }, .{ "print_exc", genUnit },
    .{ "print_last", genUnit }, .{ "print_stack", genUnit }, .{ "clear_frames", genUnit },
    .{ "extract_tb", genStackFrames }, .{ "extract_stack", genStackFrames },
    .{ "walk_tb", genWalkFrames }, .{ "walk_stack", genWalkFrames },
    .{ "format_list", genStringList }, .{ "format_exception_only", genStringList },
    .{ "format_exception", genStringList }, .{ "format_tb", genStringList }, .{ "format_stack", genStringList },
    .{ "format_exc", genEmptyStr }, .{ "TracebackException", genTracebackException },
    .{ "StackSummary", genStackSummary }, .{ "FrameSummary", genFrameSummary },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genStringList(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{}"); }
fn genStackFrames(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]struct { filename: []const u8, lineno: i64, name: []const u8, line: []const u8 }{}"); }
fn genWalkFrames(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]struct { frame: ?*anyopaque, lineno: i64 }{}"); }
fn genTracebackException(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "struct { exc_type: []const u8 = \"\", exc_value: []const u8 = \"\", stack: []struct { filename: []const u8, lineno: i64, name: []const u8 } = &.{}, cause: ?*@This() = null, context: ?*@This() = null, pub fn format(__self: *@This()) [][]const u8 { _ = __self; return &[_][]const u8{}; } pub fn format_exception_only(__self: *@This()) [][]const u8 { _ = __self; return &[_][]const u8{}; } pub fn from_exception(exc: anytype) @This() { _ = exc; return @This(){}; } }{}"); }
fn genStackSummary(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "struct { frames: []struct { filename: []const u8, lineno: i64, name: []const u8, line: []const u8 } = &.{}, pub fn extract(tb: anytype) @This() { _ = tb; return @This(){}; } pub fn from_list(frames: anytype) @This() { _ = frames; return @This(){}; } pub fn format(__self: *@This()) [][]const u8 { _ = __self; return &[_][]const u8{}; } }{}"); }
fn genFrameSummary(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "struct { filename: []const u8 = \"\", lineno: i64 = 0, name: []const u8 = \"\", line: []const u8 = \"\", locals: ?hashmap_helper.StringHashMap([]const u8) = null }{}"); }
