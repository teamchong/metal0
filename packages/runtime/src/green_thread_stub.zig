const std = @import("std");

// Stub until goroutine runtime is implemented
pub const GreenThread = struct {
    id: u64,
    result: ?*anyopaque,
};

pub const Scheduler = struct {
    pub fn init(allocator: std.mem.Allocator, num_threads: usize) !Scheduler {
        _ = allocator;
        _ = num_threads;
        return Scheduler{};
    }

    pub fn spawn(self: *Scheduler, func: anytype, args: anytype) !*GreenThread {
        _ = self;
        _ = func;
        _ = args;
        @panic("TODO: Goroutine runtime not implemented yet");
    }

    pub fn wait(self: *Scheduler, thread: *GreenThread) !void {
        _ = self;
        _ = thread;
        @panic("TODO: Goroutine runtime not implemented yet");
    }

    pub fn yield(self: *Scheduler) void {
        _ = self;
        @panic("TODO: Goroutine runtime not implemented yet");
    }

    pub fn shutdown(self: *Scheduler) void {
        _ = self;
    }
};
