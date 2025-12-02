/// Python lzma module - LZMA/XZ compression
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}
fn genI32(comptime n: comptime_int) ModuleHandler { return genConst(std.fmt.comptimePrint("@as(i32, {})", .{n})); }
fn genI64(comptime n: comptime_int) ModuleHandler { return genConst(std.fmt.comptimePrint("@as(i64, 0x{x})", .{n})); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "compress", genPassthrough }, .{ "decompress", genPassthrough },
    .{ "open", genConst("@as(?*anyopaque, null)") }, .{ "LZMAFile", genConst("@as(?*anyopaque, null)") },
    .{ "LZMACompressor", genConst(".{ .compress = struct { fn f(data: []const u8) []const u8 { return data; } }.f, .flush = struct { fn f() []const u8 { return \"\"; } }.f }") },
    .{ "LZMADecompressor", genConst(".{ .decompress = struct { fn f(data: []const u8) []const u8 { return data; } }.f, .eof = true, .needs_input = false, .unused_data = \"\" }") },
    .{ "is_check_supported", genConst("true") },
    .{ "FORMAT_AUTO", genI32(0) }, .{ "CHECK_NONE", genI32(0) },
    .{ "FORMAT_XZ", genI32(1) }, .{ "CHECK_CRC32", genI32(1) },
    .{ "FORMAT_ALONE", genI32(2) }, .{ "FORMAT_RAW", genI32(3) },
    .{ "CHECK_CRC64", genI32(4) }, .{ "PRESET_DEFAULT", genI32(6) },
    .{ "CHECK_SHA256", genI32(10) }, .{ "CHECK_ID_MAX", genI32(15) }, .{ "CHECK_UNKNOWN", genI32(16) },
    .{ "PRESET_EXTREME", genI32(0x80000000) },
    .{ "FILTER_LZMA1", genI64(0x4000000000000001) }, .{ "FILTER_LZMA2", genI64(0x21) },
    .{ "FILTER_DELTA", genI64(0x03) }, .{ "FILTER_X86", genI64(0x04) },
    .{ "FILTER_ARM", genI64(0x07) }, .{ "FILTER_ARMTHUMB", genI64(0x08) }, .{ "FILTER_SPARC", genI64(0x09) },
});

fn genPassthrough(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\"");
}
