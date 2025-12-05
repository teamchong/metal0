const std = @import("std");

pub const GreenThread = struct {
    id: u64,
    stack: []align(16) u8,
    state: State,
    result: ?*anyopaque,
    cpu_context: CpuContext,
    user_context: ?*anyopaque,
    func_ptr: *const fn (?*anyopaque) void,
    context_cleanup: ?*const fn (*GreenThread, std.mem.Allocator) void, // Optional cleanup for user_context

    pub const State = enum {
        ready,
        running,
        blocked,
        completed,
    };

    pub const CpuContext = struct {
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

    pub fn init(
        allocator: std.mem.Allocator,
        id: u64,
        func: *const fn (?*anyopaque) void,
        user_ctx: ?*anyopaque,
        cleanup: ?*const fn (*GreenThread, std.mem.Allocator) void,
    ) !*GreenThread {
        const thread = try allocator.create(GreenThread);
        errdefer allocator.destroy(thread);

        const stack = try allocator.alignedAlloc(u8, .@"16", STACK_SIZE);
        errdefer allocator.free(stack);

        thread.* = GreenThread{
            .id = id,
            .stack = stack,
            .state = .ready,
            .result = null,
            .cpu_context = .{},
            .user_context = user_ctx,
            .func_ptr = func,
            .context_cleanup = cleanup,
        };

        // Initialize stack pointer to top of stack (stacks grow downward)
        thread.cpu_context.rsp = @intFromPtr(stack.ptr) + stack.len - 16;
        thread.cpu_context.rbp = thread.cpu_context.rsp;

        return thread;
    }

    pub fn deinit(self: *GreenThread, allocator: std.mem.Allocator) void {
        allocator.free(self.stack);
        allocator.destroy(self);
    }

    pub fn run(self: *GreenThread) void {
        self.state = .running;
        self.func_ptr(self.user_context);
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
        fn func(ctx: ?*anyopaque) void {
            _ = ctx;
            // Simple test function
        }
    };

    const thread = try GreenThread.init(allocator, 1, TestFunc.func, null, null);
    defer thread.deinit(allocator);

    try std.testing.expectEqual(@as(u64, 1), thread.id);
    try std.testing.expectEqual(GreenThread.State.ready, thread.state);
    try std.testing.expectEqual(@as(usize, 4 * 1024), thread.stack.len);
}

test "GreenThread run and complete" {
    const allocator = std.testing.allocator;

    const Context = struct {
        value: usize,
    };

    const TestFunc = struct {
        fn func(ctx: ?*anyopaque) void {
            const context: *Context = @ptrCast(@alignCast(ctx.?));
            context.value = 42;
        }
    };

    var context = Context{ .value = 0 };
    const thread = try GreenThread.init(allocator, 1, TestFunc.func, &context, null);
    defer thread.deinit(allocator);

    try std.testing.expectEqual(GreenThread.State.ready, thread.state);

    thread.run();

    try std.testing.expectEqual(GreenThread.State.completed, thread.state);
    try std.testing.expectEqual(@as(usize, 42), context.value);
}
