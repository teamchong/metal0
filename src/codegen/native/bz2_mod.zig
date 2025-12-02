/// Python bz2 module - Bzip2 compression library
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "compress", genPassthrough }, .{ "decompress", genPassthrough }, .{ "open", genNull }, .{ "BZ2File", genNull },
    .{ "BZ2Compressor", genCompressor }, .{ "BZ2Decompressor", genDecompressor },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?*anyopaque, null)"); }
fn genCompressor(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .compress = struct { fn f(data: []const u8) []const u8 { return data; } }.f, .flush = struct { fn f() []const u8 { return \"\"; } }.f }"); }
fn genDecompressor(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .decompress = struct { fn f(data: []const u8) []const u8 { return data; } }.f, .eof = true, .needs_input = false, .unused_data = \"\" }"); }
fn genPassthrough(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) { try self.genExpr(args[0]); } else { try self.emit("\"\""); } }
