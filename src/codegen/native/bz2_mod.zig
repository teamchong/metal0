/// Python bz2 module - Bzip2 compression library
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "compress", genPassthrough }, .{ "decompress", genPassthrough }, .{ "open", genConst("@as(?*anyopaque, null)") }, .{ "BZ2File", genConst("@as(?*anyopaque, null)") },
    .{ "BZ2Compressor", genConst(".{ .compress = struct { fn f(data: []const u8) []const u8 { return data; } }.f, .flush = struct { fn f() []const u8 { return \"\"; } }.f }") },
    .{ "BZ2Decompressor", genConst(".{ .decompress = struct { fn f(data: []const u8) []const u8 { return data; } }.f, .eof = true, .needs_input = false, .unused_data = \"\" }") },
});

fn genPassthrough(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) { try self.genExpr(args[0]); } else { try self.emit("\"\""); } }
