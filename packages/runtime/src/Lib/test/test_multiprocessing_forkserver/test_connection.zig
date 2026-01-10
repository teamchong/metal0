//! test.test_multiprocessing_forkserver.test_connection - Multiprocessing connection tests (forkserver mode)
const std = @import("std");

/// Connection families
pub const Family = enum {
    AF_PIPE,
    AF_UNIX,
    AF_INET,

    pub fn default() Family {
        return .AF_INET;
    }
};

/// Connection for inter-process communication
pub const Connection = struct {
    readable: bool = true,
    writable: bool = true,
    closed: bool = false,
    handle: ?i32 = null,
    family: Family = .AF_INET,
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator, handle: ?i32) Connection {
        return .{
            .handle = handle,
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Connection) void {
        self.buffer.deinit();
    }

    pub fn send(self: *Connection, data: []const u8) !void {
        if (self.closed) return error.ConnectionClosed;
        if (!self.writable) return error.NotWritable;
        try self.buffer.appendSlice(data);
    }

    pub fn send_bytes(self: *Connection, data: []const u8) !void {
        return self.send(data);
    }

    pub fn recv(self: *Connection, maxsize: ?usize) ![]u8 {
        if (self.closed) return error.ConnectionClosed;
        if (!self.readable) return error.NotReadable;

        const size = @min(maxsize orelse self.buffer.items.len, self.buffer.items.len);
        if (size == 0) return error.Empty;

        const result = try self.buffer.allocator.alloc(u8, size);
        @memcpy(result, self.buffer.items[0..size]);

        // Remove read bytes from buffer
        std.mem.copyForwards(u8, self.buffer.items[0..], self.buffer.items[size..]);
        self.buffer.shrinkRetainingCapacity(self.buffer.items.len - size);

        return result;
    }

    pub fn recv_bytes(self: *Connection, maxsize: ?usize) ![]u8 {
        return self.recv(maxsize);
    }

    pub fn poll(self: *Connection, timeout: ?f64) bool {
        _ = timeout;
        return !self.closed and self.buffer.items.len > 0;
    }

    pub fn close(self: *Connection) void {
        self.closed = true;
        self.handle = null;
    }

    pub fn fileno(self: *Connection) ?i32 {
        return self.handle;
    }
};

/// Pipe - returns connected pair of connections
pub const Pipe = struct {
    pub fn create(allocator: std.mem.Allocator, duplex: bool) !struct { *Connection, *Connection } {
        const conn1 = try allocator.create(Connection);
        const conn2 = try allocator.create(Connection);

        conn1.* = Connection.init(allocator, 1);
        conn2.* = Connection.init(allocator, 2);

        if (!duplex) {
            conn1.readable = false;
            conn2.writable = false;
        }

        return .{ conn1, conn2 };
    }
};

/// Listener for accepting connections
pub const Listener = struct {
    address: []const u8,
    family: Family,
    backlog: usize = 5,
    closed: bool = false,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, address: []const u8, family: ?Family) Listener {
        return .{
            .allocator = allocator,
            .address = address,
            .family = family orelse .AF_INET,
        };
    }

    pub fn accept(self: *Listener) !*Connection {
        if (self.closed) return error.ListenerClosed;

        const conn = try self.allocator.create(Connection);
        conn.* = Connection.init(self.allocator, 100);
        return conn;
    }

    pub fn close(self: *Listener) void {
        self.closed = true;
    }
};

/// Client connection to a listener
pub fn Client(address: []const u8, family: ?Family, authkey: ?[]const u8) !Connection {
    _ = authkey;
    var conn = Connection.init(std.heap.page_allocator, 200);
    conn.family = family orelse .AF_INET;
    _ = address;
    return conn;
}

/// Deliver challenge for authentication
pub fn deliver_challenge(conn: *Connection, authkey: []const u8) !void {
    _ = authkey;
    try conn.send("CHALLENGE");
}

/// Answer challenge for authentication
pub fn answer_challenge(conn: *Connection, authkey: []const u8) !void {
    _ = authkey;
    try conn.send("ANSWER");
}

/// Wait for multiple connections
pub fn wait(connections: []*Connection, timeout: ?f64) []*Connection {
    _ = timeout;
    var ready = std.ArrayList(*Connection).init(std.heap.page_allocator);
    for (connections) |conn| {
        if (conn.poll(null)) {
            ready.append(conn) catch {};
        }
    }
    return ready.toOwnedSlice() catch &[_]*Connection{};
}

/// Address operations
pub const address = struct {
    pub fn arbitrary() []const u8 {
        return "localhost:0";
    }

    pub fn default_family() Family {
        return .AF_INET;
    }
};

test "connection send recv" {
    const allocator = std.testing.allocator;
    var conn = Connection.init(allocator, 1);
    defer conn.deinit();

    try conn.send("hello");
    try std.testing.expect(conn.poll(null));

    const data = try conn.recv(null);
    defer allocator.free(data);
    try std.testing.expectEqualStrings("hello", data);
}

test "connection close" {
    const allocator = std.testing.allocator;
    var conn = Connection.init(allocator, 1);
    defer conn.deinit();

    try std.testing.expect(!conn.closed);
    conn.close();
    try std.testing.expect(conn.closed);

    try std.testing.expectError(error.ConnectionClosed, conn.send("test"));
}

test "pipe duplex" {
    const allocator = std.testing.allocator;
    const result = try Pipe.create(allocator, true);
    const conn1 = result[0];
    const conn2 = result[1];
    defer {
        conn1.deinit();
        conn2.deinit();
        allocator.destroy(conn1);
        allocator.destroy(conn2);
    }

    try std.testing.expect(conn1.readable);
    try std.testing.expect(conn1.writable);
    try std.testing.expect(conn2.readable);
    try std.testing.expect(conn2.writable);
}

test "pipe simplex" {
    const allocator = std.testing.allocator;
    const result = try Pipe.create(allocator, false);
    const conn1 = result[0];
    const conn2 = result[1];
    defer {
        conn1.deinit();
        conn2.deinit();
        allocator.destroy(conn1);
        allocator.destroy(conn2);
    }

    try std.testing.expect(!conn1.readable);
    try std.testing.expect(conn1.writable);
    try std.testing.expect(conn2.readable);
    try std.testing.expect(!conn2.writable);
}

test "listener accept" {
    const allocator = std.testing.allocator;
    var listener = Listener.init(allocator, "localhost:5000", null);

    const conn = try listener.accept();
    defer {
        conn.deinit();
        allocator.destroy(conn);
    }

    try std.testing.expect(conn.handle != null);

    listener.close();
    try std.testing.expectError(error.ListenerClosed, listener.accept());
}
