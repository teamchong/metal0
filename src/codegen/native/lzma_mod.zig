/// Python lzma module - LZMA/XZ compression
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "compress", genPassthrough }, .{ "decompress", genPassthrough },
    .{ "open", genNullPtr }, .{ "LZMAFile", genNullPtr },
    .{ "LZMACompressor", genCompressor }, .{ "LZMADecompressor", genDecompressor },
    .{ "is_check_supported", genTrue },
    .{ "FORMAT_AUTO", genI32_0 }, .{ "CHECK_NONE", genI32_0 },
    .{ "FORMAT_XZ", genI32_1 }, .{ "CHECK_CRC32", genI32_1 },
    .{ "FORMAT_ALONE", genI32_2 }, .{ "FORMAT_RAW", genI32_3 },
    .{ "CHECK_CRC64", genI32_4 }, .{ "PRESET_DEFAULT", genI32_6 },
    .{ "CHECK_SHA256", genI32_10 }, .{ "CHECK_ID_MAX", genI32_15 }, .{ "CHECK_UNKNOWN", genI32_16 },
    .{ "PRESET_EXTREME", genPresetExtreme },
    .{ "FILTER_LZMA1", genFilterLzma1 }, .{ "FILTER_LZMA2", genI64_33 },
    .{ "FILTER_DELTA", genI64_3 }, .{ "FILTER_X86", genI64_4 },
    .{ "FILTER_ARM", genI64_7 }, .{ "FILTER_ARMTHUMB", genI64_8 }, .{ "FILTER_SPARC", genI64_9 },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genNullPtr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?*anyopaque, null)"); }
fn genTrue(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "true"); }
fn genI32_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
fn genI32_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 1)"); }
fn genI32_2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 2)"); }
fn genI32_3(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 3)"); }
fn genI32_4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 4)"); }
fn genI32_6(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 6)"); }
fn genI32_10(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 10)"); }
fn genI32_15(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 15)"); }
fn genI32_16(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 16)"); }
fn genPresetExtreme(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0x80000000)"); }
fn genI64_3(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0x03)"); }
fn genI64_4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0x04)"); }
fn genI64_7(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0x07)"); }
fn genI64_8(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0x08)"); }
fn genI64_9(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0x09)"); }
fn genI64_33(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0x21)"); }
fn genFilterLzma1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0x4000000000000001)"); }
fn genCompressor(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .compress = struct { fn f(data: []const u8) []const u8 { return data; } }.f, .flush = struct { fn f() []const u8 { return \"\"; } }.f }"); }
fn genDecompressor(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .decompress = struct { fn f(data: []const u8) []const u8 { return data; } }.f, .eof = true, .needs_input = false, .unused_data = \"\" }"); }

fn genPassthrough(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\"");
}
