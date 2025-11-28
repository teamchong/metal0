/// Python xdrlib module - XDR data encoding/decoding
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate xdrlib.Packer class
pub fn genPacker(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .data = \"\" }");
}

/// Generate xdrlib.Unpacker(data)
pub fn genUnpacker(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const data = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .data = data, .pos = @as(i32, 0) }; }");
    } else {
        try self.emit(".{ .data = \"\", .pos = @as(i32, 0) }");
    }
}

// ============================================================================
// Exceptions
// ============================================================================

pub fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.XdrError");
}

pub fn genConversionError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.ConversionError");
}
