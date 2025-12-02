/// Python imaplib module - IMAP4 protocol client
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "IMAP4", genConst(".{ .host = \"\", .port = @as(i32, 143), .state = \"LOGOUT\", .capabilities = &[_][]const u8{} }") },
    .{ "IMAP4_SSL", genConst(".{ .host = \"\", .port = @as(i32, 993), .state = \"LOGOUT\", .capabilities = &[_][]const u8{} }") },
    .{ "IMAP4_stream", genConst(".{ .host = \"\", .state = \"LOGOUT\" }") },
    .{ "IMAP4_PORT", genConst("@as(i32, 143)") }, .{ "IMAP4_SSL_PORT", genConst("@as(i32, 993)") }, .{ "Commands", genConst("@as(?*anyopaque, null)") },
    .{ "IMAP4.error", genConst("error.IMAP4Error") }, .{ "IMAP4.abort", genConst("error.IMAP4Abort") }, .{ "IMAP4.readonly", genConst("error.IMAP4Readonly") },
    .{ "Internaldate2tuple", genConst("@as(?*anyopaque, null)") }, .{ "Int2AP", genConst("\"\"") }, .{ "ParseFlags", genConst("&[_][]const u8{}") }, .{ "Time2Internaldate", genConst("\"\"") },
});
