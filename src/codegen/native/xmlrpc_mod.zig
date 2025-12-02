/// Python xmlrpc module - XML-RPC client/server
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const ClientFuncs = std.StaticStringMap(h.H).initComptime(.{
    .{ "ServerProxy", genServerProxy },
    .{ "Transport", h.c(".{ .use_datetime = false, .use_builtin_types = false }") },
    .{ "SafeTransport", h.c(".{ .use_datetime = false, .use_builtin_types = false }") },
    .{ "dumps", h.c("\"<?xml version='1.0'?><methodCall></methodCall>\"") },
    .{ "loads", h.c(".{ .params = &[_]@TypeOf(@as(i32, 0)){}, .method_name = @as(?[]const u8, null) }") },
    .{ "gzip_encode", h.c("\"\"") }, .{ "gzip_decode", h.c("\"\"") },
    .{ "Fault", h.err("Fault") }, .{ "ProtocolError", h.err("ProtocolError") },
    .{ "ResponseError", h.err("ResponseError") },
    .{ "Boolean", genBoolean }, .{ "DateTime", h.c(".{ .year = @as(i32, 1970), .month = @as(i32, 1), .day = @as(i32, 1), .hour = @as(i32, 0), .minute = @as(i32, 0), .second = @as(i32, 0) }") },
    .{ "Binary", genBinary },
    .{ "MAXINT", h.I64(2147483647) }, .{ "MININT", h.I64(-2147483648) },
});

pub const ServerFuncs = std.StaticStringMap(h.H).initComptime(.{
    .{ "SimpleXMLRPCServer", h.c(".{ .addr = .{ \"\", @as(i32, 8000) }, .allow_none = false, .encoding = @as(?[]const u8, null) }") },
    .{ "CGIXMLRPCRequestHandler", h.c(".{ .allow_none = false, .encoding = @as(?[]const u8, null) }") },
    .{ "SimpleXMLRPCRequestHandler", h.c(".{}") },
    .{ "DocXMLRPCServer", h.c(".{ .addr = .{ \"\", @as(i32, 8000) } }") },
    .{ "DocCGIXMLRPCRequestHandler", h.c(".{}") },
});

fn genServerProxy(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const uri = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .uri = uri, .allow_none = false, .use_datetime = false, .use_builtin_types = false }; }"); } else { try self.emit(".{ .uri = \"\", .allow_none = false, .use_datetime = false, .use_builtin_types = false }"); }
}
fn genBoolean(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.genExpr(args[0]); } else { try self.emit("false"); }
}
fn genBinary(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.genExpr(args[0]); } else { try self.emit("\"\""); }
}
