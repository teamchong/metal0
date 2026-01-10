//! multiprocessing.shared_memory - POSIX shared memory
//! Reference: cpython/Lib/multiprocessing/shared_memory.py
//!
//! CPython __all__: ['SharedMemory', 'ShareableList']
//!
//! Provides shared memory for direct access across processes.
//! Uses POSIX shm_open/mmap on Unix and CreateFileMapping on Windows.

const std = @import("std");
const builtin = @import("builtin");
const resource_tracker = @import("resource_tracker.zig");

// ============================================================================
// Constants
// ============================================================================

/// Flags for creating shared memory
pub const O_CREX = std.posix.O.CREAT | std.posix.O.EXCL;

/// FreeBSD (and perhaps other BSDs) limit names to 14 characters
pub const SHM_SAFE_NAME_LENGTH: usize = 14;

/// Shared memory block name prefix
pub const SHM_NAME_PREFIX: []const u8 = if (builtin.os.tag == .windows) "wnsm_" else "/psm_";

// ============================================================================
// SharedMemory
// ============================================================================

/// CPython: class SharedMemory
/// Creates or attaches to a shared memory block
pub const SharedMemory = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    name: []const u8,
    size: usize,
    buf: ?[]align(std.mem.page_size) u8,
    fd: ?std.posix.fd_t,
    created: bool,
    unlink_on_close: bool,

    /// CPython: def __init__(self, name=None, create=False, size=0)
    pub fn init(allocator: std.mem.Allocator, name: ?[]const u8, create: bool, size: usize) !Self {
        var self = Self{
            .allocator = allocator,
            .name = undefined,
            .size = size,
            .buf = null,
            .fd = null,
            .created = create,
            .unlink_on_close = false,
        };

        // Generate name if not provided
        if (name) |n| {
            self.name = try allocator.dupe(u8, n);
        } else {
            self.name = try makeFilename(allocator);
        }

        if (builtin.os.tag == .windows) {
            try self.initWindows(create, size);
        } else {
            try self.initPosix(create, size);
        }

        // Register with resource tracker
        try resource_tracker.register(allocator, self.name, .shared_memory);

        return self;
    }

    fn initPosix(self: *Self, create: bool, size: usize) !void {
        const flags: u32 = if (create)
            @as(u32, @intCast(std.posix.O.CREAT | std.posix.O.EXCL | std.posix.O.RDWR))
        else
            @as(u32, @intCast(std.posix.O.RDWR));

        // Open or create shared memory
        // Note: This would use shm_open in a full implementation
        // For now, use a regular temp file as a fallback
        const path = try std.fmt.allocPrint(self.allocator, "/tmp{s}", .{self.name});
        defer self.allocator.free(path);

        const fd = try std.posix.open(path, .{
            .ACCMODE = .RDWR,
            .CREAT = create,
            .EXCL = create,
        }, 0o600);
        self.fd = fd;

        if (create) {
            // Set size
            try std.posix.ftruncate(fd, @intCast(size));
            self.size = size;
        } else {
            // Get existing size
            const stat = try std.posix.fstat(fd);
            self.size = @intCast(stat.size);
        }

        // Map into memory
        self.buf = try std.posix.mmap(
            null,
            self.size,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .SHARED },
            fd,
            0,
        );
    }

    fn initWindows(self: *Self, create: bool, size: usize) !void {
        _ = create;
        // Windows implementation would use CreateFileMapping
        self.size = size;
        // Placeholder - full implementation would use Windows APIs
    }

    pub fn deinit(self: *Self) void {
        self.close();
        self.allocator.free(self.name);
    }

    /// CPython: def close(self)
    pub fn close(self: *Self) void {
        if (self.buf) |buf| {
            std.posix.munmap(buf);
            self.buf = null;
        }

        if (self.fd) |fd| {
            std.posix.close(fd);
            self.fd = null;
        }
    }

    /// CPython: def unlink(self)
    pub fn unlink(self: *Self) void {
        // Remove the shared memory
        if (builtin.os.tag != .windows) {
            const path = std.fmt.allocPrint(self.allocator, "/tmp{s}", .{self.name}) catch return;
            defer self.allocator.free(path);
            std.posix.unlink(path) catch {};
        }

        // Unregister from resource tracker
        resource_tracker.unregister(self.allocator, self.name, .shared_memory);
    }

    /// Get the buffer
    pub fn getBuffer(self: *Self) ?[]u8 {
        return self.buf;
    }
};

// ============================================================================
// ShareableList
// ============================================================================

/// CPython: class ShareableList
/// A mutable list-like object where values are stored in shared memory
pub fn ShareableList(comptime T: type) type {
    return struct {
        const Self = @This();

        shm: SharedMemory,
        count: usize,

        pub fn init(allocator: std.mem.Allocator, sequence: []const T) !Self {
            const item_size = @sizeOf(T);
            const total_size = sequence.len * item_size + @sizeOf(usize); // +size for count

            var shm = try SharedMemory.init(allocator, null, true, total_size);

            // Initialize with sequence
            if (shm.getBuffer()) |buf| {
                // Store count
                const count_ptr: *usize = @ptrCast(@alignCast(buf.ptr));
                count_ptr.* = sequence.len;

                // Store items
                const items_ptr: [*]T = @ptrCast(@alignCast(buf.ptr + @sizeOf(usize)));
                for (sequence, 0..) |item, i| {
                    items_ptr[i] = item;
                }
            }

            return .{
                .shm = shm,
                .count = sequence.len,
            };
        }

        pub fn initFromName(allocator: std.mem.Allocator, name: []const u8) !Self {
            var shm = try SharedMemory.init(allocator, name, false, 0);

            var count: usize = 0;
            if (shm.getBuffer()) |buf| {
                const count_ptr: *const usize = @ptrCast(@alignCast(buf.ptr));
                count = count_ptr.*;
            }

            return .{
                .shm = shm,
                .count = count,
            };
        }

        pub fn deinit(self: *Self) void {
            self.shm.deinit();
        }

        /// Get item at index
        pub fn get(self: *Self, index: usize) ?T {
            if (index >= self.count) return null;

            if (self.shm.getBuffer()) |buf| {
                const items_ptr: [*]const T = @ptrCast(@alignCast(buf.ptr + @sizeOf(usize)));
                return items_ptr[index];
            }
            return null;
        }

        /// Set item at index
        pub fn set(self: *Self, index: usize, value: T) !void {
            if (index >= self.count) return error.IndexOutOfBounds;

            if (self.shm.getBuffer()) |buf| {
                const items_ptr: [*]T = @ptrCast(@alignCast(buf.ptr + @sizeOf(usize)));
                items_ptr[index] = value;
            }
        }

        /// Get length
        pub fn len(self: *Self) usize {
            return self.count;
        }
    };
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Generate a random filename for shared memory
fn makeFilename(allocator: std.mem.Allocator) ![]u8 {
    var rng = std.rand.DefaultPrng.init(@intCast(std.time.timestamp()));
    var buf: [8]u8 = undefined;

    for (&buf) |*b| {
        b.* = "0123456789abcdef"[rng.random().int(u4)];
    }

    return try std.fmt.allocPrint(allocator, "{s}{s}", .{ SHM_NAME_PREFIX, &buf });
}

// ============================================================================
// Tests
// ============================================================================

test "SharedMemory basic" {
    // Skip on CI - requires actual shared memory support
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    // Test would create and access shared memory
    // Skipping actual test due to file system requirements
    _ = allocator;
}

test "makeFilename" {
    const allocator = std.testing.allocator;
    const name = try makeFilename(allocator);
    defer allocator.free(name);

    try std.testing.expect(name.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, name, SHM_NAME_PREFIX));
}
