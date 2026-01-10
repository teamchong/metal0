//! wsgiref.simple_server - Simple WSGI HTTP server
//! Reference: cpython/Lib/wsgiref/simple_server.py
//!
//! CPython __all__: WSGIServer, WSGIRequestHandler, demo_app, make_server
//!
//! A simple HTTP server that can serve WSGI applications.

const std = @import("std");
const wsgiref = @import("../wsgiref.zig");

// Re-export core types from parent
pub const WsgiError = wsgiref.WsgiError;
pub const Environ = wsgiref.Environ;
pub const ResponseHeaders = wsgiref.ResponseHeaders;
pub const SimpleServer = wsgiref.SimpleServer;

// Re-export utility functions
pub const parseRequestLine = wsgiref.parseRequestLine;
pub const buildEnviron = wsgiref.buildEnviron;
pub const formatStatus = wsgiref.formatStatus;
pub const isValidHeaderName = wsgiref.isValidHeaderName;
pub const isValidHeaderValue = wsgiref.isValidHeaderValue;

// Re-export demo app
pub const demo_app = wsgiref.demo_app;

/// Server software name
pub const server_version = "WSGIServer/0.2";

/// Default host
pub const default_host = "127.0.0.1";

/// Default port
pub const default_port: u16 = 8000;

// ============================================================================
// WSGIServer - alias for SimpleServer
// ============================================================================

pub const WSGIServer = SimpleServer;

// ============================================================================
// Factory function
// ============================================================================

/// Create a new WSGI server
pub fn make_server(allocator: std.mem.Allocator, host: []const u8, port: u16) SimpleServer {
    return SimpleServer.init(allocator, host, port);
}

// ============================================================================
// Tests
// ============================================================================

test "make_server" {
    const allocator = std.testing.allocator;
    var server = make_server(allocator, "localhost", 8080);
    defer server.deinit();

    try std.testing.expectEqualStrings("localhost", server.host);
    try std.testing.expectEqual(@as(u16, 8080), server.port);
}

test "server_version" {
    try std.testing.expect(std.mem.indexOf(u8, server_version, "WSGI") != null);
}
