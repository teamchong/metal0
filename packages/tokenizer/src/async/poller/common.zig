const std = @import("std");
const Task = @import("../task.zig").Task;

/// I/O event types (can be OR'd together)
pub const READABLE = 0x01;
pub const WRITABLE = 0x02;
pub const ERROR = 0x04;
pub const HANGUP = 0x08;

/// I/O event ready notification
pub const Event = struct {
    /// File descriptor that's ready
    fd: std.posix.fd_t,

    /// Events that occurred (READABLE | WRITABLE | ERROR)
    events: u32,

    /// Task waiting for this I/O
    task: *Task,
};

/// Platform-specific poller implementation
pub const Poller = switch (@import("builtin").target.os.tag) {
    .linux => @import("epoll.zig").EpollPoller,
    .macos, .freebsd, .openbsd, .netbsd, .dragonfly => @import("kqueue.zig").KqueuePoller,
    else => @compileError("Platform not supported for I/O polling"),
};

// Common poller interface (all implementations must provide these):
//
// fn init(allocator: std.mem.Allocator) !Self
// fn deinit(self: *Self) void
// fn register(self: *Self, fd: std.posix.fd_t, events: u32, task: *Task) !void
// fn unregister(self: *Self, fd: std.posix.fd_t) !void
// fn wait(self: *Self, timeout_ms: i32) ![]Event
// fn modify(self: *Self, fd: std.posix.fd_t, events: u32) !void

/// Statistics for poller performance
pub const PollerStats = struct {
    /// Total registrations
    total_registered: u64,

    /// Total unregistrations
    total_unregistered: u64,

    /// Total wait calls
    total_waits: u64,

    /// Total events returned
    total_events: u64,

    /// Total timeouts
    total_timeouts: u64,

    /// Average events per wait
    pub fn avgEventsPerWait(self: PollerStats) f64 {
        if (self.total_waits == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_events)) / @as(f64, @floatFromInt(self.total_waits));
    }
};

/// Helper to convert event mask to string (for debugging)
pub fn eventMaskToString(allocator: std.mem.Allocator, events: u32) ![]const u8 {
    var parts = std.ArrayList([]const u8){};
    defer parts.deinit(allocator);

    if (events & READABLE != 0) try parts.append(allocator, "READABLE");
    if (events & WRITABLE != 0) try parts.append(allocator, "WRITABLE");
    if (events & ERROR != 0) try parts.append(allocator, "ERROR");
    if (events & HANGUP != 0) try parts.append(allocator, "HANGUP");

    if (parts.items.len == 0) {
        return allocator.dupe(u8, "NONE");
    }

    // Join with " | "
    var total_len: usize = 0;
    for (parts.items) |part| {
        total_len += part.len;
    }
    total_len += (parts.items.len - 1) * 3; // " | " separators

    const result = try allocator.alloc(u8, total_len);
    var pos: usize = 0;

    for (parts.items, 0..) |part, i| {
        @memcpy(result[pos .. pos + part.len], part);
        pos += part.len;

        if (i < parts.items.len - 1) {
            @memcpy(result[pos .. pos + 3], " | ");
            pos += 3;
        }
    }

    return result;
}

test "event constants are distinct" {
    try std.testing.expect(READABLE != WRITABLE);
    try std.testing.expect(READABLE != ERROR);
    try std.testing.expect(READABLE != HANGUP);
    try std.testing.expect(WRITABLE != ERROR);
    try std.testing.expect(WRITABLE != HANGUP);
    try std.testing.expect(ERROR != HANGUP);
}

test "eventMaskToString" {
    const allocator = std.testing.allocator;

    const none = try eventMaskToString(allocator, 0);
    defer allocator.free(none);
    try std.testing.expectEqualStrings("NONE", none);

    const readable = try eventMaskToString(allocator, READABLE);
    defer allocator.free(readable);
    try std.testing.expectEqualStrings("READABLE", readable);

    const rw = try eventMaskToString(allocator, READABLE | WRITABLE);
    defer allocator.free(rw);
    try std.testing.expectEqualStrings("READABLE | WRITABLE", rw);

    const all = try eventMaskToString(allocator, READABLE | WRITABLE | ERROR | HANGUP);
    defer allocator.free(all);
    try std.testing.expectEqualStrings("READABLE | WRITABLE | ERROR | HANGUP", all);
}
