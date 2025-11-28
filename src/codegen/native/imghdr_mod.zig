/// Python imghdr module - Image file type determination
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate imghdr.what(file, h=None)
pub fn genWhat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Returns image type string or None
    try self.emit("@as(?[]const u8, null)");
}

/// Generate imghdr.tests list (for custom detection functions)
pub fn genTests(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]*const fn ([]const u8, *anyopaque) ?[]const u8{}");
}
