/// Python poplib module - POP3 protocol client
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genPOP3(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .host = \"\", .port = @as(i32, 110), .timeout = @as(f64, -1.0) }"); }
fn genPOP3_SSL(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .host = \"\", .port = @as(i32, 995), .timeout = @as(f64, -1.0) }"); }
fn genPort(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 110)"); }
fn genSslPort(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 995)"); }
fn genErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.POP3ProtoError"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "POP3", genPOP3 }, .{ "POP3_SSL", genPOP3_SSL }, .{ "POP3_PORT", genPort }, .{ "POP3_SSL_PORT", genSslPort }, .{ "error_proto", genErr },
});
