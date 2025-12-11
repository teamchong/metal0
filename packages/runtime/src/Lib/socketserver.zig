//! CPython source: Lib/socketserver.py
//!
//! Provides classes for implementing network servers.
//!
//! Mirrors: CPython Lib/socketserver.py

// Re-export all submodules
pub const types = @import("socketserver/types.zig");
pub const tcp_server = @import("socketserver/tcp_server.zig");
pub const udp_server = @import("socketserver/udp_server.zig");
pub const handlers = @import("socketserver/handlers.zig");
pub const mixins = @import("socketserver/mixins.zig");
pub const concrete_servers = @import("socketserver/concrete_servers.zig");

// Re-export commonly used types
pub const BaseServer = types.BaseServer;
pub const TCPServer = tcp_server.TCPServer;
pub const UDPServer = udp_server.UDPServer;
pub const BaseRequestHandler = handlers.BaseRequestHandler;
pub const StreamRequestHandler = handlers.StreamRequestHandler;
pub const DatagramRequestHandler = handlers.DatagramRequestHandler;
pub const ForkingMixIn = mixins.ForkingMixIn;
pub const ThreadingMixIn = mixins.ThreadingMixIn;
pub const ForkingTCPServer = concrete_servers.ForkingTCPServer;
pub const ForkingUDPServer = concrete_servers.ForkingUDPServer;
pub const ThreadingTCPServer = concrete_servers.ThreadingTCPServer;
pub const ThreadingUDPServer = concrete_servers.ThreadingUDPServer;
