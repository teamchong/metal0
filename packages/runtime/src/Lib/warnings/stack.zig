//! Call stack tracking for stacklevel support
//!
//! Provides thread-local call stack management for warning context resolution.

const std = @import("std");
const types = @import("types.zig");

/// Thread-local call stack for stacklevel resolution
threadlocal var call_stack: std.ArrayListUnmanaged(types.FrameInfo) = .{};
threadlocal var call_stack_allocator: ?std.mem.Allocator = null;

/// Push a frame onto the call stack (called by generated code on function entry)
pub fn pushFrame(allocator: std.mem.Allocator, filename: []const u8, lineno: usize, function: []const u8) void {
    if (call_stack_allocator == null) {
        call_stack_allocator = allocator;
    }
    call_stack.append(allocator, .{ .filename = filename, .lineno = lineno, .function = function }) catch {};
}

/// Pop a frame from the call stack (called by generated code on function exit)
pub fn popFrame() void {
    if (call_stack.items.len > 0) {
        _ = call_stack.pop();
    }
}

/// Clear the call stack
pub fn clearCallStack() void {
    if (call_stack_allocator) |alloc| {
        call_stack.deinit(alloc);
        call_stack = .{};
    }
}

/// Get frame info at a specific stack level (1 = immediate caller, 2 = caller's caller, etc.)
pub fn getFrameAtLevel(stacklevel: usize) ?types.FrameInfo {
    if (call_stack.items.len >= stacklevel) {
        const frame_idx = call_stack.items.len - stacklevel;
        return call_stack.items[frame_idx];
    }
    return null;
}
