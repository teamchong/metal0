/// emscripten_syscalls - Emscripten System Calls
/// Mirrors cpython/Python/emscripten_syscalls.c
///
/// System call emulation for WebAssembly/Emscripten builds.
/// Provides syscall-like interface for WASM sandboxed environment.

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Platform Detection
// ============================================================================

/// Check if running on Emscripten/WASM
pub const is_emscripten = builtin.os.tag == .emscripten or builtin.cpu.arch == .wasm32;

// ============================================================================
// Syscall Numbers
// ============================================================================

/// Emscripten syscall numbers
pub const Syscall = enum(i32) {
    // File operations
    SYS_read = 0,
    SYS_write = 1,
    SYS_open = 2,
    SYS_close = 3,
    SYS_stat = 4,
    SYS_fstat = 5,
    SYS_lstat = 6,
    SYS_poll = 7,
    SYS_lseek = 8,
    SYS_mmap = 9,
    SYS_mprotect = 10,
    SYS_munmap = 11,

    // Directory operations
    SYS_getcwd = 79,
    SYS_chdir = 80,
    SYS_mkdir = 83,
    SYS_rmdir = 84,
    SYS_readdir = 89,

    // Process (mostly no-ops in WASM)
    SYS_getpid = 39,
    SYS_fork = 57,
    SYS_exit = 60,

    // Time
    SYS_time = 201,
    SYS_clock_gettime = 228,

    // Socket (limited in WASM)
    SYS_socket = 41,
    SYS_connect = 42,
    SYS_accept = 43,
    SYS_sendto = 44,
    SYS_recvfrom = 45,
};

/// Syscall error codes
pub const Errno = enum(i32) {
    SUCCESS = 0,
    EPERM = 1,
    ENOENT = 2,
    ESRCH = 3,
    EINTR = 4,
    EIO = 5,
    ENXIO = 6,
    E2BIG = 7,
    ENOEXEC = 8,
    EBADF = 9,
    ECHILD = 10,
    EAGAIN = 11,
    ENOMEM = 12,
    EACCES = 13,
    EFAULT = 14,
    ENOTBLK = 15,
    EBUSY = 16,
    EEXIST = 17,
    EXDEV = 18,
    ENODEV = 19,
    ENOTDIR = 20,
    EISDIR = 21,
    EINVAL = 22,
    ENFILE = 23,
    EMFILE = 24,
    ENOTTY = 25,
    ETXTBSY = 26,
    EFBIG = 27,
    ENOSPC = 28,
    ESPIPE = 29,
    EROFS = 30,
    EMLINK = 31,
    EPIPE = 32,
    EDOM = 33,
    ERANGE = 34,
    ENOSYS = 38,
};

// ============================================================================
// Virtual File System
// ============================================================================

/// Virtual file descriptor
pub const FileDescriptor = struct {
    /// FD number
    fd: i32,
    /// File path
    path: []const u8,
    /// Current position
    position: u64 = 0,
    /// File flags
    flags: u32 = 0,
    /// File contents (for virtual files)
    contents: ?[]const u8 = null,
    /// Is directory
    is_dir: bool = false,
    /// Is open
    is_open: bool = true,
};

/// Virtual file system state
pub const VirtualFS = struct {
    const Self = @This();
    const MAX_FDS = 256;

    /// Open file descriptors
    fds: [MAX_FDS]?FileDescriptor = [_]?FileDescriptor{null} ** MAX_FDS,
    /// Current working directory
    cwd: [256]u8 = undefined,
    cwd_len: usize = 1,
    /// Next FD to allocate
    next_fd: i32 = 3, // 0, 1, 2 are stdin/stdout/stderr

    pub fn init() Self {
        var self = Self{};
        self.cwd[0] = '/';

        // Initialize stdin, stdout, stderr
        self.fds[0] = FileDescriptor{ .fd = 0, .path = "/dev/stdin" };
        self.fds[1] = FileDescriptor{ .fd = 1, .path = "/dev/stdout" };
        self.fds[2] = FileDescriptor{ .fd = 2, .path = "/dev/stderr" };

        return self;
    }

    /// Allocate a new FD
    pub fn allocFd(self: *Self) ?i32 {
        const fd = self.next_fd;
        if (fd >= MAX_FDS) return null;
        self.next_fd += 1;
        return fd;
    }

    /// Get FD entry
    pub fn getFd(self: *Self, fd: i32) ?*FileDescriptor {
        if (fd < 0 or fd >= MAX_FDS) return null;
        return if (self.fds[@intCast(fd)]) |*entry| entry else null;
    }

    /// Close a FD
    pub fn closeFd(self: *Self, fd: i32) Errno {
        if (fd < 0 or fd >= MAX_FDS) return .EBADF;
        if (self.fds[@intCast(fd)] == null) return .EBADF;

        self.fds[@intCast(fd)].?.is_open = false;
        self.fds[@intCast(fd)] = null;
        return .SUCCESS;
    }

    /// Get current working directory
    pub fn getCwd(self: *const Self) []const u8 {
        return self.cwd[0..self.cwd_len];
    }

    /// Change working directory
    pub fn setCwd(self: *Self, path: []const u8) Errno {
        if (path.len >= self.cwd.len) return .ENAMETOOLONG;
        @memcpy(self.cwd[0..path.len], path);
        self.cwd_len = path.len;
        return .SUCCESS;
    }
};

// ============================================================================
// Syscall Handlers
// ============================================================================

/// Syscall dispatcher
pub fn syscall(num: Syscall, args: anytype) i64 {
    return switch (num) {
        .SYS_read => syscallRead(args[0], args[1], args[2]),
        .SYS_write => syscallWrite(args[0], args[1], args[2]),
        .SYS_close => syscallClose(args[0]),
        .SYS_getpid => syscallGetpid(),
        .SYS_exit => syscallExit(args[0]),
        .SYS_getcwd => syscallGetcwd(args[0], args[1]),
        else => -@as(i64, @intFromEnum(Errno.ENOSYS)),
    };
}

fn syscallRead(fd: i32, buf: [*]u8, count: usize) i64 {
    _ = fd;
    _ = buf;
    _ = count;
    // Would interact with JS to read from virtual FS
    return -@as(i64, @intFromEnum(Errno.ENOSYS));
}

fn syscallWrite(fd: i32, buf: [*]const u8, count: usize) i64 {
    if (fd == 1 or fd == 2) {
        // stdout/stderr - would call console.log in Emscripten
        _ = buf;
        return @intCast(count);
    }
    return -@as(i64, @intFromEnum(Errno.EBADF));
}

fn syscallClose(fd: i32) i64 {
    const result = vfs.closeFd(fd);
    if (result == .SUCCESS) return 0;
    return -@as(i64, @intFromEnum(result));
}

fn syscallGetpid() i64 {
    // WASM doesn't have real processes, return 1
    return 1;
}

fn syscallExit(code: i32) i64 {
    // Would call _exit in Emscripten
    _ = code;
    return 0;
}

fn syscallGetcwd(buf: [*]u8, size: usize) i64 {
    const cwd = vfs.getCwd();
    if (cwd.len >= size) {
        return -@as(i64, @intFromEnum(Errno.ERANGE));
    }
    @memcpy(buf[0..cwd.len], cwd);
    buf[cwd.len] = 0;
    return @intCast(@intFromPtr(buf));
}

// ============================================================================
// Time Functions
// ============================================================================

/// Get current time (seconds since epoch)
pub fn time() i64 {
    return std.time.timestamp();
}

/// Get high-resolution time
pub fn clockGettime(clock_id: i32) struct { sec: i64, nsec: i64 } {
    _ = clock_id;
    const ns = std.time.nanoTimestamp();
    return .{
        .sec = @divTrunc(ns, std.time.ns_per_s),
        .nsec = @mod(ns, std.time.ns_per_s),
    };
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;
var vfs: VirtualFS = undefined;

/// Initialize the emscripten_syscalls module
pub fn init() void {
    if (initialized) return;
    vfs = VirtualFS.init();
    initialized = true;
}

/// Get virtual file system
pub fn getVFS() *VirtualFS {
    return &vfs;
}

/// Reset module state
pub fn reset() void {
    vfs = VirtualFS.init();
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "syscall numbers" {
    try std.testing.expectEqual(@as(i32, 0), @intFromEnum(Syscall.SYS_read));
    try std.testing.expectEqual(@as(i32, 1), @intFromEnum(Syscall.SYS_write));
    try std.testing.expectEqual(@as(i32, 60), @intFromEnum(Syscall.SYS_exit));
}

test "errno values" {
    try std.testing.expectEqual(@as(i32, 0), @intFromEnum(Errno.SUCCESS));
    try std.testing.expectEqual(@as(i32, 2), @intFromEnum(Errno.ENOENT));
    try std.testing.expectEqual(@as(i32, 38), @intFromEnum(Errno.ENOSYS));
}

test "virtual fs init" {
    var fs = VirtualFS.init();

    // Check stdio fds
    try std.testing.expect(fs.getFd(0) != null);
    try std.testing.expect(fs.getFd(1) != null);
    try std.testing.expect(fs.getFd(2) != null);

    // Check cwd
    try std.testing.expectEqualStrings("/", fs.getCwd());
}

test "virtual fs alloc fd" {
    var fs = VirtualFS.init();

    const fd1 = fs.allocFd();
    try std.testing.expect(fd1 != null);
    try std.testing.expectEqual(@as(i32, 3), fd1.?);

    const fd2 = fs.allocFd();
    try std.testing.expect(fd2 != null);
    try std.testing.expectEqual(@as(i32, 4), fd2.?);
}

test "syscall getpid" {
    const pid = syscallGetpid();
    try std.testing.expectEqual(@as(i64, 1), pid);
}

test "clockgettime" {
    const t = clockGettime(0);
    try std.testing.expect(t.sec > 0);
}
