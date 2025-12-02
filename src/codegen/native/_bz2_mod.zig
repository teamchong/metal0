/// Python _bz2 module - Internal BZ2 support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "b_z2_compressor", genComp }, .{ "b_z2_decompressor", genDecomp }, .{ "compress", genEmptyStr }, .{ "flush", genEmptyStr }, .{ "decompress", genEmptyStr },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genComp(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .compresslevel = 9 }"); }
fn genDecomp(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .eof = false, .needs_input = true, .unused_data = \"\" }"); }
