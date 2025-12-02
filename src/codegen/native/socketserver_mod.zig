/// Python socketserver module - Framework for network servers
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genServerStub(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .server_address = .{ \"0.0.0.0\", 0 }, .socket = null }"); }
fn genUnixStub(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .server_address = \"\" }"); }
fn genUnixSocketStub(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .server_address = \"\", .socket = null }"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "BaseServer", genBaseServer }, .{ "TCPServer", genTCPServer }, .{ "UDPServer", genUDPServer },
    .{ "UnixStreamServer", genUnixSocketStub }, .{ "UnixDatagramServer", genUnixSocketStub },
    .{ "ForkingMixIn", genForkingMixIn }, .{ "ThreadingMixIn", genThreadingMixIn },
    .{ "ForkingTCPServer", genServerStub }, .{ "ForkingUDPServer", genServerStub },
    .{ "ThreadingTCPServer", genServerStub }, .{ "ThreadingUDPServer", genServerStub },
    .{ "ThreadingUnixStreamServer", genUnixStub }, .{ "ThreadingUnixDatagramServer", genUnixStub },
    .{ "BaseRequestHandler", genBaseRequestHandler }, .{ "StreamRequestHandler", genStreamRequestHandler },
    .{ "DatagramRequestHandler", genDatagramRequestHandler },
    .{ "serve_forever", genUnit }, .{ "shutdown", genUnit }, .{ "handle_request", genUnit }, .{ "server_close", genUnit },
});

fn genBaseServer(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .server_address = .{ \"0.0.0.0\", 0 }, .RequestHandlerClass = null }"); }
fn genTCPServer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 1) { try self.emit("blk: { const addr = "); try self.genExpr(args[0]); try self.emit("; _ = addr; break :blk .{ .server_address = .{ \"0.0.0.0\", 0 }, .socket = null, .allow_reuse_address = false, .request_queue_size = 5 }; }"); }
    else { try genConst(self, args, ".{ .server_address = .{ \"0.0.0.0\", 0 }, .socket = null, .allow_reuse_address = false, .request_queue_size = 5 }"); }
}
fn genUDPServer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 1) { try self.emit("blk: { const addr = "); try self.genExpr(args[0]); try self.emit("; _ = addr; break :blk .{ .server_address = .{ \"0.0.0.0\", 0 }, .socket = null, .allow_reuse_address = false, .max_packet_size = 8192 }; }"); }
    else { try genConst(self, args, ".{ .server_address = .{ \"0.0.0.0\", 0 }, .socket = null, .allow_reuse_address = false, .max_packet_size = 8192 }"); }
}
fn genForkingMixIn(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .timeout = 300, .active_children = null, .max_children = 40, .block_on_close = true }"); }
fn genThreadingMixIn(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .daemon_threads = false, .block_on_close = true }"); }
fn genBaseRequestHandler(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .request = null, .client_address = null, .server = null }"); }
fn genStreamRequestHandler(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .request = null, .client_address = null, .server = null, .rfile = null, .wfile = null, .rbufsize = -1, .wbufsize = 0, .timeout = null, .disable_nagle_algorithm = false }"); }
fn genDatagramRequestHandler(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .request = null, .client_address = null, .server = null, .rfile = null, .wfile = null }"); }
