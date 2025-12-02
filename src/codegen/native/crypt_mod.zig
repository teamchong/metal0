/// Python crypt module - Function to check Unix passwords
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "crypt", genCrypt }, .{ "mksalt", genMksalt },
    .{ "METHOD_SHA512", genMethodSHA512 }, .{ "METHOD_SHA256", genMethodSHA256 },
    .{ "METHOD_BLOWFISH", genMethodBlowfish }, .{ "METHOD_MD5", genMethodMD5 },
    .{ "METHOD_CRYPT", genMethodCrypt }, .{ "methods", genMethods },
});

fn genCrypt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const word = "); try self.genExpr(args[0]); try self.emit("; _ = word; break :blk \"$6$rounds=5000$salt$hash\"; }"); }
    else { try self.emit("\"\""); }
}
fn genMksalt(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"$6$rounds=5000$\""); }
fn genMethodSHA512(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"SHA512\", .ident = \"$6$\", .salt_chars = 16, .total_size = 106 }"); }
fn genMethodSHA256(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"SHA256\", .ident = \"$5$\", .salt_chars = 16, .total_size = 63 }"); }
fn genMethodBlowfish(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"BLOWFISH\", .ident = \"$2b$\", .salt_chars = 22, .total_size = 59 }"); }
fn genMethodMD5(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"MD5\", .ident = \"$1$\", .salt_chars = 8, .total_size = 34 }"); }
fn genMethodCrypt(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"CRYPT\", .ident = \"\", .salt_chars = 2, .total_size = 13 }"); }
fn genMethods(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "metal0_runtime.PyList(@TypeOf(.{ .name = \"\", .ident = \"\", .salt_chars = @as(i32, 0), .total_size = @as(i32, 0) })).init()"); }
