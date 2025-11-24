const std = @import("std");

pub const GreenThread = struct {
    id: u64,
    stack: []align(16) u8,
    state: State,
    result: ?*anyopaque,
    context: Context,
    func_ptr: *const fn (*GreenThread) void,

    pub const State = enum {
        ready,
        running,
        blocked,
        completed,
    };

    pub const Context = struct {
        // Saved registers for context switching
        rsp: usize = 0, // Stack pointer
        rbp: usize = 0, // Base pointer
        rip: usize = 0, // Instruction pointer
        r12: usize = 0,
        r13: usize = 0,
        r14: usize = 0,
        r15: usize = 0,
        rbx: usize = 0,
    };

    const STACK_SIZE = 4 * 1024; // 4KB per thread

    pub fn init(allocator: std.mem.Allocator, id: u64, func: *const fn (*GreenThread) void) !*GreenThread {
        const thread = try allocator.create(GreenThread);
        errdefer allocator.destroy(thread);

        const stack = try allocator.alignedAlloc(u8, .@"16", STACK_SIZE);
        errdefer allocator.free(stack);

        thread.* = GreenThread{
            .id = id,
            .stack = stack,
            .state = .ready,
            .result = null,
            .context = .{},
            .func_ptr = func,
        };

        // Initialize stack pointer to top of stack (stacks grow downward)
        thread.context.rsp = @intFromPtr(stack.ptr) + stack.len - 16;
        thread.context.rbp = thread.context.rsp;

        return thread;
    }

    pub fn deinit(self: *GreenThread, allocator: std.mem.Allocator) void {
        allocator.free(self.stack);
        allocator.destroy(self);
    }

    pub fn run(self: *GreenThread) void {
        self.state = .running;
        self.func_ptr(self);
        self.state = .completed;
    }

    pub fn isCompleted(self: *const GreenThread) bool {
        return self.state == .completed;
    }

    pub fn isReady(self: *const GreenThread) bool {
        return self.state == .ready;
    }

    pub fn isBlocked(self: *const GreenThread) bool {
        return self.state == .blocked;
    }
};

test "GreenThread basic creation" {
    const allocator = std.testing.allocator;

    const TestFunc = struct {
        fn func(thread: *GreenThread) void {
            _ = thread;
            // Simple test function
        }
    };

    const thread = try GreenThread.init(allocator, 1, TestFunc.func);
    defer thread.deinit(allocator);

    try std.testing.expectEqual(@as(u64, 1), thread.id);
    try std.testing.expectEqual(GreenThread.State.ready, thread.state);
    try std.testing.expectEqual(@as(usize, 4 * 1024), thread.stack.len);
}

test "GreenThread run and complete" {
    const allocator = std.testing.allocator;

    const TestFunc = struct {
        fn func(thread: *GreenThread) void {
            thread.result = @ptrFromInt(@as(usize, 42));
        }
    };

    const thread = try GreenThread.init(allocator, 1, TestFunc.func);
    defer thread.deinit(allocator);

    try std.testing.expectEqual(GreenThread.State.ready, thread.state);

    thread.run();

    try std.testing.expectEqual(GreenThread.State.completed, thread.state);
    try std.testing.expectEqual(@as(usize, 42), @intFromPtr(thread.result.?));
}
