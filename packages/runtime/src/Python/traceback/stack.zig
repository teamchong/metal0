/// traceback/stack - Thread-local Traceback Stack Management
/// Mirrors cpython/Python/traceback.c
///
/// This module provides:
/// - Thread-local stack for capturing traceback entries
/// - Push/pop operations for function entry/exit
/// - Stack retrieval and clearing

const std = @import("std");
const types = @import("types.zig");

/// Thread-local traceback stack
threadlocal var traceback_stack: [types.MAX_STACK_ENTRIES]types.TracebackEntry = undefined;
threadlocal var traceback_stack_len: usize = 0;

/// Push a traceback entry
pub fn pushEntry(filename: []const u8, lineno: i32, name: []const u8) void {
    if (traceback_stack_len < types.MAX_STACK_ENTRIES) {
        traceback_stack[traceback_stack_len] = .{
            .filename = filename,
            .lineno = lineno,
            .name = name,
        };
        traceback_stack_len += 1;
    }
}

/// Pop a traceback entry
pub fn popEntry() void {
    if (traceback_stack_len > 0) {
        traceback_stack_len -= 1;
    }
}

/// Get current traceback stack
pub fn getStack() []const types.TracebackEntry {
    return traceback_stack[0..traceback_stack_len];
}

/// Clear traceback stack
pub fn clearStack() void {
    traceback_stack_len = 0;
}
