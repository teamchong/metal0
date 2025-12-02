/// Python xdrlib module - XDR data encoding/decoding
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Packer", genPacker }, .{ "Unpacker", genUnpacker }, .{ "Error", genXdrErr }, .{ "ConversionError", genConvErr },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genPacker(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .data = \"\" }"); }
fn genXdrErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.XdrError"); }
fn genConvErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.ConversionError"); }
fn genUnpacker(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const data = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .data = data, .pos = @as(i32, 0) }; }"); } else { try self.emit(".{ .data = \"\", .pos = @as(i32, 0) }"); }
}
