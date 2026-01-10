//! multiprocessing.resource_sharer - Resource sharing between processes
//! Reference: cpython/Lib/multiprocessing/resource_sharer.py
//!
//! CPython __all__: ['stop']
//!                  + ['DupSocket'] on platforms with socket support
//!                  + ['DupFd'] on Unix
//!
//! Provides mechanisms for sharing resources (file descriptors, sockets)
//! between processes.

const std = @import("std");
const builtin = @import("builtin");
const reduction = @import("reduction.zig");

// Re-export DupFd from reduction
pub const DupFd = reduction.DupFd;

// ============================================================================
// Constants
// ============================================================================

/// Timeout for resource transfers
pub const TIMEOUT: f64 = 20.0;

// ============================================================================
// DupSocket
// ============================================================================

/// CPython: class DupSocket
/// Wrapper for sharing sockets between processes
pub const DupSocket = struct {
    const Self = @This();

    fd: std.posix.fd_t,
    family: i32,
    sock_type: i32,
    protocol: i32,

    pub fn init(socket_fd: std.posix.fd_t) Self {
        return .{
            .fd = socket_fd,
            .family = std.posix.AF.INET,
            .sock_type = std.posix.SOCK.STREAM,
            .protocol = 0,
        };
    }

    pub fn initFull(socket_fd: std.posix.fd_t, family: i32, sock_type: i32, protocol: i32) Self {
        return .{
            .fd = socket_fd,
            .family = family,
            .sock_type = sock_type,
            .protocol = protocol,
        };
    }

    /// CPython: def detach(self)
    pub fn detach(self: *Self) std.posix.fd_t {
        const fd = self.fd;
        self.fd = -1;
        return fd;
    }

    /// CPython: def share(self, process_id)
    pub fn share(self: *Self, process_id: std.posix.pid_t) ![]const u8 {
        _ = process_id;
        // Return serialized socket info
        // In practice, this would use platform-specific sharing mechanisms
        return std.mem.asBytes(&self.fd);
    }

    /// CPython: @staticmethod def fromshare(data)
    pub fn fromShare(data: []const u8) !Self {
        if (data.len < @sizeOf(std.posix.fd_t)) {
            return error.InvalidData;
        }
        const fd = std.mem.bytesToValue(std.posix.fd_t, data[0..@sizeOf(std.posix.fd_t)]);
        return Self.init(fd);
    }
};

// ============================================================================
// ResourceSharer
// ============================================================================

/// CPython: class _ResourceSharer
/// Manages sharing of resources between processes
pub const ResourceSharer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    address: ?[]const u8,
    listener: ?std.posix.fd_t,
    thread: ?std.Thread,
    running: bool,
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .address = null,
            .listener = null,
            .thread = null,
            .running = false,
            .mutex = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.stop();
        if (self.listener) |fd| {
            std.posix.close(fd);
        }
    }

    /// CPython: def start(self, obj)
    pub fn start(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.running) return;

        // Create listener socket
        const sock = try std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0);
        self.listener = sock;
        self.running = true;

        // Start server thread
        self.thread = try std.Thread.spawn(.{}, serverLoop, .{self});
    }

    fn serverLoop(self: *Self) void {
        while (self.running) {
            if (self.listener) |listener| {
                // Accept connections and handle resource transfers
                var addr: std.posix.sockaddr.un = undefined;
                var addr_len: std.posix.socklen_t = @sizeOf(@TypeOf(addr));

                const client = std.posix.accept(listener, @ptrCast(&addr), &addr_len) catch continue;
                defer std.posix.close(client);

                // Handle transfer
                self.handleTransfer(client) catch continue;
            }
        }
    }

    fn handleTransfer(self: *Self, client: std.posix.fd_t) !void {
        _ = self;
        // Read request and send resource
        var buf: [1024]u8 = undefined;
        _ = try std.posix.read(client, &buf);
        // Process request and send response
    }

    /// CPython: def stop(self, timeout=None)
    pub fn stop(self: *Self) void {
        self.mutex.lock();
        self.running = false;
        self.mutex.unlock();

        if (self.thread) |t| {
            t.join();
            self.thread = null;
        }
    }

    /// CPython: def get_address(self)
    pub fn getAddress(self: *Self) ?[]const u8 {
        return self.address;
    }
};

// ============================================================================
// Global Resource Sharer
// ============================================================================

var _resource_sharer: ?ResourceSharer = null;
var _resource_sharer_lock: std.Thread.Mutex = .{};

/// Get global resource sharer
pub fn getResourceSharer(allocator: std.mem.Allocator) *ResourceSharer {
    _resource_sharer_lock.lock();
    defer _resource_sharer_lock.unlock();

    if (_resource_sharer == null) {
        _resource_sharer = ResourceSharer.init(allocator);
    }
    return &_resource_sharer.?;
}

/// CPython: def stop(timeout=TIMEOUT)
pub fn stop() void {
    _resource_sharer_lock.lock();
    defer _resource_sharer_lock.unlock();

    if (_resource_sharer) |*rs| {
        rs.stop();
    }
}

// ============================================================================
// Tests
// ============================================================================

test "DupSocket" {
    var sock = DupSocket.init(42);
    const fd = sock.detach();
    try std.testing.expectEqual(@as(std.posix.fd_t, 42), fd);
    try std.testing.expectEqual(@as(std.posix.fd_t, -1), sock.fd);
}

test "ResourceSharer init" {
    const allocator = std.testing.allocator;
    var rs = ResourceSharer.init(allocator);
    defer rs.deinit();

    try std.testing.expect(!rs.running);
    try std.testing.expect(rs.listener == null);
}
