/// matching - Exception Matching and Hierarchy
/// Mirrors cpython/Python/errors.c exception matching logic
///
/// This module provides exception type matching and inheritance checking.
/// Used for try/except handlers to determine if a caught exception matches
/// the expected type.

const std = @import("std");
const thread_state_mod = @import("thread_state.zig");
const ExceptionValue = @import("exception_value.zig").ExceptionValue;

const getThreadState = thread_state_mod.getThreadState;

/// Check if exception matches a given type
/// Mirrors: PyErr_GivenExceptionMatches
pub fn givenExceptionMatches(err_type: []const u8, exc_type: []const u8) bool {
    // Direct match
    if (std.mem.eql(u8, err_type, exc_type)) {
        return true;
    }

    // Check inheritance hierarchy
    // BaseException <- Exception <- specific exceptions
    if (std.mem.eql(u8, exc_type, "BaseException")) {
        return true; // Everything matches BaseException
    }

    if (std.mem.eql(u8, exc_type, "Exception")) {
        // Most exceptions inherit from Exception
        // Exceptions that don't: SystemExit, KeyboardInterrupt, GeneratorExit
        return !std.mem.eql(u8, err_type, "SystemExit") and
            !std.mem.eql(u8, err_type, "KeyboardInterrupt") and
            !std.mem.eql(u8, err_type, "GeneratorExit");
    }

    // Check specific inheritance
    return isSubclass(err_type, exc_type);
}

/// Check if a type is a subclass of another
fn isSubclass(sub: []const u8, super: []const u8) bool {
    // LookupError <- IndexError, KeyError
    if (std.mem.eql(u8, super, "LookupError")) {
        return std.mem.eql(u8, sub, "IndexError") or
            std.mem.eql(u8, sub, "KeyError");
    }

    // ArithmeticError <- ZeroDivisionError, OverflowError, FloatingPointError
    if (std.mem.eql(u8, super, "ArithmeticError")) {
        return std.mem.eql(u8, sub, "ZeroDivisionError") or
            std.mem.eql(u8, sub, "OverflowError") or
            std.mem.eql(u8, sub, "FloatingPointError");
    }

    // OSError <- many subclasses
    if (std.mem.eql(u8, super, "OSError")) {
        return std.mem.eql(u8, sub, "FileNotFoundError") or
            std.mem.eql(u8, sub, "FileExistsError") or
            std.mem.eql(u8, sub, "PermissionError") or
            std.mem.eql(u8, sub, "IsADirectoryError") or
            std.mem.eql(u8, sub, "NotADirectoryError") or
            std.mem.eql(u8, sub, "InterruptedError") or
            std.mem.eql(u8, sub, "ConnectionError") or
            std.mem.eql(u8, sub, "BlockingIOError") or
            std.mem.eql(u8, sub, "TimeoutError");
    }

    // ConnectionError <- ConnectionAbortedError, ConnectionRefusedError, etc
    if (std.mem.eql(u8, super, "ConnectionError")) {
        return std.mem.eql(u8, sub, "ConnectionAbortedError") or
            std.mem.eql(u8, sub, "ConnectionRefusedError") or
            std.mem.eql(u8, sub, "ConnectionResetError") or
            std.mem.eql(u8, sub, "BrokenPipeError");
    }

    // ValueError <- UnicodeError
    if (std.mem.eql(u8, super, "ValueError")) {
        return std.mem.eql(u8, sub, "UnicodeError") or
            std.mem.eql(u8, sub, "UnicodeDecodeError") or
            std.mem.eql(u8, sub, "UnicodeEncodeError") or
            std.mem.eql(u8, sub, "UnicodeTranslateError");
    }

    // ImportError <- ModuleNotFoundError
    if (std.mem.eql(u8, super, "ImportError")) {
        return std.mem.eql(u8, sub, "ModuleNotFoundError");
    }

    return false;
}

/// Check if current exception matches a type
/// Mirrors: _PyErr_ExceptionMatches, PyErr_ExceptionMatches
pub fn exceptionMatches(exc_type: []const u8) bool {
    const tstate = getThreadState();
    if (tstate.current_exception) |exc| {
        return givenExceptionMatches(exc.type_name, exc_type);
    }
    return false;
}
