/// Python uu module - UUencode/decode
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate uu.encode(in_file, out_file, name=None, mode=None, *, backtick=False)
pub fn genEncode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate uu.decode(in_file, out_file=None, mode=None, quiet=True)
pub fn genDecode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

// ============================================================================
// Exception
// ============================================================================

pub fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.UuError");
}
