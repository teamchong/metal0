/// Python _multibytecodec module - Multi-byte codec support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _multibytecodec.MultibyteCodec class
pub fn genMultibyteCodec(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"\" }");
}

/// Generate _multibytecodec.MultibyteIncrementalEncoder class
pub fn genMultibyteIncrementalEncoder(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .codec = null, .errors = \"strict\" }");
}

/// Generate _multibytecodec.MultibyteIncrementalDecoder class
pub fn genMultibyteIncrementalDecoder(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .codec = null, .errors = \"strict\" }");
}

/// Generate _multibytecodec.MultibyteStreamReader class
pub fn genMultibyteStreamReader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .stream = null, .errors = \"strict\" }");
}

/// Generate _multibytecodec.MultibyteStreamWriter class
pub fn genMultibyteStreamWriter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .stream = null, .errors = \"strict\" }");
}

/// Generate _multibytecodec.__create_codec(name)
pub fn genCreateCodec(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"\" }");
}
