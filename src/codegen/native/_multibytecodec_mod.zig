/// Python _multibytecodec module - Multi-byte codec support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "multibyte_codec", genConst(".{ .name = \"\" }") }, .{ "multibyte_incremental_encoder", genConst(".{ .codec = null, .errors = \"strict\" }") }, .{ "multibyte_incremental_decoder", genConst(".{ .codec = null, .errors = \"strict\" }") },
    .{ "multibyte_stream_reader", genConst(".{ .stream = null, .errors = \"strict\" }") }, .{ "multibyte_stream_writer", genConst(".{ .stream = null, .errors = \"strict\" }") }, .{ "create_codec", genConst(".{ .name = \"\" }") },
});
