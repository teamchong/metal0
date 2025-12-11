/// chaining - Exception Chaining
/// Mirrors cpython/Python/errors.c exception chaining logic
///
/// This module handles exception chaining:
/// - Implicit chaining (context) - "During handling of..."
/// - Explicit chaining (cause) - "raise X from Y"

const thread_state_mod = @import("thread_state.zig");
const ExceptionValue = @import("exception_value.zig").ExceptionValue;
const core_api = @import("core_api.zig");

const getThreadState = thread_state_mod.getThreadState;
const occurred = core_api.occurred;
const getRaisedException = core_api.getRaisedException;
const restore = core_api.restore;
const setRaisedException = core_api.setRaisedException;

/// Chain exceptions - set context for implicit chaining
/// Mirrors: _PyErr_ChainExceptions
pub fn chainExceptions(type_name: []const u8, value: []const u8, traceback: ?[]const u8) void {
    if (occurred()) {
        // Get current exception
        const current = getRaisedException();

        // Create and set new exception
        restore(type_name, value, traceback);

        // Get the new exception and set context
        const tstate = getThreadState();
        if (tstate.current_exception) |new_exc| {
            new_exc.setContext(current);
        }
    } else {
        restore(type_name, value, traceback);
    }
}

/// Chain a single exception value
/// Mirrors: _PyErr_ChainExceptions1
pub fn chainExceptions1(exc: *ExceptionValue) void {
    if (occurred()) {
        const current = getRaisedException();
        const tstate = getThreadState();
        setRaisedException(tstate, exc);
        exc.setContext(current);
    } else {
        const tstate = getThreadState();
        setRaisedException(tstate, exc);
    }
}
