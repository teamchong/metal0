/// Python socketserver module - Framework for network servers
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "BaseServer", genConst(".{ .server_address = .{ \"0.0.0.0\", 0 }, .RequestHandlerClass = null }") },
    .{ "TCPServer", genTCPServer }, .{ "UDPServer", genUDPServer },
    .{ "UnixStreamServer", genConst(".{ .server_address = \"\", .socket = null }") },
    .{ "UnixDatagramServer", genConst(".{ .server_address = \"\", .socket = null }") },
    .{ "ForkingMixIn", genConst(".{ .timeout = 300, .active_children = null, .max_children = 40, .block_on_close = true }") },
    .{ "ThreadingMixIn", genConst(".{ .daemon_threads = false, .block_on_close = true }") },
    .{ "ForkingTCPServer", genConst(".{ .server_address = .{ \"0.0.0.0\", 0 }, .socket = null }") },
    .{ "ForkingUDPServer", genConst(".{ .server_address = .{ \"0.0.0.0\", 0 }, .socket = null }") },
    .{ "ThreadingTCPServer", genConst(".{ .server_address = .{ \"0.0.0.0\", 0 }, .socket = null }") },
    .{ "ThreadingUDPServer", genConst(".{ .server_address = .{ \"0.0.0.0\", 0 }, .socket = null }") },
    .{ "ThreadingUnixStreamServer", genConst(".{ .server_address = \"\" }") },
    .{ "ThreadingUnixDatagramServer", genConst(".{ .server_address = \"\" }") },
    .{ "BaseRequestHandler", genConst(".{ .request = null, .client_address = null, .server = null }") },
    .{ "StreamRequestHandler", genConst(".{ .request = null, .client_address = null, .server = null, .rfile = null, .wfile = null, .rbufsize = -1, .wbufsize = 0, .timeout = null, .disable_nagle_algorithm = false }") },
    .{ "DatagramRequestHandler", genConst(".{ .request = null, .client_address = null, .server = null, .rfile = null, .wfile = null }") },
    .{ "serve_forever", genConst("{}") }, .{ "shutdown", genConst("{}") }, .{ "handle_request", genConst("{}") }, .{ "server_close", genConst("{}") },
});

fn genTCPServer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 1) { try self.emit("blk: { const addr = "); try self.genExpr(args[0]); try self.emit("; _ = addr; break :blk .{ .server_address = .{ \"0.0.0.0\", 0 }, .socket = null, .allow_reuse_address = false, .request_queue_size = 5 }; }"); }
    else { try self.emit(".{ .server_address = .{ \"0.0.0.0\", 0 }, .socket = null, .allow_reuse_address = false, .request_queue_size = 5 }"); }
}
fn genUDPServer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 1) { try self.emit("blk: { const addr = "); try self.genExpr(args[0]); try self.emit("; _ = addr; break :blk .{ .server_address = .{ \"0.0.0.0\", 0 }, .socket = null, .allow_reuse_address = false, .max_packet_size = 8192 }; }"); }
    else { try self.emit(".{ .server_address = .{ \"0.0.0.0\", 0 }, .socket = null, .allow_reuse_address = false, .max_packet_size = 8192 }"); }
}
