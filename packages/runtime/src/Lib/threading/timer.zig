//! Timer - Call a function after a delay
//!
//! CPython source: Lib/threading.py (Timer class)

const std = @import("std");

/// A timer that calls a function after a delay
pub const Timer = struct {
    const Self = @This();

    thread: ?std.Thread,
    function: *const fn () void,
    interval: f64,
    cancelled: bool,
    finished: bool,

    pub fn init(interval: f64, function: *const fn () void) Self {
        return .{
            .thread = null,
            .function = function,
            .interval = interval,
            .cancelled = false,
            .finished = false,
        };
    }

    /// Start the timer
    pub fn start(self: *Self) !void {
        self.thread = try std.Thread.spawn(.{}, timerRunner, .{self});
    }

    fn timerRunner(timer: *Self) void {
        const ns = @as(u64, @intFromFloat(timer.interval * std.time.ns_per_s));
        std.Thread.sleep(ns);

        if (!timer.cancelled) {
            timer.function();
        }
        timer.finished = true;
    }

    /// Cancel the timer
    pub fn cancel(self: *Self) void {
        self.cancelled = true;
    }

    /// Wait for the timer to complete
    pub fn join(self: *Self) void {
        if (self.thread) |*t| {
            t.join();
            self.thread = null;
        }
    }

    /// Check if the timer has finished
    pub fn isFinished(self: *Self) bool {
        return self.finished;
    }
};
