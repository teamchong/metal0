/// Python socketserver module - Framework for network servers
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "BaseServer", h.c(".{ .server_address = .{ \"0.0.0.0\", 0 }, .RequestHandlerClass = null }") },
    .{ "TCPServer", h.discard(".{ .server_address = .{ \"0.0.0.0\", 0 }, .socket = null, .allow_reuse_address = false, .request_queue_size = 5 }") },
    .{ "UDPServer", h.discard(".{ .server_address = .{ \"0.0.0.0\", 0 }, .socket = null, .allow_reuse_address = false, .max_packet_size = 8192 }") },
    .{ "UnixStreamServer", h.c(".{ .server_address = \"\", .socket = null }") },
    .{ "UnixDatagramServer", h.c(".{ .server_address = \"\", .socket = null }") },
    .{ "ForkingMixIn", h.c(".{ .timeout = 300, .active_children = null, .max_children = 40, .block_on_close = true }") },
    .{ "ThreadingMixIn", h.c(".{ .daemon_threads = false, .block_on_close = true }") },
    .{ "ForkingTCPServer", h.c(".{ .server_address = .{ \"0.0.0.0\", 0 }, .socket = null }") },
    .{ "ForkingUDPServer", h.c(".{ .server_address = .{ \"0.0.0.0\", 0 }, .socket = null }") },
    .{ "ThreadingTCPServer", h.c(".{ .server_address = .{ \"0.0.0.0\", 0 }, .socket = null }") },
    .{ "ThreadingUDPServer", h.c(".{ .server_address = .{ \"0.0.0.0\", 0 }, .socket = null }") },
    .{ "ThreadingUnixStreamServer", h.c(".{ .server_address = \"\" }") },
    .{ "ThreadingUnixDatagramServer", h.c(".{ .server_address = \"\" }") },
    .{ "BaseRequestHandler", h.c(".{ .request = null, .client_address = null, .server = null }") },
    .{ "StreamRequestHandler", h.c(".{ .request = null, .client_address = null, .server = null, .rfile = null, .wfile = null, .rbufsize = -1, .wbufsize = 0, .timeout = null, .disable_nagle_algorithm = false }") },
    .{ "DatagramRequestHandler", h.c(".{ .request = null, .client_address = null, .server = null, .rfile = null, .wfile = null }") },
    .{ "serve_forever", h.c("{}") }, .{ "shutdown", h.c("{}") }, .{ "handle_request", h.c("{}") }, .{ "server_close", h.c("{}") },
});

