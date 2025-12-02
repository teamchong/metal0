/// Python xmlrpc module - XML-RPC client/server
const std = @import("std");
const h = @import("mod_helper.zig");

pub const ClientFuncs = std.StaticStringMap(h.H).initComptime(.{
    .{ "ServerProxy", h.wrap("blk: { const uri = ", "; break :blk .{ .uri = uri, .allow_none = false, .use_datetime = false, .use_builtin_types = false }; }", ".{ .uri = \"\", .allow_none = false, .use_datetime = false, .use_builtin_types = false }") },
    .{ "Transport", h.c(".{ .use_datetime = false, .use_builtin_types = false }") },
    .{ "SafeTransport", h.c(".{ .use_datetime = false, .use_builtin_types = false }") },
    .{ "dumps", h.c("\"<?xml version='1.0'?><methodCall></methodCall>\"") },
    .{ "loads", h.c(".{ .params = &[_]@TypeOf(@as(i32, 0)){}, .method_name = @as(?[]const u8, null) }") },
    .{ "gzip_encode", h.c("\"\"") }, .{ "gzip_decode", h.c("\"\"") },
    .{ "Fault", h.err("Fault") }, .{ "ProtocolError", h.err("ProtocolError") },
    .{ "ResponseError", h.err("ResponseError") },
    .{ "Boolean", h.pass("false") }, .{ "DateTime", h.c(".{ .year = @as(i32, 1970), .month = @as(i32, 1), .day = @as(i32, 1), .hour = @as(i32, 0), .minute = @as(i32, 0), .second = @as(i32, 0) }") },
    .{ "Binary", h.pass("\"\"") },
    .{ "MAXINT", h.I64(2147483647) }, .{ "MININT", h.I64(-2147483648) },
});

pub const ServerFuncs = std.StaticStringMap(h.H).initComptime(.{
    .{ "SimpleXMLRPCServer", h.c(".{ .addr = .{ \"\", @as(i32, 8000) }, .allow_none = false, .encoding = @as(?[]const u8, null) }") },
    .{ "CGIXMLRPCRequestHandler", h.c(".{ .allow_none = false, .encoding = @as(?[]const u8, null) }") },
    .{ "SimpleXMLRPCRequestHandler", h.c(".{}") },
    .{ "DocXMLRPCServer", h.c(".{ .addr = .{ \"\", @as(i32, 8000) } }") },
    .{ "DocCGIXMLRPCRequestHandler", h.c(".{}") },
});
