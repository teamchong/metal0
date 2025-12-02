/// Python imaplib module - IMAP4 protocol client
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genIMAP4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .host = \"\", .port = @as(i32, 143), .state = \"LOGOUT\", .capabilities = &[_][]const u8{} }"); }
fn genIMAP4_SSL(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .host = \"\", .port = @as(i32, 993), .state = \"LOGOUT\", .capabilities = &[_][]const u8{} }"); }
fn genIMAP4_stream(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .host = \"\", .state = \"LOGOUT\" }"); }
fn genPort(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 143)"); }
fn genSslPort(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 993)"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?*anyopaque, null)"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genEmptyArr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{}"); }
fn genErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.IMAP4Error"); }
fn genAbort(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.IMAP4Abort"); }
fn genReadonly(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.IMAP4Readonly"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "IMAP4", genIMAP4 }, .{ "IMAP4_SSL", genIMAP4_SSL }, .{ "IMAP4_stream", genIMAP4_stream },
    .{ "IMAP4_PORT", genPort }, .{ "IMAP4_SSL_PORT", genSslPort }, .{ "Commands", genNull },
    .{ "IMAP4.error", genErr }, .{ "IMAP4.abort", genAbort }, .{ "IMAP4.readonly", genReadonly },
    .{ "Internaldate2tuple", genNull }, .{ "Int2AP", genEmptyStr }, .{ "ParseFlags", genEmptyArr }, .{ "Time2Internaldate", genEmptyStr },
});
