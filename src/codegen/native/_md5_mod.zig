/// Python _md5 module - Internal MD5 support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "md5", genMd5 }, .{ "update", genUnit }, .{ "digest", genDigest }, .{ "hexdigest", genHex }, .{ "copy", genMd5 },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genMd5(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"md5\", .digest_size = 16, .block_size = 64 }"); }
fn genDigest(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\\x00\" ** 16"); }
fn genHex(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"0\" ** 32"); }
