//! Thread class - A class representing a thread of control
//!
//! CPython source: Lib/threading.py (Thread class)

const std = @import("std");

/// A class that represents a thread of control
pub const Thread = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    name: []const u8,
    daemon: bool,
    ident: ?std.Thread.Id,
    native_id: ?std.Thread.Id,
    started: bool,
    stopped: bool,
    thread: ?std.Thread,
    target: ?*const fn () void,

    /// Thread-local exception info (simplified)
    exc_info: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) Self {
        return .{
            .allocator = allocator,
            .name = name,
            .daemon = false,
            .ident = null,
            .native_id = null,
            .started = false,
            .stopped = false,
            .thread = null,
            .target = null,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Start the thread's activity
    pub fn start(self: *Self) !void {
        if (self.started) return error.ThreadAlreadyStarted;

        self.started = true;
        self.thread = try std.Thread.spawn(.{}, threadRunner, .{self});
        self.ident = self.thread.?.getCurrentId();
        self.native_id = self.ident;
    }

    fn threadRunner(thread_obj: *Self) void {
        if (thread_obj.target) |target| {
            target();
        } else {
            thread_obj.run();
        }
        thread_obj.stopped = true;
    }

    /// Method representing the thread's activity (override in subclass)
    pub fn run(self: *Self) void {
        _ = self;
        // Default implementation does nothing
    }

    /// Wait until the thread terminates
    pub fn join(self: *Self, timeout: ?f64) !void {
        if (!self.started) return error.ThreadNotStarted;

        if (timeout) |t| {
            // Timed join (simplified - just sleep and check)
            const ns = @as(u64, @intFromFloat(t * std.time.ns_per_s));
            _ = ns;
            // For simplicity, just do blocking join
        }

        if (self.thread) |*t| {
            t.join();
            self.thread = null;
        }
    }

    /// Return whether the thread is alive
    pub fn isAlive(self: *Self) bool {
        return self.started and !self.stopped;
    }

    /// Return the thread's name
    pub fn getName(self: *Self) []const u8 {
        return self.name;
    }

    /// Set the thread's name
    pub fn setName(self: *Self, name: []const u8) void {
        self.name = name;
    }

    /// Return whether this is a daemon thread
    pub fn isDaemon(self: *Self) bool {
        return self.daemon;
    }

    /// Set whether this is a daemon thread
    pub fn setDaemon(self: *Self, daemon: bool) void {
        if (self.started) return; // Cannot change after start
        self.daemon = daemon;
    }
};

// ============================================================================
// Thread Registry - tracks all active threads
// ============================================================================

pub const ThreadRegistry = struct {
    var threads: [256]?*Thread = [_]?*Thread{null} ** 256;
    var count: usize = 1; // Start at 1 for main thread
    var lock: std.Thread.Mutex = .{};

    pub fn register(thread: *Thread) void {
        lock.lock();
        defer lock.unlock();
        for (&threads) |*slot| {
            if (slot.* == null) {
                slot.* = thread;
                count += 1;
                return;
            }
        }
    }

    pub fn unregister(thread: *Thread) void {
        lock.lock();
        defer lock.unlock();
        for (&threads) |*slot| {
            if (slot.* == thread) {
                slot.* = null;
                if (count > 1) count -= 1;
                return;
            }
        }
    }

    pub fn getCount() usize {
        return @atomicLoad(usize, &count, .seq_cst);
    }

    pub fn getAll(allocator: std.mem.Allocator) ![]const *Thread {
        lock.lock();
        defer lock.unlock();

        var result = std.ArrayList(*Thread).init(allocator);
        for (threads) |maybe_thread| {
            if (maybe_thread) |t| {
                try result.append(t);
            }
        }
        return result.toOwnedSlice();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Thread init" {
    const allocator = std.testing.allocator;

    var thread = Thread.init(allocator, "TestThread");
    defer thread.deinit();

    try std.testing.expectEqualStrings("TestThread", thread.getName());
    try std.testing.expect(!thread.isDaemon());
    try std.testing.expect(!thread.isAlive());
}
