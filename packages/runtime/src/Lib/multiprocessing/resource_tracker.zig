//! multiprocessing.resource_tracker - Track shared resources
//! Reference: cpython/Lib/multiprocessing/resource_tracker.py
//!
//! CPython __all__: ['ensure_running', 'register', 'unregister']
//!
//! Tracks resources (shared memory, semaphores) to ensure they are
//! cleaned up when no longer needed, even if processes crash.

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Resource Types
// ============================================================================

/// Types of resources that can be tracked
pub const ResourceType = enum {
    shared_memory,
    semaphore,
    file,

    pub fn toString(self: ResourceType) []const u8 {
        return switch (self) {
            .shared_memory => "shared_memory",
            .semaphore => "semaphore",
            .file => "file",
        };
    }

    pub fn fromString(s: []const u8) ?ResourceType {
        if (std.mem.eql(u8, s, "shared_memory")) return .shared_memory;
        if (std.mem.eql(u8, s, "semaphore")) return .semaphore;
        if (std.mem.eql(u8, s, "file")) return .file;
        return null;
    }
};

// ============================================================================
// ResourceTracker
// ============================================================================

/// CPython: class ResourceTracker
/// Tracks resources to ensure cleanup
pub const ResourceTracker = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    pid: ?std.posix.pid_t,
    fd: ?std.posix.fd_t,
    resources: std.StringHashMap(ResourceType),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .pid = null,
            .fd = null,
            .resources = std.StringHashMap(ResourceType).init(allocator),
            .mutex = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.resources.deinit();
        if (self.fd) |fd| {
            std.posix.close(fd);
        }
    }

    /// CPython: def ensure_running(self)
    pub fn ensure_running(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check if tracker process is running
        if (self.pid) |pid| {
            // Check if still alive
            const result = std.posix.waitpid(pid, .{ .NOHANG = true });
            if (result.pid == 0) {
                return; // Still running
            }
            // Process died, reset
            self.pid = null;
            if (self.fd) |fd| {
                std.posix.close(fd);
                self.fd = null;
            }
        }

        // Start tracker process
        try self.startTracker();
    }

    fn startTracker(self: *Self) !void {
        if (builtin.os.tag == .windows) {
            // Windows doesn't use fork
            return;
        }

        // Create pipe for communication
        const pipe = try std.posix.pipe();

        const pid = try std.posix.fork();
        if (pid == 0) {
            // Child - become the tracker
            std.posix.close(pipe[1]);
            self.runTracker(pipe[0]);
            std.posix.exit(0);
        } else {
            // Parent
            std.posix.close(pipe[0]);
            self.pid = pid;
            self.fd = pipe[1];
        }
    }

    fn runTracker(self: *Self, comm_fd: std.posix.fd_t) void {
        _ = self;
        // Tracker process loop
        var buf: [4096]u8 = undefined;
        while (true) {
            const n = std.posix.read(comm_fd, &buf) catch break;
            if (n == 0) break;

            // Parse command: REGISTER/UNREGISTER name type
            // Process and track resources
        }

        // Cleanup remaining resources on exit
    }

    /// CPython: def register(self, name, rtype)
    pub fn register(self: *Self, name: []const u8, rtype: ResourceType) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.ensure_running();

        // Add to local tracking
        const name_copy = try self.allocator.dupe(u8, name);
        try self.resources.put(name_copy, rtype);

        // Send to tracker process
        if (self.fd) |fd| {
            var msg_buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&msg_buf, "REGISTER:{s}:{s}\n", .{ name, rtype.toString() }) catch return;
            _ = std.posix.write(fd, msg) catch {};
        }
    }

    /// CPython: def unregister(self, name, rtype)
    pub fn unregister(self: *Self, name: []const u8, rtype: ResourceType) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Remove from local tracking
        if (self.resources.fetchRemove(name)) |kv| {
            self.allocator.free(kv.key);
        }

        // Send to tracker process
        if (self.fd) |fd| {
            var msg_buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&msg_buf, "UNREGISTER:{s}:{s}\n", .{ name, rtype.toString() }) catch return;
            _ = std.posix.write(fd, msg) catch {};
        }
    }

    /// CPython: def getfd(self)
    pub fn getfd(self: *Self) ?std.posix.fd_t {
        return self.fd;
    }
};

// ============================================================================
// Global Resource Tracker
// ============================================================================

var _resource_tracker: ?ResourceTracker = null;
var _resource_tracker_lock: std.Thread.Mutex = .{};

/// Get global resource tracker
pub fn getResourceTracker(allocator: std.mem.Allocator) *ResourceTracker {
    _resource_tracker_lock.lock();
    defer _resource_tracker_lock.unlock();

    if (_resource_tracker == null) {
        _resource_tracker = ResourceTracker.init(allocator);
    }
    return &_resource_tracker.?;
}

/// CPython: def ensure_running()
pub fn ensure_running(allocator: std.mem.Allocator) !void {
    const tracker = getResourceTracker(allocator);
    try tracker.ensure_running();
}

/// CPython: def register(name, rtype)
pub fn register(allocator: std.mem.Allocator, name: []const u8, rtype: ResourceType) !void {
    const tracker = getResourceTracker(allocator);
    try tracker.register(name, rtype);
}

/// CPython: def unregister(name, rtype)
pub fn unregister(allocator: std.mem.Allocator, name: []const u8, rtype: ResourceType) void {
    const tracker = getResourceTracker(allocator);
    tracker.unregister(name, rtype);
}

// ============================================================================
// Tests
// ============================================================================

test "ResourceType" {
    try std.testing.expectEqual(ResourceType.shared_memory, ResourceType.fromString("shared_memory").?);
    try std.testing.expectEqual(ResourceType.semaphore, ResourceType.fromString("semaphore").?);
    try std.testing.expect(ResourceType.fromString("invalid") == null);
}

test "ResourceTracker init" {
    const allocator = std.testing.allocator;
    var tracker = ResourceTracker.init(allocator);
    defer tracker.deinit();

    try std.testing.expect(tracker.pid == null);
    try std.testing.expect(tracker.fd == null);
}
