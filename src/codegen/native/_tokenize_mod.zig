/// Python _tokenize module - Internal tokenize support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _tokenize.TokenInfo class
pub fn genTokenInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .type = 0, .string = \"\", .start = .{ 0, 0 }, .end = .{ 0, 0 }, .line = \"\" }");
}

/// Generate _tokenize.tokenize(readline)
pub fn genTokenize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]@TypeOf(.{ .type = 0, .string = \"\", .start = .{ 0, 0 }, .end = .{ 0, 0 }, .line = \"\" }){}");
}

/// Generate _tokenize.generate_tokens(readline)
pub fn genGenerateTokens(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]@TypeOf(.{ .type = 0, .string = \"\", .start = .{ 0, 0 }, .end = .{ 0, 0 }, .line = \"\" }){}");
}

/// Generate _tokenize.detect_encoding(readline)
pub fn genDetectEncoding(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ \"utf-8\", &[_][]const u8{} }");
}

/// Generate _tokenize.untokenize(iterable)
pub fn genUntokenize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate _tokenize.open(filename)
pub fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate _tokenize.TokenError exception
pub fn genTokenError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.TokenError");
}

/// Generate _tokenize.StopTokenizing exception
pub fn genStopTokenizing(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.StopTokenizing");
}

/// Generate _tokenize.ENCODING constant
pub fn genENCODING(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 62)");
}

/// Generate _tokenize.COMMENT constant
pub fn genCOMMENT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 60)");
}

/// Generate _tokenize.NL constant
pub fn genNL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 61)");
}
