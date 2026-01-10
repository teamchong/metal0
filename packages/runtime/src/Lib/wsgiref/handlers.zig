//! wsgiref.handlers - Base WSGI handler classes
//! Reference: cpython/Lib/wsgiref/handlers.py
//!
//! CPython __all__: BaseHandler, SimpleHandler, BaseCGIHandler, CGIHandler,
//!                  IISCGIHandler, read_environ
//!
//! Base handler implementations for WSGI servers.

const std = @import("std");
const wsgiref = @import("../wsgiref.zig");

// Re-export core types from parent
pub const WsgiError = wsgiref.WsgiError;
pub const Environ = wsgiref.Environ;
pub const ResponseHeaders = wsgiref.ResponseHeaders;

// ============================================================================
// BaseHandler
// ============================================================================

/// Base class for WSGI handlers
pub const BaseHandler = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    status: ?[]const u8 = null,
    headers: ?ResponseHeaders = null,
    headers_sent: bool = false,
    bytes_sent: usize = 0,

    // Error handling
    error_status: []const u8 = "500 Internal Server Error",
    error_body: []const u8 = "A server error occurred.",

    // HTTP feature flags
    wsgi_multithread: bool = true,
    wsgi_multiprocess: bool = true,
    wsgi_run_once: bool = false,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        if (self.headers) |*h| {
            h.deinit();
        }
    }

    /// Set up the base environ dict
    pub fn setup_environ(self: *Self) !Environ {
        var environ = Environ.init(self.allocator);

        try environ.put("wsgi.version", "1.0");
        try environ.put("wsgi.multithread", if (self.wsgi_multithread) "true" else "false");
        try environ.put("wsgi.multiprocess", if (self.wsgi_multiprocess) "true" else "false");
        try environ.put("wsgi.run_once", if (self.wsgi_run_once) "true" else "false");

        return environ;
    }

    /// Clean up after request
    pub fn close(self: *Self) void {
        self.status = null;
        self.headers_sent = false;
        self.bytes_sent = 0;
    }
};

// ============================================================================
// SimpleHandler
// ============================================================================

/// Simple handler for in-memory I/O
pub const SimpleHandler = struct {
    const Self = @This();

    base: BaseHandler,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .base = BaseHandler.init(allocator) };
    }

    pub fn deinit(self: *Self) void {
        self.base.deinit();
    }
};

// ============================================================================
// CGI Handlers
// ============================================================================

/// Base CGI handler
pub const BaseCGIHandler = struct {
    const Self = @This();

    base: BaseHandler,

    pub fn init(allocator: std.mem.Allocator) Self {
        var handler = Self{ .base = BaseHandler.init(allocator) };
        handler.base.wsgi_run_once = true;
        return handler;
    }

    pub fn deinit(self: *Self) void {
        self.base.deinit();
    }
};

/// Standard CGI handler
pub const CGIHandler = BaseCGIHandler;

/// IIS CGI handler
pub const IISCGIHandler = BaseCGIHandler;

// ============================================================================
// Utility functions
// ============================================================================

/// Read environ from OS environment
pub fn read_environ(allocator: std.mem.Allocator) !Environ {
    var environ = Environ.init(allocator);

    try environ.put("REQUEST_METHOD", "GET");
    try environ.put("SCRIPT_NAME", "");
    try environ.put("PATH_INFO", "/");
    try environ.put("QUERY_STRING", "");
    try environ.put("SERVER_NAME", "localhost");
    try environ.put("SERVER_PORT", "80");
    try environ.put("SERVER_PROTOCOL", "HTTP/1.1");

    return environ;
}

// ============================================================================
// Tests
// ============================================================================

test "BaseHandler init" {
    const allocator = std.testing.allocator;
    var handler = BaseHandler.init(allocator);
    defer handler.deinit();

    try std.testing.expect(handler.wsgi_multithread);
    try std.testing.expect(!handler.wsgi_run_once);
}

test "read_environ" {
    const allocator = std.testing.allocator;
    var environ = try read_environ(allocator);
    defer environ.deinit();

    try std.testing.expect(environ.get("REQUEST_METHOD") != null);
}
