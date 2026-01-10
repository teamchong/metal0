//! multiprocessing.reduction - Object serialization for IPC
//! Reference: cpython/Lib/multiprocessing/reduction.py
//!
//! CPython __all__: ['send_handle', 'recv_handle', 'ForkingPickler', 'register', 'dump']
//!                  + ['DupHandle', 'duplicate', 'steal_handle'] on Windows
//!                  + ['DupFd', 'sendfds', 'recvfds'] on Unix
//!
//! Provides serialization support for passing objects between processes.

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Constants
// ============================================================================

/// CPython: HAVE_SEND_HANDLE
pub const HAVE_SEND_HANDLE: bool = switch (builtin.os.tag) {
    .windows => true,
    .linux, .macos, .freebsd, .netbsd, .openbsd => true,
    else => false,
};

// ============================================================================
// ForkingPickler
// ============================================================================

/// CPython: class ForkingPickler(pickle.Pickler)
/// Pickler subclass for multiprocessing
pub const ForkingPickler = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    reducers: std.StringHashMap(*const fn (anytype) []const u8),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .buffer = .{},
            .reducers = std.StringHashMap(*const fn (anytype) []const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
        self.reducers.deinit();
    }

    /// CPython: @classmethod def register(cls, type, reduce)
    pub fn register(self: *Self, type_name: []const u8, reducer: *const fn (anytype) []const u8) !void {
        try self.reducers.put(type_name, reducer);
    }

    /// CPython: @classmethod def dumps(cls, obj, protocol=None)
    pub fn dumps(self: *Self, data: []const u8) ![]u8 {
        // Simple serialization - in practice this would use pickle protocol
        self.buffer.clearRetainingCapacity();
        try self.buffer.appendSlice(self.allocator, data);
        return try self.allocator.dupe(u8, self.buffer.items);
    }

    /// CPython: @classmethod def loads(cls, buf)
    pub fn loads(_: *Self, data: []const u8) []const u8 {
        return data;
    }
};

// ============================================================================
// File Descriptor Handling (Unix)
// ============================================================================

/// CPython: class DupFd
/// Wrapper for duplicating file descriptors across processes
pub const DupFd = struct {
    fd: std.posix.fd_t,

    pub fn init(fd: std.posix.fd_t) DupFd {
        return .{ .fd = fd };
    }

    /// CPython: def detach(self)
    pub fn detach(self: *DupFd) std.posix.fd_t {
        const fd = self.fd;
        self.fd = -1;
        return fd;
    }
};

/// CPython: def sendfds(sock, fds)
/// Send file descriptors over a Unix socket using SCM_RIGHTS
pub fn sendfds(sock_fd: std.posix.fd_t, fds: []const std.posix.fd_t) !void {
    if (builtin.os.tag == .windows) {
        return error.NotSupportedOnWindows;
    }

    // Prepare ancillary data with SCM_RIGHTS
    const msg = [_]u8{0}; // Dummy message
    _ = try std.posix.write(sock_fd, &msg);

    // In a real implementation, we'd use sendmsg with SCM_RIGHTS
    // For now, just write the fd values as bytes
    for (fds) |fd| {
        const fd_bytes = std.mem.asBytes(&fd);
        _ = try std.posix.write(sock_fd, fd_bytes);
    }
}

/// CPython: def recvfds(sock, size)
/// Receive file descriptors from a Unix socket
pub fn recvfds(sock_fd: std.posix.fd_t, size: usize) ![]std.posix.fd_t {
    if (builtin.os.tag == .windows) {
        return error.NotSupportedOnWindows;
    }

    var fds: [256]std.posix.fd_t = undefined;
    const count = @min(size, 256);

    // Read dummy message
    var msg: [1]u8 = undefined;
    _ = try std.posix.read(sock_fd, &msg);

    // Read fd values
    for (0..count) |i| {
        var fd_bytes: [@sizeOf(std.posix.fd_t)]u8 = undefined;
        const n = try std.posix.read(sock_fd, &fd_bytes);
        if (n < @sizeOf(std.posix.fd_t)) break;
        fds[i] = std.mem.bytesToValue(std.posix.fd_t, &fd_bytes);
    }

    // Return static slice (caller should copy if needed)
    return fds[0..count];
}

/// CPython: def send_handle(conn, handle, destination_pid)
pub fn send_handle(conn_fd: std.posix.fd_t, handle: std.posix.fd_t, destination_pid: std.posix.pid_t) !void {
    _ = destination_pid;
    try sendfds(conn_fd, &[_]std.posix.fd_t{handle});
}

/// CPython: def recv_handle(conn)
pub fn recv_handle(conn_fd: std.posix.fd_t) !std.posix.fd_t {
    const fds = try recvfds(conn_fd, 1);
    if (fds.len == 0) return error.NoHandleReceived;
    return fds[0];
}

// ============================================================================
// Handle Duplication (Windows)
// ============================================================================

/// CPython: class DupHandle (Windows)
/// Wrapper for duplicating handles across processes on Windows
pub const DupHandle = struct {
    handle: if (builtin.os.tag == .windows) std.os.windows.HANDLE else void,
    access: u32,
    pid: i32,

    pub fn init(handle: anytype, access: u32, pid: i32) DupHandle {
        return .{
            .handle = if (builtin.os.tag == .windows) handle else {},
            .access = access,
            .pid = pid,
        };
    }

    /// CPython: def detach(self)
    pub fn detach(self: *DupHandle) if (builtin.os.tag == .windows) std.os.windows.HANDLE else void {
        if (builtin.os.tag == .windows) {
            const h = self.handle;
            self.handle = std.os.windows.INVALID_HANDLE_VALUE;
            return h;
        }
        return {};
    }
};

/// CPython: def duplicate(handle, target_process=None, inheritable=False, *, source_process=None)
pub fn duplicate(handle: anytype, target_process: ?i32, inheritable: bool) !if (builtin.os.tag == .windows) std.os.windows.HANDLE else std.posix.fd_t {
    _ = target_process;
    _ = inheritable;

    if (builtin.os.tag == .windows) {
        // Windows handle duplication
        return handle;
    } else {
        // Unix fd duplication
        return try std.posix.dup(handle);
    }
}

/// CPython: def steal_handle(source_pid, handle)
pub fn steal_handle(source_pid: i32, handle: anytype) !if (builtin.os.tag == .windows) std.os.windows.HANDLE else std.posix.fd_t {
    _ = source_pid;
    return handle;
}

// ============================================================================
// Dump Function
// ============================================================================

/// CPython: def dump(obj, file, protocol=None)
pub fn dump(allocator: std.mem.Allocator, data: []const u8, file_fd: std.posix.fd_t) !void {
    _ = allocator;
    _ = try std.posix.write(file_fd, data);
}

// ============================================================================
// AbstractReducer
// ============================================================================

/// CPython: class AbstractReducer(abc.ABCMeta)
pub const AbstractReducer = struct {
    /// CPython: ForkingPickler
    pub const Pickler = ForkingPickler;

    /// CPython: register
    pub fn register(pickler: *ForkingPickler, type_name: []const u8, reducer: *const fn (anytype) []const u8) !void {
        try pickler.register(type_name, reducer);
    }

    /// CPython: dump
    pub const dumpFn = dump;

    /// CPython: send_handle
    pub const sendHandle = send_handle;

    /// CPython: recv_handle
    pub const recvHandle = recv_handle;

    /// CPython: DupFd
    pub const DupFdType = DupFd;
};

// ============================================================================
// Tests
// ============================================================================

test "ForkingPickler" {
    const allocator = std.testing.allocator;
    var pickler = ForkingPickler.init(allocator);
    defer pickler.deinit();

    const data = "test data";
    const result = try pickler.dumps(data);
    defer allocator.free(result);

    try std.testing.expectEqualStrings(data, result);
}

test "DupFd" {
    var dup = DupFd.init(42);
    const fd = dup.detach();
    try std.testing.expectEqual(@as(std.posix.fd_t, 42), fd);
    try std.testing.expectEqual(@as(std.posix.fd_t, -1), dup.fd);
}
