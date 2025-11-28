/// Python _codecs_tw module - Taiwan codecs
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _codecs_tw.getcodec(name)
pub fn genGetcodec(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"big5\" }");
}
