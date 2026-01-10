//! xmlrpc.client - XML-RPC client library
//! Reference: cpython/Lib/xmlrpc/client.py
//!
//! CPython __all__: ServerProxy, Server, Transport, SafeTransport,
//!                  Fault, ResponseError, dumps, loads, gzip_encode, gzip_decode
//!
//! XML-RPC client-side implementation.

const std = @import("std");

/// XML-RPC Fault exception
pub const Fault = struct {
    fault_code: i32,
    fault_string: []const u8,

    pub fn format(self: Fault, allocator: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "<Fault {d}: '{s}'>", .{ self.fault_code, self.fault_string });
    }
};

/// Protocol error
pub const ProtocolError = struct {
    url: []const u8,
    errcode: i32,
    errmsg: []const u8,
    headers: ?std.StringHashMap([]const u8),
};

/// XML-RPC data types
pub const Value = union(enum) {
    nil,
    boolean: bool,
    int: i32,
    double: f64,
    string: []const u8,
    base64: []const u8,
    datetime: []const u8, // ISO 8601 format
    array: std.ArrayList(Value),
    @"struct": std.StringHashMap(Value),
};

/// Transport class for making HTTP requests
pub const Transport = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    user_agent: []const u8,
    accept_gzip: bool,
    timeout: ?u32, // milliseconds

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .user_agent = "metal0-xmlrpc/1.0",
            .accept_gzip = true,
            .timeout = null,
        };
    }

    /// Make a request
    pub fn request(self: *Self, host: []const u8, handler: []const u8, request_body: []const u8) ![]const u8 {
        _ = self;
        _ = host;
        _ = handler;
        _ = request_body;
        // Would make HTTP POST request here
        return error.NotImplemented;
    }
};

/// Safe (HTTPS) transport
pub const SafeTransport = struct {
    transport: Transport,

    pub fn init(allocator: std.mem.Allocator) SafeTransport {
        return .{ .transport = Transport.init(allocator) };
    }
};

/// Server proxy for making XML-RPC calls
pub const ServerProxy = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    uri: []const u8,
    transport: Transport,
    encoding: []const u8,
    allow_none: bool,

    pub fn init(allocator: std.mem.Allocator, uri: []const u8) Self {
        return .{
            .allocator = allocator,
            .uri = uri,
            .transport = Transport.init(allocator),
            .encoding = "utf-8",
            .allow_none = false,
        };
    }

    /// Call a remote method
    pub fn call(self: *Self, method: []const u8, params: []const Value) !Value {
        const request_body = try dumps(self.allocator, method, params, self.encoding, self.allow_none);
        defer self.allocator.free(request_body);

        // Parse URI to get host and path
        // Make request via transport
        // Parse response
        _ = self;
        return error.NotImplemented;
    }
};

/// Alias for ServerProxy
pub const Server = ServerProxy;

/// Encode XML-RPC request
pub fn dumps(allocator: std.mem.Allocator, method_name: ?[]const u8, params: []const Value, encoding: []const u8, allow_none: bool) ![]const u8 {
    _ = encoding;
    _ = allow_none;

    var output: std.ArrayList(u8) = .{};
    errdefer output.deinit(allocator);

    try output.appendSlice(allocator, "<?xml version='1.0'?>\n");

    if (method_name) |name| {
        try output.appendSlice(allocator, "<methodCall>\n");
        try output.appendSlice(allocator, "<methodName>");
        try output.appendSlice(allocator, name);
        try output.appendSlice(allocator, "</methodName>\n");
        try output.appendSlice(allocator, "<params>\n");

        for (params) |param| {
            try output.appendSlice(allocator, "<param>\n");
            try encodeValue(allocator, &output, param);
            try output.appendSlice(allocator, "</param>\n");
        }

        try output.appendSlice(allocator, "</params>\n");
        try output.appendSlice(allocator, "</methodCall>\n");
    } else {
        // Response
        try output.appendSlice(allocator, "<methodResponse>\n");
        try output.appendSlice(allocator, "<params>\n");
        for (params) |param| {
            try output.appendSlice(allocator, "<param>\n");
            try encodeValue(allocator, &output, param);
            try output.appendSlice(allocator, "</param>\n");
        }
        try output.appendSlice(allocator, "</params>\n");
        try output.appendSlice(allocator, "</methodResponse>\n");
    }

    return output.toOwnedSlice(allocator);
}

fn encodeValue(allocator: std.mem.Allocator, output: *std.ArrayList(u8), value: Value) !void {
    try output.appendSlice(allocator, "<value>");

    switch (value) {
        .nil => try output.appendSlice(allocator, "<nil/>"),
        .boolean => |b| {
            try output.appendSlice(allocator, "<boolean>");
            try output.appendSlice(allocator, if (b) "1" else "0");
            try output.appendSlice(allocator, "</boolean>");
        },
        .int => |i| {
            try output.appendSlice(allocator, "<int>");
            var buf: [16]u8 = undefined;
            const str = std.fmt.bufPrint(&buf, "{d}", .{i}) catch unreachable;
            try output.appendSlice(allocator, str);
            try output.appendSlice(allocator, "</int>");
        },
        .double => |d| {
            try output.appendSlice(allocator, "<double>");
            var buf: [32]u8 = undefined;
            const str = std.fmt.bufPrint(&buf, "{d}", .{d}) catch unreachable;
            try output.appendSlice(allocator, str);
            try output.appendSlice(allocator, "</double>");
        },
        .string => |s| {
            try output.appendSlice(allocator, "<string>");
            // Escape XML special chars
            for (s) |c| {
                switch (c) {
                    '<' => try output.appendSlice(allocator, "&lt;"),
                    '>' => try output.appendSlice(allocator, "&gt;"),
                    '&' => try output.appendSlice(allocator, "&amp;"),
                    else => try output.append(allocator, c),
                }
            }
            try output.appendSlice(allocator, "</string>");
        },
        .base64 => |b| {
            try output.appendSlice(allocator, "<base64>");
            try output.appendSlice(allocator, b);
            try output.appendSlice(allocator, "</base64>");
        },
        .datetime => |dt| {
            try output.appendSlice(allocator, "<dateTime.iso8601>");
            try output.appendSlice(allocator, dt);
            try output.appendSlice(allocator, "</dateTime.iso8601>");
        },
        .array => |arr| {
            try output.appendSlice(allocator, "<array><data>");
            for (arr.items) |item| {
                try encodeValue(allocator, output, item);
            }
            try output.appendSlice(allocator, "</data></array>");
        },
        .@"struct" => |s| {
            try output.appendSlice(allocator, "<struct>");
            var iter = s.iterator();
            while (iter.next()) |entry| {
                try output.appendSlice(allocator, "<member><name>");
                try output.appendSlice(allocator, entry.key_ptr.*);
                try output.appendSlice(allocator, "</name>");
                try encodeValue(allocator, output, entry.value_ptr.*);
                try output.appendSlice(allocator, "</member>");
            }
            try output.appendSlice(allocator, "</struct>");
        },
    }

    try output.appendSlice(allocator, "</value>\n");
}

/// Decode XML-RPC response
pub fn loads(allocator: std.mem.Allocator, data: []const u8) !Value {
    _ = allocator;
    _ = data;
    // Would parse XML here
    return .nil;
}

/// Gzip encode data
pub fn gzip_encode(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
    _ = allocator;
    _ = data;
    return error.NotImplemented;
}

/// Gzip decode data
pub fn gzip_decode(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
    _ = allocator;
    _ = data;
    return error.NotImplemented;
}

// ============================================================================
// Tests
// ============================================================================

test "Fault format" {
    const allocator = std.testing.allocator;
    const fault = Fault{ .fault_code = 404, .fault_string = "Not found" };
    const formatted = try fault.format(allocator);
    defer allocator.free(formatted);
    try std.testing.expectEqualStrings("<Fault 404: 'Not found'>", formatted);
}

test "ServerProxy init" {
    const allocator = std.testing.allocator;
    const proxy = ServerProxy.init(allocator, "http://example.com/RPC2");
    try std.testing.expectEqualStrings("http://example.com/RPC2", proxy.uri);
}

test "dumps basic" {
    const allocator = std.testing.allocator;
    const params = [_]Value{.{ .int = 42 }};
    const result = try dumps(allocator, "test.method", &params, "utf-8", false);
    defer allocator.free(result);
    try std.testing.expect(std.mem.indexOf(u8, result, "methodCall") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "test.method") != null);
}
