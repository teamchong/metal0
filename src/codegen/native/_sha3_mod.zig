/// Python _sha3 module - Internal SHA3 support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "sha3_224", genSha3_224 }, .{ "sha3_256", genSha3_256 }, .{ "sha3_384", genSha3_384 }, .{ "sha3_512", genSha3_512 },
    .{ "shake128", genShake128 }, .{ "shake256", genShake256 },
    .{ "update", genUnit }, .{ "digest", genDigest }, .{ "hexdigest", genHexdigest }, .{ "copy", genSha3_256 },
    .{ "shake_digest", genEmptyStr }, .{ "shake_hexdigest", genEmptyStr },
});

fn genSha3_224(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"sha3_224\", .digest_size = 28, .block_size = 144 }"); }
fn genSha3_256(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"sha3_256\", .digest_size = 32, .block_size = 136 }"); }
fn genSha3_384(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"sha3_384\", .digest_size = 48, .block_size = 104 }"); }
fn genSha3_512(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"sha3_512\", .digest_size = 64, .block_size = 72 }"); }
fn genShake128(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"shake_128\", .digest_size = 0, .block_size = 168 }"); }
fn genShake256(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"shake_256\", .digest_size = 0, .block_size = 136 }"); }
fn genDigest(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\\x00\" ** 32"); }
fn genHexdigest(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"0\" ** 64"); }
