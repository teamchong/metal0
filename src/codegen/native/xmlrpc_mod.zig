/// Python xmlrpc module - XML-RPC client/server
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genTransport(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .use_datetime = false, .use_builtin_types = false }"); }
fn genDumps(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"<?xml version='1.0'?><methodCall></methodCall>\""); }
fn genLoads(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .params = &[_]@TypeOf(@as(i32, 0)){}, .method_name = @as(?[]const u8, null) }"); }
fn genFault(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.Fault"); }
fn genProtocolError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.ProtocolError"); }
fn genResponseError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.ResponseError"); }
fn genDateTime(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .year = @as(i32, 1970), .month = @as(i32, 1), .day = @as(i32, 1), .hour = @as(i32, 0), .minute = @as(i32, 0), .second = @as(i32, 0) }"); }
fn genMAXINT(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 2147483647)"); }
fn genMININT(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, -2147483648)"); }
fn genSimpleServer(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .addr = .{ \"\", @as(i32, 8000) }, .allow_none = false, .encoding = @as(?[]const u8, null) }"); }
fn genCGIHandler(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .allow_none = false, .encoding = @as(?[]const u8, null) }"); }
fn genDocServer(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .addr = .{ \"\", @as(i32, 8000) } }"); }

pub const ClientFuncs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "ServerProxy", genServerProxy }, .{ "Transport", genTransport }, .{ "SafeTransport", genTransport },
    .{ "dumps", genDumps }, .{ "loads", genLoads }, .{ "gzip_encode", genEmptyStr }, .{ "gzip_decode", genEmptyStr },
    .{ "Fault", genFault }, .{ "ProtocolError", genProtocolError }, .{ "ResponseError", genResponseError },
    .{ "Boolean", genBoolean }, .{ "DateTime", genDateTime }, .{ "Binary", genBinary },
    .{ "MAXINT", genMAXINT }, .{ "MININT", genMININT },
});

pub const ServerFuncs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "SimpleXMLRPCServer", genSimpleServer }, .{ "CGIXMLRPCRequestHandler", genCGIHandler },
    .{ "SimpleXMLRPCRequestHandler", genEmpty }, .{ "DocXMLRPCServer", genDocServer }, .{ "DocCGIXMLRPCRequestHandler", genEmpty },
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
