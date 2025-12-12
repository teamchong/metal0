const std = @import("std");

/// Green thread - lightweight cooperative thread
pub const GreenThread = struct {
    id: u64,
    result: ?*anyopaque,
    state: State = .ready,
    func_ptr: ?*const anyopaque = null,
    args_ptr: ?*anyopaque = null,
    stack: ?[]u8 = null,

    pub const State = enum {
        ready,
        running,
        blocked,
        completed,
    };
};

/// Simple cooperative scheduler using OS threads as workers
/// This is a basic implementation - spawn creates real threads for now
pub const Scheduler = struct {
    allocator: std.mem.Allocator,
    next_id: std.atomic.Value(u64),
    threads: std.ArrayList(*GreenThread),
    mutex: std.Thread.Mutex,
    worker_threads: std.ArrayList(std.Thread),

    pub fn init(allocator: std.mem.Allocator, num_threads: usize) !Scheduler {
        _ = num_threads; // Worker pool size (for future M:N scheduling)
        return Scheduler{
            .allocator = allocator,
            .next_id = std.atomic.Value(u64).init(1),
            .threads = .{},
            .mutex = .{},
            .worker_threads = .{},
        };
    }

    pub fn spawn(self: *Scheduler, func: anytype, args: anytype) !*GreenThread {
        const gt = try self.allocator.create(GreenThread);
        gt.* = .{
            .id = self.next_id.fetchAdd(1, .monotonic),
            .result = null,
            .state = .ready,
        };

        self.mutex.lock();
        try self.threads.append(self.allocator, gt);
        self.mutex.unlock();

        // Spawn OS thread to run the green thread function
        // Note: M:N scheduling would improve performance for many green threads
        const Args = @TypeOf(args);
        const Wrapper = struct {
            fn run(green_thread: *GreenThread, captured_func: @TypeOf(func), captured_args: Args) void {
                green_thread.state = .running;
                // Call the function
                const result = @call(.auto, captured_func, captured_args);
                // Store result if it's a pointer type
                if (@TypeOf(result) == *anyopaque or @typeInfo(@TypeOf(result)) == .pointer) {
                    green_thread.result = @ptrCast(@constCast(&result));
                }
                green_thread.state = .completed;
            }
        };

        const thread = try std.Thread.spawn(.{}, Wrapper.run, .{ gt, func, args });

        self.mutex.lock();
        try self.worker_threads.append(self.allocator, thread);
        self.mutex.unlock();

        return gt;
    }

    pub fn wait(self: *Scheduler, thread: *GreenThread) !void {
        _ = self;
        // Spin wait until completed
        while (thread.state != .completed) {
            std.Thread.yield();
        }
    }

    pub fn yield(self: *Scheduler) void {
        _ = self;
        // Yield to OS scheduler
        std.Thread.yield();
    }

    pub fn shutdown(self: *Scheduler) void {
        // Join all worker threads
        self.mutex.lock();
        for (self.worker_threads.items) |t| {
            t.join();
        }
        self.worker_threads.deinit(self.allocator);

        // Free green thread structures
        for (self.threads.items) |gt| {
            self.allocator.destroy(gt);
        }
        self.threads.deinit(self.allocator);
        self.mutex.unlock();
    }
};
