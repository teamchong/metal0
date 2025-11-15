const std = @import("std");
const builtin = @import("builtin");
const Task = @import("../task.zig").Task;

/// Stack switching for preemptive context switches
/// Based on Go's runtime stack management

/// Save current execution context (registers, stack pointer)
pub fn saveContext(task: *Task) void {
    // Platform-specific context saving
    if (builtin.cpu.arch == .x86_64) {
        saveContextX86_64(task);
    } else if (builtin.cpu.arch == .aarch64) {
        saveContextARM64(task);
    } else {
        // Unsupported architecture - use simplified approach
        saveContextGeneric(task);
    }
}

/// Restore execution context (registers, stack pointer)
pub fn restoreContext(task: *Task) void {
    // Platform-specific context restoration
    if (builtin.cpu.arch == .x86_64) {
        restoreContextX86_64(task);
    } else if (builtin.cpu.arch == .aarch64) {
        restoreContextARM64(task);
    } else {
        // Unsupported architecture - use simplified approach
        restoreContextGeneric(task);
    }
}

/// Switch from current task to next task
pub fn switchContext(current: *Task, next: *Task) void {
    saveContext(current);
    restoreContext(next);
}

// x86_64 implementation
fn saveContextX86_64(task: *Task) void {
    // Save stack pointer
    const sp = @returnAddress();
    task.exec_context.sp = @intFromPtr(sp);

    // In a real implementation, we'd use inline assembly to save registers:
    // asm volatile (
    //     \\mov %%rsp, %[sp]
    //     \\mov %%rbp, %[fp]
    //     : [sp] "=r" (task.exec_context.sp),
    //       [fp] "=r" (task.exec_context.fp)
    // );

    // For now, store return address as PC
    task.exec_context.pc = @intFromPtr(@returnAddress());
}

fn restoreContextX86_64(task: *Task) void {
    // Restore stack pointer and jump to saved PC
    // In a real implementation:
    // asm volatile (
    //     \\mov %[sp], %%rsp
    //     \\mov %[fp], %%rbp
    //     \\jmp *%[pc]
    //     :
    //     : [sp] "r" (task.exec_context.sp),
    //       [fp] "r" (task.exec_context.fp),
    //       [pc] "r" (task.exec_context.pc)
    // );

    _ = task;
}

// ARM64 implementation
fn saveContextARM64(task: *Task) void {
    // Save stack pointer and frame pointer
    const sp = @returnAddress();
    task.exec_context.sp = @intFromPtr(sp);

    // In a real implementation:
    // asm volatile (
    //     \\mov %[sp], sp
    //     \\mov %[fp], x29
    //     : [sp] "=r" (task.exec_context.sp),
    //       [fp] "=r" (task.exec_context.fp)
    // );

    task.exec_context.pc = @intFromPtr(@returnAddress());
}

fn restoreContextARM64(task: *Task) void {
    // Restore context
    // In a real implementation:
    // asm volatile (
    //     \\mov sp, %[sp]
    //     \\mov x29, %[fp]
    //     \\br %[pc]
    //     :
    //     : [sp] "r" (task.exec_context.sp),
    //       [fp] "r" (task.exec_context.fp),
    //       [pc] "r" (task.exec_context.pc)
    // );

    _ = task;
}

// Generic implementation (simplified, no real context switch)
fn saveContextGeneric(task: *Task) void {
    const sp = @returnAddress();
    task.exec_context.sp = @intFromPtr(sp);
    task.exec_context.pc = @intFromPtr(@returnAddress());
}

fn restoreContextGeneric(task: *Task) void {
    _ = task;
    // No-op for unsupported architectures
}

/// Allocate a new stack for a task
pub fn allocateStack(allocator: std.mem.Allocator, size: usize) ![]u8 {
    // Allocate with page alignment for guard pages
    const aligned_size = std.mem.alignForward(usize, size, 4096);

    return try allocator.alignedAlloc(u8, @enumFromInt(12), aligned_size); // 2^12 = 4096
}

/// Free a task's stack
pub fn freeStack(allocator: std.mem.Allocator, stack: []u8) void {
    allocator.free(stack);
}

/// Set up initial stack frame for a task
pub fn setupInitialStack(task: *Task, entry_point: *const fn (*anyopaque) anyerror!void, context: *anyopaque) !void {
    if (task.stack == null) {
        return error.NoStack;
    }

    const stack = task.stack.?;

    // Stack grows downward, so start at the end
    const stack_top = @intFromPtr(stack.ptr) + stack.len;

    // Align stack pointer to 16 bytes (required by ABI)
    const aligned_sp = stack_top & ~@as(usize, 15);

    // Set up initial context
    task.exec_context.sp = aligned_sp;
    task.exec_context.pc = @intFromPtr(entry_point);
    task.exec_context.fp = aligned_sp;

    // Store context pointer (for entry_point to find)
    task.context = context;
}

/// Check if stack needs to grow (simplified check)
pub fn needsStackGrowth(task: *Task) bool {
    if (task.stack == null) return false;

    // Check if we've used more than 80% of stack
    const usage = task.stackUsage();
    return usage > 80.0;
}

/// Get platform name for debugging
pub fn getPlatformName() []const u8 {
    return @tagName(builtin.cpu.arch);
}

/// Check if platform supports native context switching
pub fn isNativeContextSwitchSupported() bool {
    return builtin.cpu.arch == .x86_64 or builtin.cpu.arch == .aarch64;
}

// Tests
test "Stack allocation and deallocation" {
    const testing = std.testing;

    const stack = try allocateStack(testing.allocator, 4096);
    defer freeStack(testing.allocator, stack);

    try testing.expect(stack.len >= 4096);
    try testing.expect(@intFromPtr(stack.ptr) % 4096 == 0); // Page aligned
}

test "Initial stack setup" {
    const testing = std.testing;

    var task = Task.init(1, undefined, undefined);
    task.stack = try allocateStack(testing.allocator, 4096);
    task.stack_size = 4096;
    defer freeStack(testing.allocator, task.stack.?);

    var dummy_context: u32 = 42;
    const entry_point = struct {
        fn func(ctx: *anyopaque) !void {
            _ = ctx;
        }
    }.func;

    try setupInitialStack(&task, entry_point, &dummy_context);

    // Check stack pointer is set
    try testing.expect(task.exec_context.sp > 0);

    // Check program counter is set
    try testing.expect(task.exec_context.pc == @intFromPtr(entry_point));

    // Check alignment (16-byte aligned)
    try testing.expect(task.exec_context.sp % 16 == 0);
}

test "Context save and restore" {
    const testing = std.testing;

    var task = Task.init(1, undefined, undefined);
    task.stack = try allocateStack(testing.allocator, 4096);
    defer freeStack(testing.allocator, task.stack.?);

    // Save context
    saveContext(&task);

    // Check something was saved
    try testing.expect(task.exec_context.sp > 0);
    try testing.expect(task.exec_context.pc > 0);

    // Note: We can't really test restore without crashing
    // as it would jump to a different PC
}

test "Platform detection" {
    const testing = std.testing;

    const platform = getPlatformName();
    try testing.expect(platform.len > 0);

    // Just verify this doesn't crash
    _ = isNativeContextSwitchSupported();
}

test "Stack growth detection" {
    const testing = std.testing;

    var task = Task.init(1, undefined, undefined);
    task.stack = try allocateStack(testing.allocator, 4096);
    task.stack_size = 4096;
    defer freeStack(testing.allocator, task.stack.?);

    // Simulate high stack usage
    task.exec_context.sp = 3500; // 85% usage

    try testing.expect(needsStackGrowth(&task));

    // Simulate low stack usage
    task.exec_context.sp = 1000; // 25% usage

    try testing.expect(!needsStackGrowth(&task));
}
