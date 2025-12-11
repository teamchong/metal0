/// core_api - Core Error Setting/Retrieval Functions
/// Mirrors cpython/Python/errors.c core API
///
/// This module provides the fundamental error handling operations:
/// - Setting exceptions
/// - Getting/fetching exceptions
/// - Clearing exceptions
/// - Checking if exceptions occurred

const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");
const exceptions = @import("../runtime/exceptions.zig");
const thread_state_mod = @import("thread_state.zig");
const ExceptionValue = @import("exception_value.zig").ExceptionValue;

const ThreadState = thread_state_mod.ThreadState;
const getThreadState = thread_state_mod.getThreadState;
const getTopmostException = thread_state_mod.getTopmostException;

// ============================================================================
// Core Error Setting Functions
// ============================================================================

/// Set the raised exception (replaces current)
/// Mirrors: _PyErr_SetRaisedException
pub fn setRaisedException(tstate: *ThreadState, exc: ?*ExceptionValue) void {
    const old_exc = tstate.current_exception;
    tstate.current_exception = exc;
    if (old_exc) |old| {
        old.destroy();
    }
}

/// Set exception from type and value
/// Mirrors: _PyErr_SetObject, PyErr_SetObject
pub fn setObject(exception_type: []const u8, value: []const u8) void {
    const tstate = getThreadState();
    const allocator = allocator_helper.fast_allocator;

    const exc = ExceptionValue.create(allocator, exception_type, value) catch {
        // Fall back to thread-local for OOM
        exceptions.setException(exception_type, value);
        return;
    };

    // Handle implicit exception chaining
    const exc_info = getTopmostException(tstate);
    if (exc_info.exc_value) |chain_exc| {
        exc.setContext(chain_exc);
    }

    setRaisedException(tstate, exc);

    // Also set in thread-local for compatibility
    exceptions.setException(exception_type, value);
}

/// Set exception with no value
/// Mirrors: _PyErr_SetNone, PyErr_SetNone
pub fn setNone(exception_type: []const u8) void {
    setObject(exception_type, "");
}

/// Set exception from type and string message
/// Mirrors: _PyErr_SetString, PyErr_SetString
pub fn setString(exception_type: []const u8, message: []const u8) void {
    setObject(exception_type, message);
}

/// Set a KeyError with proper tuple wrapping
/// Mirrors: _PyErr_SetKeyError
pub fn setKeyError(key_repr: []const u8) void {
    setObject("KeyError", key_repr);
}

// ============================================================================
// Error Retrieval Functions
// ============================================================================

/// Get the current raised exception
/// Mirrors: _PyErr_GetRaisedException, PyErr_GetRaisedException
pub fn getRaisedException() ?*ExceptionValue {
    const tstate = getThreadState();
    const exc = tstate.current_exception;
    tstate.current_exception = null;
    return exc;
}

/// Check if an exception is currently set
/// Mirrors: PyErr_Occurred, _PyErr_Occurred
pub fn occurred() bool {
    const tstate = getThreadState();
    return tstate.current_exception != null;
}

/// Get the current exception type name
pub fn occurredType() ?[]const u8 {
    const tstate = getThreadState();
    if (tstate.current_exception) |exc| {
        return exc.type_name;
    }
    return null;
}

/// Fetch exception (old API - type, value, traceback)
/// Mirrors: _PyErr_Fetch, PyErr_Fetch
pub fn fetch() struct { type_name: ?[]const u8, value: ?[]const u8, traceback: ?[]const u8 } {
    const exc = getRaisedException();
    if (exc) |e| {
        return .{
            .type_name = e.type_name,
            .value = e.message,
            .traceback = e.traceback,
        };
    }
    return .{ .type_name = null, .value = null, .traceback = null };
}

/// Get the handled exception (exc_info)
/// Mirrors: _PyErr_GetHandledException, PyErr_GetHandledException
pub fn getHandledException() ?*ExceptionValue {
    const tstate = getThreadState();
    const exc_info = getTopmostException(tstate);
    return exc_info.exc_value;
}

/// Set the handled exception
/// Mirrors: _PyErr_SetHandledException, PyErr_SetHandledException
pub fn setHandledException(exc: ?*ExceptionValue) void {
    const tstate = getThreadState();
    tstate.exc_info.exc_value = exc;
}

// ============================================================================
// Error Clearing Functions
// ============================================================================

/// Clear any currently set exception
/// Mirrors: _PyErr_Clear, PyErr_Clear
pub fn clear() void {
    const tstate = getThreadState();
    setRaisedException(tstate, null);
    exceptions.clearException();
}

/// Restore exception state (old API)
/// Mirrors: _PyErr_Restore, PyErr_Restore
pub fn restore(type_name: ?[]const u8, value: ?[]const u8, traceback: ?[]const u8) void {
    if (type_name == null) {
        clear();
        return;
    }

    const allocator = allocator_helper.fast_allocator;
    const exc = ExceptionValue.create(allocator, type_name.?, value orelse "") catch {
        exceptions.setException(type_name.?, value orelse "");
        return;
    };

    if (traceback) |tb| {
        exc.setTraceback(tb) catch {};
    }

    const tstate = getThreadState();
    setRaisedException(tstate, exc);
    exceptions.setException(type_name.?, value orelse "");
}
