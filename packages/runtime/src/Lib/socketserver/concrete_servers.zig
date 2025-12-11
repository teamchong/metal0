//! Concrete server type implementations
//!
//! Mirrors: CPython Lib/socketserver.py (ForkingTCPServer, ForkingUDPServer, ThreadingTCPServer, ThreadingUDPServer)

const tcp_server = @import("tcp_server.zig");
const udp_server = @import("udp_server.zig");
const mixins = @import("mixins.zig");

// ============================================================================
// Concrete Server Types
// ============================================================================

/// Forking TCP server
pub fn ForkingTCPServer(comptime RequestHandler: type) type {
    return mixins.ForkingMixIn(tcp_server.TCPServer(RequestHandler));
}

/// Forking UDP server
pub fn ForkingUDPServer(comptime RequestHandler: type) type {
    return mixins.ForkingMixIn(udp_server.UDPServer(RequestHandler));
}

/// Threading TCP server
pub fn ThreadingTCPServer(comptime RequestHandler: type) type {
    return mixins.ThreadingMixIn(tcp_server.TCPServer(RequestHandler));
}

/// Threading UDP server
pub fn ThreadingUDPServer(comptime RequestHandler: type) type {
    return mixins.ThreadingMixIn(udp_server.UDPServer(RequestHandler));
}
