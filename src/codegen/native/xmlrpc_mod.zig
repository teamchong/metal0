/// Python xmlrpc module - XML-RPC client/server
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

// ============================================================================
// xmlrpc.client
// ============================================================================

/// Generate xmlrpc.client.ServerProxy class
pub fn genServerProxy(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const uri = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .uri = uri, .allow_none = false, .use_datetime = false, .use_builtin_types = false }; }");
    } else {
        try self.emit(".{ .uri = \"\", .allow_none = false, .use_datetime = false, .use_builtin_types = false }");
    }
}

/// Generate xmlrpc.client.Transport class
pub fn genTransport(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .use_datetime = false, .use_builtin_types = false }");
}

/// Generate xmlrpc.client.SafeTransport class
pub fn genSafeTransport(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .use_datetime = false, .use_builtin_types = false }");
}

/// Generate xmlrpc.client.dumps(params, methodname=None, ...)
pub fn genDumps(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"<?xml version='1.0'?><methodCall></methodCall>\"");
}

/// Generate xmlrpc.client.loads(data, use_datetime=False, use_builtin_types=False)
pub fn genLoads(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .params = &[_]@TypeOf(@as(i32, 0)){}, .method_name = @as(?[]const u8, null) }");
}

/// Generate xmlrpc.client.gzip_encode(data)
pub fn genGzip_encode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate xmlrpc.client.gzip_decode(data)
pub fn genGzip_decode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

// ============================================================================
// xmlrpc.server
// ============================================================================

/// Generate xmlrpc.server.SimpleXMLRPCServer class
pub fn genSimpleXMLRPCServer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .addr = .{ \"\", @as(i32, 8000) }, .allow_none = false, .encoding = @as(?[]const u8, null) }");
}

/// Generate xmlrpc.server.CGIXMLRPCRequestHandler class
pub fn genCGIXMLRPCRequestHandler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .allow_none = false, .encoding = @as(?[]const u8, null) }");
}

/// Generate xmlrpc.server.SimpleXMLRPCRequestHandler class
pub fn genSimpleXMLRPCRequestHandler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate xmlrpc.server.DocXMLRPCServer class
pub fn genDocXMLRPCServer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .addr = .{ \"\", @as(i32, 8000) } }");
}

/// Generate xmlrpc.server.DocCGIXMLRPCRequestHandler class
pub fn genDocCGIXMLRPCRequestHandler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

// ============================================================================
// Exceptions
// ============================================================================

pub fn genFault(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.Fault");
}

pub fn genProtocolError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.ProtocolError");
}

pub fn genResponseError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.ResponseError");
}

// ============================================================================
// Marshalling type wrappers
// ============================================================================

pub fn genBoolean(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("false");
    }
}

pub fn genDateTime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .year = @as(i32, 1970), .month = @as(i32, 1), .day = @as(i32, 1), .hour = @as(i32, 0), .minute = @as(i32, 0), .second = @as(i32, 0) }");
}

pub fn genBinary(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"\"");
    }
}

// ============================================================================
// Constants
// ============================================================================

pub fn genMAXINT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 2147483647)");
}

pub fn genMININT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, -2147483648)");
}
