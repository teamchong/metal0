/// Python _sha2 module - Internal SHA2 support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "sha224", genSha224 }, .{ "sha256", genSha256 }, .{ "sha384", genSha384 }, .{ "sha512", genSha512 },
    .{ "update", genUnit }, .{ "digest", genDigest }, .{ "hexdigest", genHexdigest }, .{ "copy", genSha256 },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genDigest(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\\x00\" ** 32"); }
fn genHexdigest(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"0\" ** 64"); }
fn genSha224(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"sha224\", .digest_size = 28, .block_size = 64 }"); }
fn genSha256(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"sha256\", .digest_size = 32, .block_size = 64 }"); }
fn genSha384(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"sha384\", .digest_size = 48, .block_size = 128 }"); }
fn genSha512(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"sha512\", .digest_size = 64, .block_size = 128 }"); }
