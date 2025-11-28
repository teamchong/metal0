/// Python tokenize module - Tokenizer for Python source
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

// ============================================================================
// Main Functions
// ============================================================================

/// Generate tokenize.tokenize(readline)
pub fn genTokenize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("pyaot_runtime.PyList(@TypeOf(.{ .type = @as(i32, 0), .string = \"\", .start = .{ @as(i32, 0), @as(i32, 0) }, .end = .{ @as(i32, 0), @as(i32, 0) }, .line = \"\" })).init()");
}

/// Generate tokenize.generate_tokens(readline)
pub fn genGenerate_tokens(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("pyaot_runtime.PyList(@TypeOf(.{ .type = @as(i32, 0), .string = \"\", .start = .{ @as(i32, 0), @as(i32, 0) }, .end = .{ @as(i32, 0), @as(i32, 0) }, .line = \"\" })).init()");
}

/// Generate tokenize.detect_encoding(readline)
pub fn genDetect_encoding(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ \"utf-8\", pyaot_runtime.PyList([]const u8).init() }");
}

/// Generate tokenize.open(filename)
pub fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk std.fs.cwd().openFile(path, .{}) catch null; }");
    } else {
        try self.emit("@as(?std.fs.File, null)");
    }
}

/// Generate tokenize.untokenize(iterable)
pub fn genUntokenize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

// ============================================================================
// Token Info
// ============================================================================

/// Generate tokenize.TokenInfo
pub fn genTokenInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .type = @as(i32, 0), .string = \"\", .start = .{ @as(i32, 0), @as(i32, 0) }, .end = .{ @as(i32, 0), @as(i32, 0) }, .line = \"\" }");
}

// ============================================================================
// Exceptions
// ============================================================================

pub fn genTokenError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.TokenError");
}

pub fn genStopTokenizing(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.StopTokenizing");
}

// ============================================================================
// Special tokens re-exported
// ============================================================================

pub fn genENDMARKER(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

pub fn genNAME(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genNUMBER(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

pub fn genSTRING(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 3)");
}

pub fn genNEWLINE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 4)");
}

pub fn genINDENT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 5)");
}

pub fn genDEDENT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 6)");
}

pub fn genOP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 54)");
}

pub fn genERRORTOKEN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 59)");
}

pub fn genCOMMENT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 60)");
}

pub fn genNL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 61)");
}

pub fn genENCODING(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 62)");
}

pub fn genN_TOKENS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 63)");
}
