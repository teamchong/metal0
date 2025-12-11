/// thread_state - Thread State Emulation
/// Mirrors cpython/Python/errors.c thread state management
///
/// This module provides thread-local storage for exception state.
/// In CPython this is PyThreadState, we use a simpler thread-local approach.

const ExceptionValue = @import("exception_value.zig").ExceptionValue;

/// Emulated thread state for storing exception info
/// In CPython this is PyThreadState, we use a simpler thread-local approach
pub const ThreadState = struct {
    /// Current raised exception (the active error)
    current_exception: ?*ExceptionValue = null,

    /// Exception info stack for nested exception handling
    exc_info: *ExceptionStackItem = undefined,

    /// Recursion headroom for exception normalization
    recursion_headroom: i32 = 0,
};

/// Exception stack item - tracks handled exceptions
pub const ExceptionStackItem = struct {
    exc_value: ?*ExceptionValue = null,
    previous_item: ?*ExceptionStackItem = null,
};

/// Thread-local thread state
threadlocal var thread_state: ThreadState = .{};

/// Thread-local root exception stack item
threadlocal var root_exc_info: ExceptionStackItem = .{};

/// Get the current thread state
pub fn getThreadState() *ThreadState {
    // Initialize exc_info on first access
    if (thread_state.exc_info == undefined) {
        thread_state.exc_info = &root_exc_info;
    }
    return &thread_state;
}

/// Get topmost exception from exc_info stack
/// Mirrors: _PyErr_GetTopmostException
pub fn getTopmostException(tstate: *ThreadState) *ExceptionStackItem {
    var exc_info = tstate.exc_info;
    while (exc_info.exc_value == null and exc_info.previous_item != null) {
        exc_info = exc_info.previous_item.?;
    }
    return exc_info;
}
