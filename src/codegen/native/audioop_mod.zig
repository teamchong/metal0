/// Python audioop module - Audio operations
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "add", genStr }, .{ "alaw2lin", genStr }, .{ "bias", genStr }, .{ "byteswap", genStr },
    .{ "lin2alaw", genStr }, .{ "lin2lin", genStr }, .{ "lin2ulaw", genStr }, .{ "mul", genStr },
    .{ "reverse", genStr }, .{ "tomono", genStr }, .{ "tostereo", genStr }, .{ "ulaw2lin", genStr },
    .{ "avg", genI32 }, .{ "avgpp", genI32 }, .{ "cross", genI32 }, .{ "findmax", genI32 },
    .{ "getsample", genI32 }, .{ "max", genI32 }, .{ "maxpp", genI32 }, .{ "rms", genI32 },
    .{ "findfactor", genF64 }, .{ "minmax", genI32Pair }, .{ "findfit", genI32F64 },
    .{ "adpcm2lin", genAdpcmState }, .{ "lin2adpcm", genAdpcmState },
    .{ "ratecv", genRatecv }, .{ "error", genError },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genI32(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
fn genF64(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(f64, 1.0)"); }
fn genI32Pair(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ @as(i32, 0), @as(i32, 0) }"); }
fn genI32F64(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ @as(i32, 0), @as(f64, 1.0) }"); }
fn genAdpcmState(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ \"\", .{ @as(i32, 0), @as(i32, 0) } }"); }
fn genRatecv(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ \"\", .{ @as(i32, 0), .{} } }"); }
fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.AudioopError"); }
