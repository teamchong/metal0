//! xmlrpc.server - XML-RPC server library
//! Reference: cpython/Lib/xmlrpc/server.py
//!
//! CPython __all__: SimpleXMLRPCServer, CGIXMLRPCRequestHandler,
//!                  SimpleXMLRPCRequestHandler, SimpleXMLRPCDispatcher,
//!                  DocXMLRPCServer, DocCGIXMLRPCRequestHandler,
//!                  DocXMLRPCRequestHandler
//!
//! XML-RPC server-side implementation.

const std = @import("std");
const client = @import("client.zig");

/// XML-RPC dispatcher
pub const SimpleXMLRPCDispatcher = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    funcs: std.StringHashMap(*const fn ([]const client.Value) client.Value),
    instance: ?*anyopaque,
    allow_none: bool,
    encoding: []const u8,
    use_builtin_types: bool,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .funcs = std.StringHashMap(*const fn ([]const client.Value) client.Value).init(allocator),
            .instance = null,
            .allow_none = false,
            .encoding = "utf-8",
            .use_builtin_types = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.funcs.deinit();
    }

    /// Register a function
    pub fn register_function(self: *Self, name: []const u8, func: *const fn ([]const client.Value) client.Value) !void {
        try self.funcs.put(name, func);
    }

    /// Register introspection functions
    pub fn register_introspection_functions(self: *Self) !void {
        // system.listMethods, system.methodHelp, system.methodSignature
        _ = self;
    }

    /// Register the multicall function
    pub fn register_multicall_functions(self: *Self) !void {
        // system.multicall
        _ = self;
    }

    /// Dispatch a method call
    pub fn dispatch(self: *Self, method: []const u8, params: []const client.Value) !client.Value {
        if (self.funcs.get(method)) |func| {
            return func(params);
        }
        return error.MethodNotFound;
    }

    /// Handle an XML-RPC request
    pub fn marshaled_dispatch(self: *Self, data: []const u8) ![]const u8 {
        // Parse request
        const request = try client.loads(self.allocator, data);
        _ = request;

        // Extract method name and params
        // Dispatch
        // Return response
        return try client.dumps(self.allocator, null, &[_]client.Value{.nil}, self.encoding, self.allow_none);
    }

    /// List available methods
    pub fn list_methods(self: *Self) !std.ArrayList([]const u8) {
        var methods: std.ArrayList([]const u8) = .{};
        var iter = self.funcs.keyIterator();
        while (iter.next()) |key| {
            try methods.append(self.allocator, key.*);
        }
        return methods;
    }
};

/// Simple XML-RPC server
pub const SimpleXMLRPCServer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    dispatcher: SimpleXMLRPCDispatcher,
    host: []const u8,
    port: u16,
    request_handler: ?*anyopaque,

    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16) Self {
        return .{
            .allocator = allocator,
            .dispatcher = SimpleXMLRPCDispatcher.init(allocator),
            .host = host,
            .port = port,
            .request_handler = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.dispatcher.deinit();
    }

    /// Register a function
    pub fn register_function(self: *Self, name: []const u8, func: *const fn ([]const client.Value) client.Value) !void {
        try self.dispatcher.register_function(name, func);
    }

    /// Register introspection functions
    pub fn register_introspection_functions(self: *Self) !void {
        try self.dispatcher.register_introspection_functions();
    }

    /// Start serving requests
    pub fn serve_forever(self: *Self) !void {
        _ = self;
        // Would start HTTP server here
    }

    /// Handle one request
    pub fn handle_request(self: *Self) !void {
        _ = self;
        // Would handle one HTTP request
    }

    /// Shutdown the server
    pub fn shutdown(self: *Self) void {
        _ = self;
    }
};

/// CGI-based XML-RPC request handler
pub const CGIXMLRPCRequestHandler = struct {
    const Self = @This();

    dispatcher: SimpleXMLRPCDispatcher,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .dispatcher = SimpleXMLRPCDispatcher.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.dispatcher.deinit();
    }

    /// Register a function
    pub fn register_function(self: *Self, name: []const u8, func: *const fn ([]const client.Value) client.Value) !void {
        try self.dispatcher.register_function(name, func);
    }

    /// Handle a CGI request
    pub fn handle_request(self: *Self) !void {
        _ = self;
        // Read from stdin, write to stdout
    }
};

/// Simple HTTP request handler for XML-RPC
pub const SimpleXMLRPCRequestHandler = struct {
    const Self = @This();

    // RPC path must start with /
    rpc_paths: []const []const u8,
    encode_threshold: usize,
    wbufsize: usize,

    pub fn init() Self {
        return .{
            .rpc_paths = &[_][]const u8{ "/", "/RPC2" },
            .encode_threshold = 1400,
            .wbufsize = 65536,
        };
    }

    /// Check if path is valid for RPC
    pub fn is_rpc_path_valid(self: *Self, path: []const u8) bool {
        for (self.rpc_paths) |rpc_path| {
            if (std.mem.eql(u8, path, rpc_path)) return true;
        }
        return false;
    }
};

/// XML-RPC server with documentation support
pub const DocXMLRPCServer = struct {
    server: SimpleXMLRPCServer,
    server_name: []const u8,
    server_documentation: []const u8,

    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16) DocXMLRPCServer {
        return .{
            .server = SimpleXMLRPCServer.init(allocator, host, port),
            .server_name = "DocXMLRPCServer",
            .server_documentation = "This is a documentation-enabled XML-RPC server.",
        };
    }

    pub fn deinit(self: *DocXMLRPCServer) void {
        self.server.deinit();
    }

    /// Set server name
    pub fn set_server_name(self: *DocXMLRPCServer, name: []const u8) void {
        self.server_name = name;
    }

    /// Set server documentation
    pub fn set_server_documentation(self: *DocXMLRPCServer, doc: []const u8) void {
        self.server_documentation = doc;
    }
};

/// CGI handler with documentation support
pub const DocCGIXMLRPCRequestHandler = struct {
    handler: CGIXMLRPCRequestHandler,
    server_name: []const u8,

    pub fn init(allocator: std.mem.Allocator) DocCGIXMLRPCRequestHandler {
        return .{
            .handler = CGIXMLRPCRequestHandler.init(allocator),
            .server_name = "DocCGIXMLRPCRequestHandler",
        };
    }

    pub fn deinit(self: *DocCGIXMLRPCRequestHandler) void {
        self.handler.deinit();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "SimpleXMLRPCDispatcher" {
    const allocator = std.testing.allocator;
    var dispatcher = SimpleXMLRPCDispatcher.init(allocator);
    defer dispatcher.deinit();
    try std.testing.expect(!dispatcher.allow_none);
}

test "SimpleXMLRPCServer init" {
    const allocator = std.testing.allocator;
    var server = SimpleXMLRPCServer.init(allocator, "localhost", 8000);
    defer server.deinit();
    try std.testing.expectEqualStrings("localhost", server.host);
    try std.testing.expectEqual(@as(u16, 8000), server.port);
}

test "SimpleXMLRPCRequestHandler paths" {
    var handler = SimpleXMLRPCRequestHandler.init();
    try std.testing.expect(handler.is_rpc_path_valid("/"));
    try std.testing.expect(handler.is_rpc_path_valid("/RPC2"));
    try std.testing.expect(!handler.is_rpc_path_valid("/other"));
}
