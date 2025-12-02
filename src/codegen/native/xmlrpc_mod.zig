/// Python xmlrpc module - XML-RPC client/server
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const ClientFuncs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "ServerProxy", genServerProxy },
    .{ "Transport", genConst(".{ .use_datetime = false, .use_builtin_types = false }") },
    .{ "SafeTransport", genConst(".{ .use_datetime = false, .use_builtin_types = false }") },
    .{ "dumps", genConst("\"<?xml version='1.0'?><methodCall></methodCall>\"") },
    .{ "loads", genConst(".{ .params = &[_]@TypeOf(@as(i32, 0)){}, .method_name = @as(?[]const u8, null) }") },
    .{ "gzip_encode", genConst("\"\"") }, .{ "gzip_decode", genConst("\"\"") },
    .{ "Fault", genConst("error.Fault") }, .{ "ProtocolError", genConst("error.ProtocolError") },
    .{ "ResponseError", genConst("error.ResponseError") },
    .{ "Boolean", genBoolean }, .{ "DateTime", genConst(".{ .year = @as(i32, 1970), .month = @as(i32, 1), .day = @as(i32, 1), .hour = @as(i32, 0), .minute = @as(i32, 0), .second = @as(i32, 0) }") },
    .{ "Binary", genBinary },
    .{ "MAXINT", genConst("@as(i64, 2147483647)") }, .{ "MININT", genConst("@as(i64, -2147483648)") },
});

pub const ServerFuncs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "SimpleXMLRPCServer", genConst(".{ .addr = .{ \"\", @as(i32, 8000) }, .allow_none = false, .encoding = @as(?[]const u8, null) }") },
    .{ "CGIXMLRPCRequestHandler", genConst(".{ .allow_none = false, .encoding = @as(?[]const u8, null) }") },
    .{ "SimpleXMLRPCRequestHandler", genConst(".{}") },
    .{ "DocXMLRPCServer", genConst(".{ .addr = .{ \"\", @as(i32, 8000) } }") },
    .{ "DocCGIXMLRPCRequestHandler", genConst(".{}") },
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
