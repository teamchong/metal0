/// Python ftplib module - FTP protocol client
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "FTP", genConst(".{ .host = \"\", .port = @as(i32, 21), .timeout = @as(f64, -1.0), .source_address = @as(?[]const u8, null), .encoding = \"utf-8\" }") },
    .{ "FTP_TLS", genConst(".{ .host = \"\", .port = @as(i32, 21), .timeout = @as(f64, -1.0), .source_address = @as(?[]const u8, null), .encoding = \"utf-8\" }") },
    .{ "FTP_PORT", genConst("@as(i32, 21)") },
    .{ "error", genConst("error.FTPError") }, .{ "error_reply", genConst("error.FTPReplyError") }, .{ "error_temp", genConst("error.FTPTempError") },
    .{ "error_perm", genConst("error.FTPPermError") }, .{ "error_proto", genConst("error.FTPProtoError") },
    .{ "all_errors", genConst("&[_]type{ error.FTPError, error.FTPReplyError, error.FTPTempError, error.FTPPermError, error.FTPProtoError }") },
});
