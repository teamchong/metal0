/// Python __future__ module - Future statement definitions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

// ============================================================================
// Future Features
// ============================================================================

pub fn genAnnotations(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .compiler_flag = 0x100000 }");
}

pub fn genDivision(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .compiler_flag = 0x2000 }");
}

pub fn genAbsolute_import(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .compiler_flag = 0x4000 }");
}

pub fn genWith_statement(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .compiler_flag = 0x8000 }");
}

pub fn genPrint_function(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .compiler_flag = 0x10000 }");
}

pub fn genUnicode_literals(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .compiler_flag = 0x20000 }");
}

pub fn genGenerator_stop(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .compiler_flag = 0x80000 }");
}

pub fn genNested_scopes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .compiler_flag = 0x10 }");
}

pub fn genGenerators(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .compiler_flag = 0x1000 }");
}
