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
const GreenThread = @import("green_thread").GreenThread;

/// I/O operation type
pub const IoOp = enum {
    read,
    write,
    connect,
    accept,
    timer, // For asyncio.sleep
};

/// Pending I/O operation
pub const PendingIo = struct {
    fd: std.posix.fd_t,
    op: IoOp,
    thread: *GreenThread,
    callback: ?*const fn (*GreenThread, anyerror!usize) void,
    user_data: ?*anyopaque,
};

/// Pending timer (for asyncio.sleep)
pub const PendingTimer = struct {
    id: u64,
    thread: *GreenThread,
    deadline_ns: i128, // Absolute time when timer fires
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

    // Pending timers (id -> PendingTimer) for asyncio.sleep
    timers: std.AutoHashMap(u64, PendingTimer),
    timer_mutex: std.Thread.Mutex,
    next_timer_id: std.atomic.Value(u64),

    // Ready threads (woken by I/O completion)
    ready_threads: std.ArrayList(*GreenThread),
    ready_mutex: std.Thread.Mutex,

    // Stats
    total_registered: u64,
    total_completed: u64,
    total_errors: u64,
    total_timers: u64,

    // Poller thread
    poller_thread: ?std.Thread,
    running: std.atomic.Value(bool),

    pub fn init(allocator: std.mem.Allocator) !Netpoller {
        var np = Netpoller{
            .allocator = allocator,
            .poll_fd = undefined,
            .pending = std.AutoHashMap(std.posix.fd_t, PendingIo).init(allocator),
            .pending_mutex = .{},
            .timers = std.AutoHashMap(u64, PendingTimer).init(allocator),
            .timer_mutex = .{},
            .next_timer_id = std.atomic.Value(u64).init(1),
            .ready_threads = std.ArrayList(*GreenThread){},
            .ready_mutex = .{},
            .total_registered = 0,
            .total_completed = 0,
            .total_errors = 0,
            .total_timers = 0,
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
        self.timers.deinit();
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

    /// Register a timer (for asyncio.sleep)
    /// duration_ns: how long to sleep in nanoseconds
    /// thread: the green thread to wake when timer fires
    /// Returns immediately, thread will be woken by poll loop
    pub fn registerTimer(self: *Netpoller, duration_ns: u64, thread: *GreenThread) !void {
        const timer_id = self.next_timer_id.fetchAdd(1, .monotonic);
        const now = std.time.nanoTimestamp();
        const deadline = now + @as(i128, duration_ns);

        self.timer_mutex.lock();
        defer self.timer_mutex.unlock();

        try self.timers.put(timer_id, .{
            .id = timer_id,
            .thread = thread,
            .deadline_ns = deadline,
        });
        self.total_timers += 1;

        // Register with OS using EVFILT_TIMER (kqueue) or timerfd (Linux)
        if (builtin.os.tag == .macos or builtin.os.tag == .freebsd or builtin.os.tag == .netbsd or builtin.os.tag == .openbsd) {
            try self.kqueueAddTimer(timer_id, duration_ns);
        } else if (builtin.os.tag == .linux) {
            // Linux uses timerfd - for now use simple polling
            // TODO: implement timerfd for better efficiency
        }

        // Park the thread
        thread.state = .blocked;
    }

    /// Get ready threads (called by scheduler)
    pub fn getReadyThreads(self: *Netpoller) []*GreenThread {
        self.ready_mutex.lock();
        defer self.ready_mutex.unlock();

        if (self.ready_threads.items.len == 0) {
            return @constCast(&[_]*GreenThread{});
        }

        const result = self.ready_threads.toOwnedSlice(self.allocator) catch @constCast(&[_]*GreenThread{});
        return result;
    }

    // === Platform-specific implementations ===

    fn kqueueAdd(self: *Netpoller, fd: std.posix.fd_t, op: IoOp) !void {
        var changelist: [1]std.posix.Kevent = undefined;
        const filter: i16 = switch (op) {
            .read, .accept => std.posix.system.EVFILT.READ,
            .write, .connect => std.posix.system.EVFILT.WRITE,
            .timer => return, // Timers use kqueueAddTimer
        };

        changelist[0] = .{
            .ident = @intCast(fd),
            .filter = filter,
            .flags = std.posix.system.EV.ADD | std.posix.system.EV.ONESHOT,
            .fflags = 0,
            .data = 0,
            .udata = @intFromPtr(&self.pending.get(fd).?),
        };

        _ = std.posix.kevent(self.poll_fd, &changelist, &[_]std.posix.Kevent{}, null) catch return error.KqueueError;
    }

    /// Add a timer to kqueue using EVFILT_TIMER
    fn kqueueAddTimer(self: *Netpoller, timer_id: u64, duration_ns: u64) !void {
        var changelist: [1]std.posix.Kevent = undefined;

        // Convert nanoseconds to milliseconds for kqueue (NOTE_NSECONDS flag would allow ns)
        const duration_ms: isize = @intCast(@max(1, duration_ns / 1_000_000));

        changelist[0] = .{
            .ident = timer_id,
            .filter = std.posix.system.EVFILT.TIMER,
            .flags = std.posix.system.EV.ADD | std.posix.system.EV.ONESHOT,
            .fflags = 0, // Use milliseconds (default)
            .data = duration_ms,
            .udata = timer_id, // Store timer_id for lookup
        };

        _ = std.posix.kevent(self.poll_fd, &changelist, &[_]std.posix.Kevent{}, null) catch return error.KqueueError;
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
        // Timers use timerfd on Linux, not epoll directly
        if (op == .timer) return;

        var event: std.os.linux.epoll_event = .{
            .events = switch (op) {
                .read, .accept => std.os.linux.EPOLL.IN,
                .write, .connect => std.os.linux.EPOLL.OUT,
                .timer => unreachable, // Handled above
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
        const timeout = std.posix.timespec{ .sec = 0, .nsec = 1 * std.time.ns_per_ms }; // 1ms for faster timer response

        const n = std.posix.kevent(self.poll_fd, &[_]std.posix.Kevent{}, &events, &timeout) catch return;
        if (n == 0) return;

        self.pending_mutex.lock();
        self.timer_mutex.lock();
        self.ready_mutex.lock();
        defer {
            self.ready_mutex.unlock();
            self.timer_mutex.unlock();
            self.pending_mutex.unlock();
        }

        for (events[0..@intCast(n)]) |event| {
            // Check if this is a timer event
            if (event.filter == std.posix.system.EVFILT.TIMER) {
                const timer_id: u64 = event.udata;
                if (self.timers.get(timer_id)) |timer| {
                    // Wake the thread
                    timer.thread.state = .ready;
                    self.ready_threads.append(self.allocator, timer.thread) catch {};
                    self.total_completed += 1;
                    _ = self.timers.remove(timer_id);
                }
                continue;
            }

            // Regular I/O event
            const fd: std.posix.fd_t = @intCast(event.ident);
            if (self.pending.get(fd)) |pending| {
                pending.thread.state = .ready;
                self.ready_threads.append(self.allocator, pending.thread) catch {};
                self.total_completed += 1;
                _ = self.pending.remove(fd);
            }
        }
    }

    fn pollEpoll(self: *Netpoller) void {
        var events: [64]std.os.linux.epoll_event = undefined;

        const n = std.posix.epoll_wait(self.poll_fd, &events, 1) catch return; // 1ms timeout

        // Check timers (deadline-based polling - TODO: use timerfd)
        self.checkTimers();

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
                pending.thread.state = .ready;
                self.ready_threads.append(self.allocator, pending.thread) catch {};
                self.total_completed += 1;
                _ = self.pending.remove(fd);
            }
        }
    }

    /// Check expired timers (used by Linux until timerfd is implemented)
    fn checkTimers(self: *Netpoller) void {
        const now = std.time.nanoTimestamp();

        self.timer_mutex.lock();
        self.ready_mutex.lock();
        defer {
            self.ready_mutex.unlock();
            self.timer_mutex.unlock();
        }

        // Collect expired timers
        var expired = std.ArrayList(u64){};
        defer expired.deinit(self.allocator);

        var iter = self.timers.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.deadline_ns <= now) {
                expired.append(self.allocator, entry.key_ptr.*) catch continue;
            }
        }

        // Wake expired timers
        for (expired.items) |timer_id| {
            if (self.timers.get(timer_id)) |timer| {
                timer.thread.state = .ready;
                self.ready_threads.append(self.allocator, timer.thread) catch {};
                self.total_completed += 1;
                _ = self.timers.remove(timer_id);
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
var global_allocator: ?std.mem.Allocator = null;

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
    global_allocator = allocator;

    return np;
}

// === Simple timer API for state machine async ===

/// Timer state for non-blocking sleep
const SimpleTimer = struct {
    deadline_ns: i128,
    fired: bool = false,
};

var simple_timers: std.AutoHashMap(u64, SimpleTimer) = undefined;
var simple_timer_mutex: std.Thread.Mutex = .{};
var next_simple_timer_id: std.atomic.Value(u64) = std.atomic.Value(u64).init(1);
var simple_timers_initialized = false;

fn ensureSimpleTimersInit() void {
    if (!simple_timers_initialized) {
        simple_timers = std.AutoHashMap(u64, SimpleTimer).init(std.heap.page_allocator);
        simple_timers_initialized = true;
    }
}

/// Add a timer that fires after duration_ns nanoseconds
/// Returns timer ID for checking with timerReady()
pub fn addTimer(duration_ns: u64) u64 {
    ensureSimpleTimersInit();

    const timer_id = next_simple_timer_id.fetchAdd(1, .monotonic);
    const now = std.time.nanoTimestamp();
    const deadline = now + @as(i128, duration_ns);

    simple_timer_mutex.lock();
    defer simple_timer_mutex.unlock();

    simple_timers.put(timer_id, .{
        .deadline_ns = deadline,
        .fired = false,
    }) catch {};

    return timer_id;
}

/// Check if a timer has fired (deadline passed)
pub fn timerReady(timer_id: u64) bool {
    ensureSimpleTimersInit();

    simple_timer_mutex.lock();
    defer simple_timer_mutex.unlock();

    if (simple_timers.getPtr(timer_id)) |timer| {
        if (timer.fired) return true;

        const now = std.time.nanoTimestamp();
        if (now >= timer.deadline_ns) {
            timer.fired = true;
            return true;
        }
        return false;
    }
    return true; // Unknown timer treated as complete
}

/// Remove a completed timer to free memory
pub fn removeTimer(timer_id: u64) void {
    ensureSimpleTimersInit();

    simple_timer_mutex.lock();
    defer simple_timer_mutex.unlock();

    _ = simple_timers.remove(timer_id);
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
