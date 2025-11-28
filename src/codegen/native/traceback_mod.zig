/// Python traceback module - Print or retrieve a stack traceback
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate traceback.print_tb(tb, limit=None, file=None) -> None
pub fn genPrintTb(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate traceback.print_exception(exc, /, value=_sentinel, tb=_sentinel, ...) -> None
pub fn genPrintException(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate traceback.print_exc(limit=None, file=None, chain=True) -> None
pub fn genPrintExc(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate traceback.print_last(limit=None, file=None, chain=True) -> None
pub fn genPrintLast(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate traceback.print_stack(f=None, limit=None, file=None) -> None
pub fn genPrintStack(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate traceback.extract_tb(tb, limit=None) -> StackSummary
pub fn genExtractTb(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]struct { filename: []const u8, lineno: i64, name: []const u8, line: []const u8 }{}");
}

/// Generate traceback.extract_stack(f=None, limit=None) -> StackSummary
pub fn genExtractStack(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]struct { filename: []const u8, lineno: i64, name: []const u8, line: []const u8 }{}");
}

/// Generate traceback.format_list(extracted_list) -> list of strings
pub fn genFormatList(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{}");
}

/// Generate traceback.format_exception_only(exc, /, value=_sentinel) -> list of strings
pub fn genFormatExceptionOnly(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{}");
}

/// Generate traceback.format_exception(exc, /, value=_sentinel, tb=_sentinel, ...) -> list
pub fn genFormatException(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{}");
}

/// Generate traceback.format_exc(limit=None, chain=True) -> str
pub fn genFormatExc(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate traceback.format_tb(tb, limit=None) -> list of strings
pub fn genFormatTb(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{}");
}

/// Generate traceback.format_stack(f=None, limit=None) -> list of strings
pub fn genFormatStack(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{}");
}

/// Generate traceback.clear_frames(tb) -> None
pub fn genClearFrames(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate traceback.walk_tb(tb) -> iterator
pub fn genWalkTb(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]struct { frame: ?*anyopaque, lineno: i64 }{}");
}

/// Generate traceback.walk_stack(f) -> iterator
pub fn genWalkStack(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]struct { frame: ?*anyopaque, lineno: i64 }{}");
}

/// Generate traceback.TracebackException class
pub fn genTracebackException(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("exc_type: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("exc_value: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("stack: []struct { filename: []const u8, lineno: i64, name: []const u8 } = &.{},\n");
    try self.emitIndent();
    try self.emit("cause: ?*@This() = null,\n");
    try self.emitIndent();
    try self.emit("context: ?*@This() = null,\n");
    try self.emitIndent();
    try self.emit("pub fn format(self: *@This()) [][]const u8 { _ = self; return &[_][]const u8{}; }\n");
    try self.emitIndent();
    try self.emit("pub fn format_exception_only(self: *@This()) [][]const u8 { _ = self; return &[_][]const u8{}; }\n");
    try self.emitIndent();
    try self.emit("pub fn from_exception(exc: anytype) @This() { _ = exc; return @This(){}; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate traceback.StackSummary class
pub fn genStackSummary(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("frames: []struct { filename: []const u8, lineno: i64, name: []const u8, line: []const u8 } = &.{},\n");
    try self.emitIndent();
    try self.emit("pub fn extract(tb: anytype) @This() { _ = tb; return @This(){}; }\n");
    try self.emitIndent();
    try self.emit("pub fn from_list(frames: anytype) @This() { _ = frames; return @This(){}; }\n");
    try self.emitIndent();
    try self.emit("pub fn format(self: *@This()) [][]const u8 { _ = self; return &[_][]const u8{}; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate traceback.FrameSummary class
pub fn genFrameSummary(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("filename: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("lineno: i64 = 0,\n");
    try self.emitIndent();
    try self.emit("name: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("line: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("locals: ?hashmap_helper.StringHashMap([]const u8) = null,\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}
