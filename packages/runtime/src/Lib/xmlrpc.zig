//! Python 'xmlrpc' module - XML-RPC client and server implementation
//!
//! Provides XML-RPC client and server classes.
//!
//! Mirrors: CPython Lib/xmlrpc/

const std = @import("std");

// ============================================================================
// Error Types
// ============================================================================

pub const XmlRpcError = error{
    ProtocolError,
    Fault,
    ParseError,
    InvalidMethod,
    IoError,
    OutOfMemory,
};

// ============================================================================
// Fault - XML-RPC fault response
// ============================================================================

/// XML-RPC Fault exception
pub const Fault = struct {
    faultCode: i32,
    faultString: []const u8,

    pub fn format(self: Fault, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "<Fault {d}: '{s}'>", .{ self.faultCode, self.faultString });
    }
};

// ============================================================================
// Value Types
// ============================================================================

/// XML-RPC value types
pub const Value = union(enum) {
    nil: void,
    boolean: bool,
    int: i32,
    double: f64,
    string: []const u8,
    base64: []const u8,
    dateTime: []const u8,
    array: std.ArrayList(Value),
    @"struct": std.StringHashMap(Value),

    pub fn deinit(self: *Value, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .array => |*arr| {
                for (arr.items) |*item| {
                    item.deinit(allocator);
                }
                arr.deinit();
            },
            .@"struct" => |*s| {
                var iter = s.iterator();
                while (iter.next()) |entry| {
                    entry.value_ptr.deinit(allocator);
                }
                s.deinit();
            },
            else => {},
        }
    }

    /// Serialize value to XML
    pub fn toXml(self: *const Value, allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        const writer = result.writer();

        try writer.writeAll("<value>");
        switch (self.*) {
            .nil => try writer.writeAll("<nil/>"),
            .boolean => |b| try writer.print("<boolean>{d}</boolean>", .{@as(u8, if (b) 1 else 0)}),
            .int => |i| try writer.print("<int>{d}</int>", .{i}),
            .double => |d| try writer.print("<double>{d}</double>", .{d}),
            .string => |s| try writer.print("<string>{s}</string>", .{s}),
            .base64 => |b| try writer.print("<base64>{s}</base64>", .{b}),
            .dateTime => |dt| try writer.print("<dateTime.iso8601>{s}</dateTime.iso8601>", .{dt}),
            .array => |arr| {
                try writer.writeAll("<array><data>");
                for (arr.items) |*item| {
                    const item_xml = try item.toXml(allocator);
                    defer allocator.free(item_xml);
                    try writer.writeAll(item_xml);
                }
                try writer.writeAll("</data></array>");
            },
            .@"struct" => |s| {
                try writer.writeAll("<struct>");
                var iter = s.iterator();
                while (iter.next()) |entry| {
                    try writer.print("<member><name>{s}</name>", .{entry.key_ptr.*});
                    const val_xml = try entry.value_ptr.toXml(allocator);
                    defer allocator.free(val_xml);
                    try writer.writeAll(val_xml);
                    try writer.writeAll("</member>");
                }
                try writer.writeAll("</struct>");
            },
        }
        try writer.writeAll("</value>");

        return result.toOwnedSlice();
    }
};

// ============================================================================
// ServerProxy - XML-RPC client
// ============================================================================

/// XML-RPC client proxy
pub const ServerProxy = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    uri: []const u8,
    transport: ?*anyopaque = null,
    encoding: []const u8 = "utf-8",
    verbose: bool = false,
    allow_none: bool = false,
    use_datetime: bool = false,
    use_builtin_types: bool = false,

    pub fn init(allocator: std.mem.Allocator, uri: []const u8) Self {
        return Self{
            .allocator = allocator,
            .uri = uri,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Make an XML-RPC call
    pub fn call(self: *Self, method: []const u8, params: []const Value) !Value {
        const request = try self.buildRequest(method, params);
        defer self.allocator.free(request);

        // In a full implementation, would send HTTP request to server
        _ = self.uri;

        // Return empty for now
        return Value{ .nil = {} };
    }

    fn buildRequest(self: *Self, method: []const u8, params: []const Value) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        const writer = result.writer();

        try writer.writeAll("<?xml version=\"1.0\"?>\n");
        try writer.writeAll("<methodCall>\n");
        try writer.print("<methodName>{s}</methodName>\n", .{method});
        try writer.writeAll("<params>\n");

        for (params) |*param| {
            try writer.writeAll("<param>");
            const param_xml = try param.toXml(self.allocator);
            defer self.allocator.free(param_xml);
            try writer.writeAll(param_xml);
            try writer.writeAll("</param>\n");
        }

        try writer.writeAll("</params>\n");
        try writer.writeAll("</methodCall>");

        return result.toOwnedSlice();
    }
};

// ============================================================================
// SimpleXMLRPCServer
// ============================================================================

/// Method handler function type
pub const MethodHandler = *const fn ([]const Value) anyerror!Value;

/// Simple XML-RPC server
pub const SimpleXMLRPCServer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
    methods: std.StringHashMap(MethodHandler),
    allow_none: bool = false,
    encoding: []const u8 = "utf-8",

    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16) Self {
        return Self{
            .allocator = allocator,
            .host = host,
            .port = port,
            .methods = std.StringHashMap(MethodHandler).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.methods.deinit();
    }

    /// Register a method
    pub fn register_function(self: *Self, func: MethodHandler, name: []const u8) !void {
        try self.methods.put(name, func);
    }

    /// Register introspection functions
    pub fn register_introspection_functions(self: *Self) void {
        _ = self;
        // Would register system.listMethods, system.methodHelp, etc.
    }

    /// Dispatch a method call
    pub fn dispatch(self: *Self, method: []const u8, params: []const Value) !Value {
        if (self.methods.get(method)) |handler| {
            return handler(params);
        }
        return error.InvalidMethod;
    }

    /// Handle a single request
    pub fn handle_request(self: *Self, request_xml: []const u8) ![]u8 {
        _ = request_xml;

        // Parse request and dispatch
        // In a full implementation, would parse XML and call dispatch

        var response = std.ArrayList(u8).init(self.allocator);
        const writer = response.writer();

        try writer.writeAll("<?xml version=\"1.0\"?>\n");
        try writer.writeAll("<methodResponse>\n");
        try writer.writeAll("<params><param><value><string>OK</string></value></param></params>\n");
        try writer.writeAll("</methodResponse>");

        return response.toOwnedSlice();
    }

    /// Start serving
    pub fn serve_forever(self: *Self) !void {
        _ = self;
        // Would bind to host:port and serve requests
    }
};

// ============================================================================
// Utility Functions
// ============================================================================

/// Escape XML special characters
pub fn escape(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    const writer = result.writer();

    for (s) |c| {
        switch (c) {
            '<' => try writer.writeAll("&lt;"),
            '>' => try writer.writeAll("&gt;"),
            '&' => try writer.writeAll("&amp;"),
            '\'' => try writer.writeAll("&apos;"),
            '"' => try writer.writeAll("&quot;"),
            else => try writer.writeByte(c),
        }
    }

    return result.toOwnedSlice();
}

/// Build a fault response
pub fn buildFaultResponse(allocator: std.mem.Allocator, code: i32, message: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    const writer = result.writer();

    try writer.writeAll("<?xml version=\"1.0\"?>\n");
    try writer.writeAll("<methodResponse>\n");
    try writer.writeAll("<fault>\n");
    try writer.writeAll("<value><struct>\n");
    try writer.print("<member><name>faultCode</name><value><int>{d}</int></value></member>\n", .{code});
    try writer.print("<member><name>faultString</name><value><string>{s}</string></value></member>\n", .{message});
    try writer.writeAll("</struct></value>\n");
    try writer.writeAll("</fault>\n");
    try writer.writeAll("</methodResponse>");

    return result.toOwnedSlice();
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

pub fn init() void {
    if (initialized) return;
    initialized = true;
}

pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "Fault format" {
    const allocator = std.testing.allocator;
    const fault = Fault{ .faultCode = 1, .faultString = "Test error" };
    const s = try fault.format(allocator);
    defer allocator.free(s);

    try std.testing.expectEqualStrings("<Fault 1: 'Test error'>", s);
}

test "Value toXml string" {
    const allocator = std.testing.allocator;
    var value = Value{ .string = "hello" };
    const xml = try value.toXml(allocator);
    defer allocator.free(xml);

    try std.testing.expectEqualStrings("<value><string>hello</string></value>", xml);
}

test "Value toXml int" {
    const allocator = std.testing.allocator;
    var value = Value{ .int = 42 };
    const xml = try value.toXml(allocator);
    defer allocator.free(xml);

    try std.testing.expectEqualStrings("<value><int>42</int></value>", xml);
}

test "Value toXml boolean" {
    const allocator = std.testing.allocator;
    var value = Value{ .boolean = true };
    const xml = try value.toXml(allocator);
    defer allocator.free(xml);

    try std.testing.expectEqualStrings("<value><boolean>1</boolean></value>", xml);
}

test "ServerProxy init" {
    const allocator = std.testing.allocator;
    var proxy = ServerProxy.init(allocator, "http://localhost:8000/RPC2");
    defer proxy.deinit();

    try std.testing.expectEqualStrings("http://localhost:8000/RPC2", proxy.uri);
}

test "SimpleXMLRPCServer init" {
    const allocator = std.testing.allocator;
    var server = SimpleXMLRPCServer.init(allocator, "localhost", 8000);
    defer server.deinit();

    try std.testing.expectEqualStrings("localhost", server.host);
    try std.testing.expectEqual(@as(u16, 8000), server.port);
}

test "escape" {
    const allocator = std.testing.allocator;
    const escaped = try escape(allocator, "<test & 'value'>");
    defer allocator.free(escaped);

    try std.testing.expectEqualStrings("&lt;test &amp; &apos;value&apos;&gt;", escaped);
}

test "buildFaultResponse" {
    const allocator = std.testing.allocator;
    const response = try buildFaultResponse(allocator, 1, "Error");
    defer allocator.free(response);

    try std.testing.expect(std.mem.indexOf(u8, response, "faultCode") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "faultString") != null);
}
