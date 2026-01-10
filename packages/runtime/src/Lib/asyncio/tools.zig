//! asyncio.tools - Utility functions for asyncio
//! Reference: Various asyncio internal utilities

const std = @import("std");
const futures = @import("futures.zig");
const tasks = @import("tasks.zig");

/// Get all running tasks (debug utility)
pub fn getAllRunningTasks(allocator: std.mem.Allocator) ![]const *tasks.Task {
    _ = allocator;
    // Would query the global task registry
    return &[_]*tasks.Task{};
}

/// Print all running tasks (debug utility)
pub fn printRunningTasks(writer: anytype) !void {
    try writer.print("Running tasks:\n", .{});
    // Would enumerate tasks from registry
    try writer.print("  (none)\n", .{});
}

/// Check if we're in the main thread
pub fn isMainThread() bool {
    // Simplified - would check against main thread ID
    return true;
}

/// Get current event loop or create new one
pub fn getOrCreateEventLoop(allocator: std.mem.Allocator) !*anyopaque {
    _ = allocator;
    // Would get or create event loop
    return error.NotImplemented;
}

/// Safe way to cancel a task
pub fn safeCancel(task: *tasks.Task) void {
    task.markPreempted();
}

/// Check if object is a coroutine or task
pub fn isCoroutineOrTask(obj: anytype) bool {
    const T = @TypeOf(obj);
    if (@typeInfo(T) == .pointer) {
        const Child = @typeInfo(T).pointer.child;
        if (Child == tasks.Task) return true;
        if (@hasDecl(Child, "poll")) return true;
    }
    return false;
}

// Tests
test "isMainThread" {
    try std.testing.expect(isMainThread());
}

test "getAllRunningTasks empty" {
    const allocator = std.testing.allocator;
    const running = try getAllRunningTasks(allocator);
    try std.testing.expectEqual(@as(usize, 0), running.len);
}
