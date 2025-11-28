/// Python _codecs_cn module - Chinese codecs
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _codecs_cn.getcodec(name)
pub fn genGetcodec(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .name = \"gb2312\" }");
}
