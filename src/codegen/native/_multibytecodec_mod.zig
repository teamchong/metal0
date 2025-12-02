/// Python _multibytecodec module - Multi-byte codec support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "multibyte_codec", genCodec }, .{ "multibyte_incremental_encoder", genIncCodec }, .{ "multibyte_incremental_decoder", genIncCodec },
    .{ "multibyte_stream_reader", genStream }, .{ "multibyte_stream_writer", genStream }, .{ "create_codec", genCodec },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genCodec(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"\" }"); }
fn genIncCodec(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .codec = null, .errors = \"strict\" }"); }
fn genStream(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .stream = null, .errors = \"strict\" }"); }
