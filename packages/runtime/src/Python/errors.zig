/// errors - Error Handling
/// Mirrors cpython/Python/errors.c
///
/// This module provides Python's error handling API:
/// - Setting, getting, and clearing exceptions
/// - Exception matching and normalization
/// - Exception chaining
/// - Formatted error messages
/// - Syntax error handling
///
/// Works with runtime/exceptions.zig which defines exception types and thread-local storage.

const std = @import("std");

// Re-export submodules
pub const thread_state = @import("errors/thread_state.zig");
pub const exception_value = @import("errors/exception_value.zig");
pub const core_api = @import("errors/core_api.zig");
pub const matching = @import("errors/matching.zig");
pub const chaining = @import("errors/chaining.zig");
pub const formatting = @import("errors/formatting.zig");
pub const convenience = @import("errors/convenience.zig");
pub const syntax_errors = @import("errors/syntax_errors.zig");
pub const unraisable = @import("errors/unraisable.zig");
pub const types = @import("errors/types.zig");
pub const init_module = @import("errors/init.zig");

// Re-export types
pub const ThreadState = thread_state.ThreadState;
pub const ExceptionStackItem = thread_state.ExceptionStackItem;
pub const ExceptionValue = exception_value.ExceptionValue;

// Re-export thread state functions
pub const getThreadState = thread_state.getThreadState;
pub const getTopmostException = thread_state.getTopmostException;

// Re-export core API functions
pub const setRaisedException = core_api.setRaisedException;
pub const setObject = core_api.setObject;
pub const setNone = core_api.setNone;
pub const setString = core_api.setString;
pub const setKeyError = core_api.setKeyError;
pub const getRaisedException = core_api.getRaisedException;
pub const occurred = core_api.occurred;
pub const occurredType = core_api.occurredType;
pub const fetch = core_api.fetch;
pub const getHandledException = core_api.getHandledException;
pub const setHandledException = core_api.setHandledException;
pub const clear = core_api.clear;
pub const restore = core_api.restore;

// Re-export matching functions
pub const givenExceptionMatches = matching.givenExceptionMatches;
pub const exceptionMatches = matching.exceptionMatches;

// Re-export chaining functions
pub const chainExceptions = chaining.chainExceptions;
pub const chainExceptions1 = chaining.chainExceptions1;

// Re-export formatting functions
pub const format = formatting.format;
pub const formatFromCause = formatting.formatFromCause;

// Re-export convenience functions
pub const badArgument = convenience.badArgument;
pub const noMemory = convenience.noMemory;
pub const setFromErrno = convenience.setFromErrno;
pub const setFromErrnoWithFilename = convenience.setFromErrnoWithFilename;
pub const setModuleNotFoundError = convenience.setModuleNotFoundError;
pub const setImportError = convenience.setImportError;
pub const badInternalCall = convenience.badInternalCall;

// Re-export syntax error functions
pub const syntaxLocation = syntax_errors.syntaxLocation;
pub const raiseSyntaxError = syntax_errors.raiseSyntaxError;

// Re-export unraisable functions
pub const writeUnraisable = unraisable.writeUnraisable;
pub const formatUnraisable = unraisable.formatUnraisable;

// Re-export type creation functions
pub const newException = types.newException;
pub const newExceptionWithDoc = types.newExceptionWithDoc;

// Re-export initialization functions
pub const init = init_module.init;
pub const fini = init_module.fini;

// ============================================================================
// Tests
// ============================================================================

test "setString and occurred" {
    setString("ValueError", "test error");
    try std.testing.expect(occurred());
    try std.testing.expectEqualStrings("ValueError", occurredType().?);
    clear();
    try std.testing.expect(!occurred());
}

test "exception matching" {
    try std.testing.expect(givenExceptionMatches("ValueError", "ValueError"));
    try std.testing.expect(givenExceptionMatches("ValueError", "Exception"));
    try std.testing.expect(givenExceptionMatches("ValueError", "BaseException"));
    try std.testing.expect(!givenExceptionMatches("ValueError", "TypeError"));

    try std.testing.expect(givenExceptionMatches("IndexError", "LookupError"));
    try std.testing.expect(givenExceptionMatches("KeyError", "LookupError"));
    try std.testing.expect(!givenExceptionMatches("ValueError", "LookupError"));

    try std.testing.expect(givenExceptionMatches("FileNotFoundError", "OSError"));
    try std.testing.expect(givenExceptionMatches("PermissionError", "OSError"));
}

test "exception chaining" {
    // Set first exception
    setString("ValueError", "first error");
    try std.testing.expect(occurred());

    // Chain second exception
    chainExceptions("TypeError", "second error", null);
    try std.testing.expect(occurred());
    try std.testing.expectEqualStrings("TypeError", occurredType().?);

    const tstate = getThreadState();
    if (tstate.current_exception) |exc| {
        try std.testing.expect(exc.context != null);
        try std.testing.expectEqualStrings("ValueError", exc.context.?.type_name);
    }

    clear();
}

test "format error message" {
    format("ValueError", "invalid value: {d}", .{42});
    try std.testing.expect(occurred());

    const fetched = fetch();
    try std.testing.expectEqualStrings("ValueError", fetched.type_name.?);
    try std.testing.expectEqualStrings("invalid value: 42", fetched.value.?);

    clear();
}
