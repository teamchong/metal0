/// formatting - Formatted Error Messages
/// Mirrors cpython/Python/errors.c formatted error functions
///
/// This module provides functions for creating exceptions with formatted messages.
/// Uses thread-local buffers for performance.

const std = @import("std");
const core_api = @import("core_api.zig");
const thread_state_mod = @import("thread_state.zig");
const ExceptionValue = @import("exception_value.zig").ExceptionValue;

const setString = core_api.setString;
const getRaisedException = core_api.getRaisedException;
const getThreadState = thread_state_mod.getThreadState;

/// Buffer for formatted error messages
threadlocal var format_buffer: [4096]u8 = undefined;

/// Set error with formatted message
/// Mirrors: _PyErr_Format, PyErr_Format
pub fn format(exception_type: []const u8, comptime fmt: []const u8, args: anytype) void {
    const message = std.fmt.bufPrint(&format_buffer, fmt, args) catch |err| {
        switch (err) {
            error.NoSpaceLeft => {
                setString(exception_type, &format_buffer);
                return;
            },
        }
    };
    setString(exception_type, message);
}

/// Set error from cause (explicit chaining)
/// Mirrors: _PyErr_FormatFromCause
pub fn formatFromCause(exception_type: []const u8, comptime fmt: []const u8, args: anytype) void {
    const current = getRaisedException();
    format(exception_type, fmt, args);
    const tstate = getThreadState();
    if (tstate.current_exception) |new_exc| {
        new_exc.setCause(current);
        new_exc.setContext(current);
    }
}
