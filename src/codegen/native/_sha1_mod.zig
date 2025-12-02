/// Python _sha1 module - Internal SHA1 support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "sha1", genSha1 }, .{ "update", genUnit }, .{ "digest", genDigest }, .{ "hexdigest", genHex }, .{ "copy", genSha1 },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genSha1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"sha1\", .digest_size = 20, .block_size = 64 }"); }
fn genDigest(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\\x00\" ** 20"); }
fn genHex(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"0\" ** 40"); }
