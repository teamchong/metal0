//! Netpoller - Non-blocking I/O multiplexer (like Go's netpoller)
//!
//! This enables goroutine-like async I/O:
//! 1. When a green thread does I/O, it registers with the netpoller
//! 2. The green thread yields (parks)
//! 3. OS handles I/O in background (epoll/kqueue)
//! 4. When I/O completes, netpoller wakes the green thread
//!
//! Platform support:
//! - macOS: kqueue
//! - Linux: epoll
//! - Windows: IOCP (future)

const std = @import("std");
const builtin = @import("builtin");
const GreenThread = @import("green_thread.zig").GreenThread;

/// I/O operation type
pub const IoOp = enum {
    read,
    write,
    connect,
    accept,
};

/// Pending I/O operation
pub const PendingIo = struct {
    fd: std.posix.fd_t,
    op: IoOp,
    thread: *GreenThread,
    callback: ?*const fn (*GreenThread, anyerror!usize) void,
    user_data: ?*anyopaque,
};

/// Netpoller - manages async I/O across all green threads
pub const Netpoller = struct {
    allocator: std.mem.Allocator,

    // Platform-specific handle
    poll_fd: if (builtin.os.tag == .macos or builtin.os.tag == .freebsd or builtin.os.tag == .netbsd or builtin.os.tag == .openbsd)
        std.posix.fd_t // kqueue fd
    else if (builtin.os.tag == .linux)
        std.posix.fd_t // epoll fd
    else
        void,

    // Pending I/O operations (fd -> PendingIo)
    pending: std.AutoHashMap(std.posix.fd_t, PendingIo),
    pending_mutex: std.Thread.Mutex,

    // Ready threads (woken by I/O completion)
    ready_threads: std.ArrayList(*GreenThread),
    ready_mutex: std.Thread.Mutex,

    // Stats
    total_registered: u64,
    total_completed: u64,
    total_errors: u64,

    // Poller thread
    poller_thread: ?std.Thread,
    running: std.atomic.Value(bool),

    pub fn init(allocator: std.mem.Allocator) !Netpoller {
        var np = Netpoller{
            .allocator = allocator,
            .poll_fd = undefined,
            .pending = std.AutoHashMap(std.posix.fd_t, PendingIo).init(allocator),
            .pending_mutex = .{},
            .ready_threads = std.ArrayList(*GreenThread){},
            .ready_mutex = .{},
            .total_registered = 0,
            .total_completed = 0,
            .total_errors = 0,
            .poller_thread = null,
            .running = std.atomic.Value(bool).init(false),
        };

        // Create platform-specific poller
        if (builtin.os.tag == .macos or builtin.os.tag == .freebsd or builtin.os.tag == .netbsd or builtin.os.tag == .openbsd) {
            np.poll_fd = try std.posix.kqueue();
        } else if (builtin.os.tag == .linux) {
            np.poll_fd = try std.posix.epoll_create1(0);
        }

        return np;
    }

    pub fn deinit(self: *Netpoller) void {
        // Stop poller thread
        self.stop();

        // Close poll fd
        if (builtin.os.tag == .macos or builtin.os.tag == .freebsd or builtin.os.tag == .netbsd or builtin.os.tag == .openbsd or builtin.os.tag == .linux) {
            std.posix.close(self.poll_fd);
        }

        self.pending.deinit();
        self.ready_threads.deinit(self.allocator);
    }

    /// Start the poller thread
    pub fn start(self: *Netpoller) !void {
        if (self.running.load(.acquire)) return;
        self.running.store(true, .release);

        self.poller_thread = try std.Thread.spawn(.{}, pollLoop, .{self});
    }

    /// Stop the poller thread
    pub fn stop(self: *Netpoller) void {
        if (!self.running.load(.acquire)) return;
        self.running.store(false, .release);

        if (self.poller_thread) |t| {
            t.join();
            self.poller_thread = null;
        }
    }

    /// Register an fd for async I/O (called by green thread before blocking I/O)
    /// The green thread will be parked and woken when I/O is ready
    pub fn register(self: *Netpoller, fd: std.posix.fd_t, op: IoOp, thread: *GreenThread) !void {
        self.pending_mutex.lock();
        defer self.pending_mutex.unlock();

        // Store pending operation
        try self.pending.put(fd, .{
            .fd = fd,
            .op = op,
            .thread = thread,
            .callback = null,
            .user_data = null,
        });
        self.total_registered += 1;

        // Register with OS
        if (builtin.os.tag == .macos or builtin.os.tag == .freebsd or builtin.os.tag == .netbsd or builtin.os.tag == .openbsd) {
            try self.kqueueAdd(fd, op);
        } else if (builtin.os.tag == .linux) {
            try self.epollAdd(fd, op);
        }

        // Park the thread (mark as blocked)
        thread.state = .blocked;
    }

    /// Unregister an fd (called when I/O completes or is cancelled)
    pub fn unregister(self: *Netpoller, fd: std.posix.fd_t) void {
        self.pending_mutex.lock();
        defer self.pending_mutex.unlock();

        _ = self.pending.remove(fd);

        // Remove from OS
        if (builtin.os.tag == .macos or builtin.os.tag == .freebsd or builtin.os.tag == .netbsd or builtin.os.tag == .openbsd) {
            self.kqueueRemove(fd) catch {};
        } else if (builtin.os.tag == .linux) {
            self.epollRemove(fd) catch {};
        }
    }

    /// Get ready threads (called by scheduler)
    pub fn getReadyThreads(self: *Netpoller) []*GreenThread {
        self.ready_mutex.lock();
        defer self.ready_mutex.unlock();

        if (self.ready_threads.items.len == 0) {
            return &[_]*GreenThread{};
        }

        const result = self.ready_threads.toOwnedSlice(self.allocator) catch &[_]*GreenThread{};
        return result;
    }

    // === Platform-specific implementations ===

    fn kqueueAdd(self: *Netpoller, fd: std.posix.fd_t, op: IoOp) !void {
        var changelist: [1]std.posix.Kevent = undefined;
        const filter: i16 = switch (op) {
            .read, .accept => std.posix.system.EVFILT.READ,
            .write, .connect => std.posix.system.EVFILT.WRITE,
        };

        changelist[0] = .{
            .ident = @intCast(fd),
            .filter = filter,
            .flags = std.posix.system.EV.ADD | std.posix.system.EV.ONESHOT,
            .fflags = 0,
            .data = 0,
            .udata = @intFromPtr(&self.pending.get(fd).?),
        };

        const result = std.posix.kevent(self.poll_fd, &changelist, &[_]std.posix.Kevent{}, null);
        if (result < 0) return error.KqueueError;
    }

    fn kqueueRemove(self: *Netpoller, fd: std.posix.fd_t) !void {
        var changelist: [2]std.posix.Kevent = undefined;

        changelist[0] = .{
            .ident = @intCast(fd),
            .filter = std.posix.system.EVFILT.READ,
            .flags = std.posix.system.EV.DELETE,
            .fflags = 0,
            .data = 0,
            .udata = 0,
        };
        changelist[1] = .{
            .ident = @intCast(fd),
            .filter = std.posix.system.EVFILT.WRITE,
            .flags = std.posix.system.EV.DELETE,
            .fflags = 0,
            .data = 0,
            .udata = 0,
        };

        _ = std.posix.kevent(self.poll_fd, &changelist, &[_]std.posix.Kevent{}, null);
    }

    fn epollAdd(self: *Netpoller, fd: std.posix.fd_t, op: IoOp) !void {
        var event: std.os.linux.epoll_event = .{
            .events = switch (op) {
                .read, .accept => std.os.linux.EPOLL.IN,
                .write, .connect => std.os.linux.EPOLL.OUT,
            } | std.os.linux.EPOLL.ONESHOT,
            .data = .{ .fd = fd },
        };

        try std.posix.epoll_ctl(self.poll_fd, std.os.linux.EPOLL.CTL_ADD, fd, &event);
    }

    fn epollRemove(self: *Netpoller, fd: std.posix.fd_t) !void {
        std.posix.epoll_ctl(self.poll_fd, std.os.linux.EPOLL.CTL_DEL, fd, null) catch {};
    }

    // === Poll loop (runs in background thread) ===

    fn pollLoop(self: *Netpoller) void {
        while (self.running.load(.acquire)) {
            if (builtin.os.tag == .macos or builtin.os.tag == .freebsd or builtin.os.tag == .netbsd or builtin.os.tag == .openbsd) {
                self.pollKqueue();
            } else if (builtin.os.tag == .linux) {
                self.pollEpoll();
            } else {
                // Unsupported platform - just sleep
                std.time.sleep(10 * std.time.ns_per_ms);
            }
        }
    }

    fn pollKqueue(self: *Netpoller) void {
        var events: [64]std.posix.Kevent = undefined;
        const timeout = std.posix.timespec{ .sec = 0, .nsec = 10 * std.time.ns_per_ms }; // 10ms

        const n = std.posix.kevent(self.poll_fd, &[_]std.posix.Kevent{}, &events, &timeout) catch return;
        if (n == 0) return;

        self.pending_mutex.lock();
        self.ready_mutex.lock();
        defer {
            self.ready_mutex.unlock();
            self.pending_mutex.unlock();
        }

        for (events[0..@intCast(n)]) |event| {
            const fd: std.posix.fd_t = @intCast(event.ident);

            if (self.pending.get(fd)) |pending| {
                // Wake the thread
                pending.thread.state = .ready;
                self.ready_threads.append(self.allocator, pending.thread) catch {};
                self.total_completed += 1;

                // Remove from pending
                _ = self.pending.remove(fd);
            }
        }
    }

    fn pollEpoll(self: *Netpoller) void {
        var events: [64]std.os.linux.epoll_event = undefined;

        const n = std.posix.epoll_wait(self.poll_fd, &events, 10) catch return; // 10ms timeout
        if (n == 0) return;

        self.pending_mutex.lock();
        self.ready_mutex.lock();
        defer {
            self.ready_mutex.unlock();
            self.pending_mutex.unlock();
        }

        for (events[0..@intCast(n)]) |event| {
            const fd = event.data.fd;

            if (self.pending.get(fd)) |pending| {
                // Wake the thread
                pending.thread.state = .ready;
                self.ready_threads.append(self.allocator, pending.thread) catch {};
                self.total_completed += 1;

                // Remove from pending
                _ = self.pending.remove(fd);
            }
        }
    }

    /// Statistics
    pub fn stats(self: *Netpoller) NetpollerStats {
        return .{
            .total_registered = self.total_registered,
            .total_completed = self.total_completed,
            .total_errors = self.total_errors,
            .pending_count = self.pending.count(),
            .ready_count = self.ready_threads.items.len,
        };
    }
};

pub const NetpollerStats = struct {
    total_registered: u64,
    total_completed: u64,
    total_errors: u64,
    pending_count: usize,
    ready_count: usize,
};

// === Global netpoller instance ===

var global_netpoller: ?*Netpoller = null;
var global_netpoller_mutex: std.Thread.Mutex = .{};

pub fn getNetpoller(allocator: std.mem.Allocator) !*Netpoller {
    global_netpoller_mutex.lock();
    defer global_netpoller_mutex.unlock();

    if (global_netpoller) |np| {
        return np;
    }

    const np = try allocator.create(Netpoller);
    np.* = try Netpoller.init(allocator);
    try np.start();
    global_netpoller = np;

    return np;
}

// === Tests ===

test "Netpoller init/deinit" {
    const allocator = std.testing.allocator;
    var np = try Netpoller.init(allocator);
    defer np.deinit();

    try std.testing.expect(np.total_registered == 0);
    try std.testing.expect(np.total_completed == 0);
}

test "Netpoller start/stop" {
    const allocator = std.testing.allocator;
    var np = try Netpoller.init(allocator);
    defer np.deinit();

    try np.start();
    try std.testing.expect(np.running.load(.acquire));

    np.stop();
    try std.testing.expect(!np.running.load(.acquire));
}
