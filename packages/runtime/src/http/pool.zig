/// Connection pool for HTTP client
/// Implements connection reuse and keep-alive
const std = @import("std");

pub const Connection = struct {
    stream: std.net.Stream,
    host: []const u8,
    port: u16,
    last_used: i64,
    in_use: bool,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16) !Connection {
        const host_copy = try allocator.dupe(u8, host);
        errdefer allocator.free(host_copy);

        // Connect to host
        const address = try std.net.Address.parseIp(host, port);
        const stream = try std.net.tcpConnectToAddress(address);

        return .{
            .stream = stream,
            .host = host_copy,
            .port = port,
            .last_used = std.time.timestamp(),
            .in_use = false,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Connection) void {
        self.stream.close();
        self.allocator.free(self.host);
    }

    pub fn isAlive(self: *const Connection) bool {
        // Connection is alive if used within last 60 seconds
        const now = std.time.timestamp();
        return (now - self.last_used) < 60;
    }

    pub fn markUsed(self: *Connection) void {
        self.last_used = std.time.timestamp();
        self.in_use = true;
    }

    pub fn markIdle(self: *Connection) void {
        self.in_use = false;
    }
};

pub const ConnectionPool = struct {
    connections: std.ArrayList(Connection),
    allocator: std.mem.Allocator,
    max_connections: usize,
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator, max_connections: usize) ConnectionPool {
        return .{
            .connections = std.ArrayList(Connection).init(allocator),
            .allocator = allocator,
            .max_connections = max_connections,
            .mutex = .{},
        };
    }

    pub fn deinit(self: *ConnectionPool) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.connections.items) |*conn| {
            conn.deinit();
        }
        self.connections.deinit(self.allocator);
    }

    /// Get a connection from the pool or create a new one
    pub fn acquire(self: *ConnectionPool, host: []const u8, port: u16) !*Connection {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Try to find an existing idle connection for this host
        for (self.connections.items) |*conn| {
            if (conn.in_use) continue;
            if (!std.mem.eql(u8, conn.host, host)) continue;
            if (conn.port != port) continue;
            if (!conn.isAlive()) continue;

            conn.markUsed();
            return conn;
        }

        // Create new connection if under limit
        if (self.connections.items.len < self.max_connections) {
            var conn = try Connection.init(self.allocator, host, port);
            conn.markUsed();
            try self.connections.append(self.allocator, conn);
            return &self.connections.items[self.connections.items.len - 1];
        }

        // Wait for a connection to become available (simple blocking)
        // In production, this would use async/await
        return error.PoolExhausted;
    }

    /// Release a connection back to the pool
    pub fn release(self: *ConnectionPool, conn: *Connection) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        conn.markIdle();
    }

    /// Clean up expired connections
    pub fn cleanup(self: *ConnectionPool) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var i: usize = 0;
        while (i < self.connections.items.len) {
            const conn = &self.connections.items[i];
            if (!conn.in_use and !conn.isAlive()) {
                var removed = self.connections.orderedRemove(i);
                removed.deinit();
                continue;
            }
            i += 1;
        }
    }

    /// Get pool statistics
    pub fn stats(self: *ConnectionPool) PoolStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        var active: usize = 0;
        var idle: usize = 0;

        for (self.connections.items) |*conn| {
            if (conn.in_use) {
                active += 1;
            } else {
                idle += 1;
            }
        }

        return .{
            .total = self.connections.items.len,
            .active = active,
            .idle = idle,
            .max = self.max_connections,
        };
    }
};

pub const PoolStats = struct {
    total: usize,
    active: usize,
    idle: usize,
    max: usize,
};

/// Per-connection allocator wrapper for zero contention
pub const ConnectionAllocator = struct {
    arena: std.heap.ArenaAllocator,
    parent: std.mem.Allocator,

    pub fn init(parent: std.mem.Allocator) ConnectionAllocator {
        return .{
            .arena = std.heap.ArenaAllocator.init(parent),
            .parent = parent,
        };
    }

    pub fn deinit(self: *ConnectionAllocator) void {
        self.arena.deinit();
    }

    pub fn allocator(self: *ConnectionAllocator) std.mem.Allocator {
        return self.arena.allocator();
    }

    pub fn reset(self: *ConnectionAllocator) void {
        _ = self.arena.reset(.retain_capacity);
    }
};

test "Connection creation and lifecycle" {
    const allocator = std.testing.allocator;

    // Skip this test if network is unavailable
    var conn = Connection.init(allocator, "127.0.0.1", 8080) catch {
        return error.SkipZigTest;
    };
    defer conn.deinit();

    try std.testing.expect(conn.isAlive());
    try std.testing.expect(!conn.in_use);

    conn.markUsed();
    try std.testing.expect(conn.in_use);

    conn.markIdle();
    try std.testing.expect(!conn.in_use);
}

test "ConnectionPool basic operations" {
    const allocator = std.testing.allocator;

    var pool = ConnectionPool.init(allocator, 10);
    defer pool.deinit();

    const pool_stats = pool.stats();
    try std.testing.expectEqual(@as(usize, 0), pool_stats.total);
    try std.testing.expectEqual(@as(usize, 10), pool_stats.max);
}

test "ConnectionPool cleanup" {
    const allocator = std.testing.allocator;

    var pool = ConnectionPool.init(allocator, 10);
    defer pool.deinit();

    pool.cleanup();

    const pool_stats = pool.stats();
    try std.testing.expectEqual(@as(usize, 0), pool_stats.total);
}

test "ConnectionAllocator arena" {
    const allocator = std.testing.allocator;

    var conn_alloc = ConnectionAllocator.init(allocator);
    defer conn_alloc.deinit();

    const buf1 = try conn_alloc.allocator().alloc(u8, 100);
    _ = buf1;

    conn_alloc.reset();

    const buf2 = try conn_alloc.allocator().alloc(u8, 200);
    _ = buf2;

    // Arena should reuse memory after reset
}
