/// Python _bz2 module - Internal BZ2 support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "b_z2_compressor", genConst(".{ .compresslevel = 9 }") }, .{ "b_z2_decompressor", genConst(".{ .eof = false, .needs_input = true, .unused_data = \"\" }") },
    .{ "compress", genConst("\"\"") }, .{ "flush", genConst("\"\"") }, .{ "decompress", genConst("\"\"") },
});
