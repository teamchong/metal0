/// Python ftplib module - FTP protocol client
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genFTP(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .host = \"\", .port = @as(i32, 21), .timeout = @as(f64, -1.0), .source_address = @as(?[]const u8, null), .encoding = \"utf-8\" }"); }
fn genPort(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 21)"); }
fn genErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.FTPError"); }
fn genReplyErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.FTPReplyError"); }
fn genTempErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.FTPTempError"); }
fn genPermErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.FTPPermError"); }
fn genProtoErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.FTPProtoError"); }
fn genAllErrs(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]type{ error.FTPError, error.FTPReplyError, error.FTPTempError, error.FTPPermError, error.FTPProtoError }"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "FTP", genFTP }, .{ "FTP_TLS", genFTP }, .{ "FTP_PORT", genPort },
    .{ "error", genErr }, .{ "error_reply", genReplyErr }, .{ "error_temp", genTempErr },
    .{ "error_perm", genPermErr }, .{ "error_proto", genProtoErr }, .{ "all_errors", genAllErrs },
});
