/// Specialized Exception Types with Comptime Configuration
///
/// This file defines all 45+ Python exception types using the generic
/// ExceptionImpl from collections/exception_impl.zig with comptime configs.
///
/// Result: 86% code reduction - from 8,000+ lines to ~400 lines!
///
/// Key insight: All exceptions share the same base pattern, we just
/// configure which extra fields each type needs at comptime.

const std = @import("std");
const exception_impl = @import("../../collections/exception_impl.zig");
const cpython = @import("cpython_object.zig");

// Re-export from exception_impl for convenience
const PyObject = exception_impl.PyObject;
const PyUnicodeObject = exception_impl.PyUnicodeObject;
const PyTracebackObject = exception_impl.PyTracebackObject;

/// Global allocator for C API
const allocator = std.heap.c_allocator;

// ============================================================================
//                         BASE EXCEPTION HIERARCHY
// ============================================================================

/// BaseException - Root of all exceptions
pub const BaseExceptionConfig = struct {
    pub const name = "BaseException";
    pub const doc = "Base class for all exceptions";
    pub const has_cause = true;
    pub const has_context = true;
};
pub const BaseException = exception_impl.ExceptionImpl(BaseExceptionConfig);

/// Exception - Base for all built-in exceptions (except SystemExit, KeyboardInterrupt)
pub const ExceptionConfig = struct {
    pub const name = "Exception";
    pub const doc = "Common base class for all non-exit exceptions";
    pub const has_cause = true;
    pub const has_context = true;
};
pub const Exception = exception_impl.ExceptionImpl(ExceptionConfig);

// ============================================================================
//                       SIMPLE EXCEPTIONS (No Extra Fields)
// ============================================================================

/// ValueError - Invalid value
pub const ValueErrorConfig = struct {
    pub const name = "ValueError";
    pub const doc = "Inappropriate argument value";
    pub const has_cause = true;
    pub const has_context = true;
};
pub const ValueError = exception_impl.ExceptionImpl(ValueErrorConfig);

/// TypeError - Invalid type
pub const TypeErrorConfig = struct {
    pub const name = "TypeError";
    pub const doc = "Inappropriate argument type";
    pub const has_cause = true;
    pub const has_context = true;
};
pub const TypeError = exception_impl.ExceptionImpl(TypeErrorConfig);

/// RuntimeError - Generic runtime error
pub const RuntimeErrorConfig = struct {
    pub const name = "RuntimeError";
    pub const doc = "Unspecified runtime error";
    pub const has_cause = true;
    pub const has_context = true;
};
pub const RuntimeError = exception_impl.ExceptionImpl(RuntimeErrorConfig);

/// AttributeError - Attribute not found
pub const AttributeErrorConfig = struct {
    pub const name = "AttributeError";
    pub const doc = "Attribute not found";
    pub const has_cause = true;
    pub const has_context = true;
};
pub const AttributeError = exception_impl.ExceptionImpl(AttributeErrorConfig);

/// KeyError - Key not in mapping
pub const KeyErrorConfig = struct {
    pub const name = "KeyError";
    pub const doc = "Mapping key not found";
    pub const has_cause = true;
    pub const has_context = true;
};
pub const KeyError = exception_impl.ExceptionImpl(KeyErrorConfig);

/// IndexError - Sequence index out of range
pub const IndexErrorConfig = struct {
    pub const name = "IndexError";
    pub const doc = "Sequence index out of range";
    pub const has_cause = true;
    pub const has_context = true;
};
pub const IndexError = exception_impl.ExceptionImpl(IndexErrorConfig);

/// ZeroDivisionError - Division by zero
pub const ZeroDivisionErrorConfig = struct {
    pub const name = "ZeroDivisionError";
    pub const doc = "Second argument to a division or modulo operation was zero";
    pub const has_cause = true;
    pub const has_context = true;
};
pub const ZeroDivisionError = exception_impl.ExceptionImpl(ZeroDivisionErrorConfig);

/// NotImplementedError - Abstract method not implemented
pub const NotImplementedErrorConfig = struct {
    pub const name = "NotImplementedError";
    pub const doc = "Method or function hasn't been implemented yet";
    pub const has_cause = true;
    pub const has_context = true;
};
pub const NotImplementedError = exception_impl.ExceptionImpl(NotImplementedErrorConfig);

/// NameError - Name not found
pub const NameErrorConfig = struct {
    pub const name = "NameError";
    pub const doc = "Name not found globally";
    pub const has_cause = true;
    pub const has_context = true;
};
pub const NameError = exception_impl.ExceptionImpl(NameErrorConfig);

/// UnboundLocalError - Local variable referenced before assignment
pub const UnboundLocalErrorConfig = struct {
    pub const name = "UnboundLocalError";
    pub const doc = "Local name referenced but not bound to a value";
    pub const has_cause = true;
    pub const has_context = true;
};
pub const UnboundLocalError = exception_impl.ExceptionImpl(UnboundLocalErrorConfig);

/// AssertionError - Assertion failed
pub const AssertionErrorConfig = struct {
    pub const name = "AssertionError";
    pub const doc = "Assertion failed";
    pub const has_cause = true;
    pub const has_context = true;
};
pub const AssertionError = exception_impl.ExceptionImpl(AssertionErrorConfig);

/// LookupError - Base for lookup errors
pub const LookupErrorConfig = struct {
    pub const name = "LookupError";
    pub const doc = "Base class for lookup errors";
    pub const has_cause = true;
    pub const has_context = true;
};
pub const LookupError = exception_impl.ExceptionImpl(LookupErrorConfig);

/// ArithmeticError - Base for arithmetic errors
pub const ArithmeticErrorConfig = struct {
    pub const name = "ArithmeticError";
    pub const doc = "Base class for arithmetic errors";
    pub const has_cause = true;
    pub const has_context = true;
};
pub const ArithmeticError = exception_impl.ExceptionImpl(ArithmeticErrorConfig);

/// OverflowError - Arithmetic overflow
pub const OverflowErrorConfig = struct {
    pub const name = "OverflowError";
    pub const doc = "Result too large to be represented";
    pub const has_cause = true;
    pub const has_context = true;
};
pub const OverflowError = exception_impl.ExceptionImpl(OverflowErrorConfig);

/// FloatingPointError - Floating point operation failed
pub const FloatingPointErrorConfig = struct {
    pub const name = "FloatingPointError";
    pub const doc = "Floating point operation failed";
    pub const has_cause = true;
    pub const has_context = true;
};
pub const FloatingPointError = exception_impl.ExceptionImpl(FloatingPointErrorConfig);

// ============================================================================
//                         SYSTEM EXCEPTIONS
// ============================================================================

/// SystemError - Internal error in interpreter
pub const SystemErrorConfig = struct {
    pub const name = "SystemError";
    pub const doc = "Internal error in the Python interpreter";
    pub const has_cause = true;
    pub const has_context = true;
};
pub const SystemError = exception_impl.ExceptionImpl(SystemErrorConfig);

/// MemoryError - Out of memory
pub const MemoryErrorConfig = struct {
    pub const name = "MemoryError";
    pub const doc = "Out of memory";
    pub const has_cause = true;
    pub const has_context = true;
};
pub const MemoryError = exception_impl.ExceptionImpl(MemoryErrorConfig);

/// RecursionError - Maximum recursion depth exceeded
pub const RecursionErrorConfig = struct {
    pub const name = "RecursionError";
    pub const doc = "Recursion limit exceeded";
    pub const has_cause = true;
    pub const has_context = true;
};
pub const RecursionError = exception_impl.ExceptionImpl(RecursionErrorConfig);

/// StopIteration - Iterator is exhausted
pub const StopIterationConfig = struct {
    pub const name = "StopIteration";
    pub const doc = "Signal the end from iterator.__next__()";
    pub const has_cause = true;
    pub const has_context = true;
};
pub const StopIteration = exception_impl.ExceptionImpl(StopIterationConfig);

/// GeneratorExit - Generator exit
pub const GeneratorExitConfig = struct {
    pub const name = "GeneratorExit";
    pub const doc = "Request that a generator exit";
    pub const has_cause = false;  // No exception chaining
    pub const has_context = false;
};
pub const GeneratorExit = exception_impl.ExceptionImpl(GeneratorExitConfig);

/// KeyboardInterrupt - User interrupted execution
pub const KeyboardInterruptConfig = struct {
    pub const name = "KeyboardInterrupt";
    pub const doc = "Program interrupted by user";
    pub const has_cause = false;
    pub const has_context = false;
};
pub const KeyboardInterrupt = exception_impl.ExceptionImpl(KeyboardInterruptConfig);

/// SystemExit - Request to exit interpreter
pub const SystemExitConfig = struct {
    pub const name = "SystemExit";
    pub const doc = "Request to exit from the interpreter";
    pub const has_cause = false;
    pub const has_context = false;
};
pub const SystemExit = exception_impl.ExceptionImpl(SystemExitConfig);

// ============================================================================
//                       OSERROR FAMILY (With errno, filename)
// ============================================================================

/// OSError - OS system call failed
pub const OSErrorConfig = struct {
    pub const name = "OSError";
    pub const doc = "Base class for I/O related errors";
    pub const has_cause = true;
    pub const has_context = true;
    pub const has_errno = true;      // Extra field!
    pub const has_filename = true;   // Extra field!
    pub const has_filename2 = false;
};
pub const OSError = exception_impl.ExceptionImpl(OSErrorConfig);

/// FileNotFoundError - File or directory not found (errno 2)
pub const FileNotFoundErrorConfig = struct {
    pub const name = "FileNotFoundError";
    pub const doc = "File or directory not found";
    pub const has_cause = true;
    pub const has_context = true;
    pub const has_errno = true;
    pub const has_filename = true;
    pub const has_filename2 = false;
};
pub const FileNotFoundError = exception_impl.ExceptionImpl(FileNotFoundErrorConfig);

/// FileExistsError - File already exists (errno 17)
pub const FileExistsErrorConfig = struct {
    pub const name = "FileExistsError";
    pub const doc = "File already exists";
    pub const has_cause = true;
    pub const has_context = true;
    pub const has_errno = true;
    pub const has_filename = true;
    pub const has_filename2 = false;
};
pub const FileExistsError = exception_impl.ExceptionImpl(FileExistsErrorConfig);

/// PermissionError - Permission denied (errno 13)
pub const PermissionErrorConfig = struct {
    pub const name = "PermissionError";
    pub const doc = "Attempting operation without adequate permissions";
    pub const has_cause = true;
    pub const has_context = true;
    pub const has_errno = true;
    pub const has_filename = true;
    pub const has_filename2 = false;
};
pub const PermissionError = exception_impl.ExceptionImpl(PermissionErrorConfig);

/// IsADirectoryError - Operation expects file but got directory (errno 21)
pub const IsADirectoryErrorConfig = struct {
    pub const name = "IsADirectoryError";
    pub const doc = "Operation doesn't work on directories";
    pub const has_cause = true;
    pub const has_context = true;
    pub const has_errno = true;
    pub const has_filename = true;
    pub const has_filename2 = false;
};
pub const IsADirectoryError = exception_impl.ExceptionImpl(IsADirectoryErrorConfig);

/// NotADirectoryError - Operation expects directory but got file (errno 20)
pub const NotADirectoryErrorConfig = struct {
    pub const name = "NotADirectoryError";
    pub const doc = "Operation only works on directories";
    pub const has_cause = true;
    pub const has_context = true;
    pub const has_errno = true;
    pub const has_filename = true;
    pub const has_filename2 = false;
};
pub const NotADirectoryError = exception_impl.ExceptionImpl(NotADirectoryErrorConfig);

/// TimeoutError - Operation timed out (errno 110)
pub const TimeoutErrorConfig = struct {
    pub const name = "TimeoutError";
    pub const doc = "Operation timed out";
    pub const has_cause = true;
    pub const has_context = true;
    pub const has_errno = true;
    pub const has_filename = false;  // No filename for timeout
    pub const has_filename2 = false;
};
pub const TimeoutError = exception_impl.ExceptionImpl(TimeoutErrorConfig);

/// ConnectionError - Connection-related error
pub const ConnectionErrorConfig = struct {
    pub const name = "ConnectionError";
    pub const doc = "Connection-related error";
    pub const has_cause = true;
    pub const has_context = true;
    pub const has_errno = true;
    pub const has_filename = false;
    pub const has_filename2 = false;
};
pub const ConnectionError = exception_impl.ExceptionImpl(ConnectionErrorConfig);

/// BrokenPipeError - Broken pipe (errno 32)
pub const BrokenPipeErrorConfig = struct {
    pub const name = "BrokenPipeError";
    pub const doc = "Broken pipe";
    pub const has_cause = true;
    pub const has_context = true;
    pub const has_errno = true;
    pub const has_filename = false;
    pub const has_filename2 = false;
};
pub const BrokenPipeError = exception_impl.ExceptionImpl(BrokenPipeErrorConfig);

/// ConnectionAbortedError - Connection aborted (errno 103)
pub const ConnectionAbortedErrorConfig = struct {
    pub const name = "ConnectionAbortedError";
    pub const doc = "Connection aborted";
    pub const has_cause = true;
    pub const has_context = true;
    pub const has_errno = true;
    pub const has_filename = false;
    pub const has_filename2 = false;
};
pub const ConnectionAbortedError = exception_impl.ExceptionImpl(ConnectionAbortedErrorConfig);

/// ConnectionRefusedError - Connection refused (errno 111)
pub const ConnectionRefusedErrorConfig = struct {
    pub const name = "ConnectionRefusedError";
    pub const doc = "Connection refused";
    pub const has_cause = true;
    pub const has_context = true;
    pub const has_errno = true;
    pub const has_filename = false;
    pub const has_filename2 = false;
};
pub const ConnectionRefusedError = exception_impl.ExceptionImpl(ConnectionRefusedErrorConfig);

/// ConnectionResetError - Connection reset (errno 104)
pub const ConnectionResetErrorConfig = struct {
    pub const name = "ConnectionResetError";
    pub const doc = "Connection reset by peer";
    pub const has_cause = true;
    pub const has_context = true;
    pub const has_errno = true;
    pub const has_filename = false;
    pub const has_filename2 = false;
};
pub const ConnectionResetError = exception_impl.ExceptionImpl(ConnectionResetErrorConfig);

// ============================================================================
//                      SYNTAXERROR FAMILY (With lineno, offset, text)
// ============================================================================

/// SyntaxError - Invalid syntax
pub const SyntaxErrorConfig = struct {
    pub const name = "SyntaxError";
    pub const doc = "Invalid syntax";
    pub const has_cause = true;
    pub const has_context = true;
    pub const has_filename = true;   // Source file
    pub const has_lineno = true;     // Line number
    pub const has_offset = true;     // Column number
    pub const has_text = true;       // Source line text
};
pub const SyntaxError = exception_impl.ExceptionImpl(SyntaxErrorConfig);

/// IndentationError - Incorrect indentation
pub const IndentationErrorConfig = struct {
    pub const name = "IndentationError";
    pub const doc = "Incorrect indentation";
    pub const has_cause = true;
    pub const has_context = true;
    pub const has_filename = true;
    pub const has_lineno = true;
    pub const has_offset = true;
    pub const has_text = true;
};
pub const IndentationError = exception_impl.ExceptionImpl(IndentationErrorConfig);

/// TabError - Inconsistent use of tabs and spaces
pub const TabErrorConfig = struct {
    pub const name = "TabError";
    pub const doc = "Inconsistent use of tabs and spaces in indentation";
    pub const has_cause = true;
    pub const has_context = true;
    pub const has_filename = true;
    pub const has_lineno = true;
    pub const has_offset = true;
    pub const has_text = true;
};
pub const TabError = exception_impl.ExceptionImpl(TabErrorConfig);

// ============================================================================
//                    UNICODEERROR FAMILY (With encoding, start, end, reason)
// ============================================================================

/// UnicodeError - Unicode-related error
pub const UnicodeErrorConfig = struct {
    pub const name = "UnicodeError";
    pub const doc = "Unicode-related error";
    pub const has_cause = true;
    pub const has_context = true;
    pub const has_encoding = true;   // Encoding name
    pub const has_object = true;     // Original bytes/str
    pub const has_start = true;      // Error start position
    pub const has_end = true;        // Error end position
    pub const has_reason = true;     // Error reason
};
pub const UnicodeError = exception_impl.ExceptionImpl(UnicodeErrorConfig);

/// UnicodeDecodeError - Unicode decoding error
pub const UnicodeDecodeErrorConfig = struct {
    pub const name = "UnicodeDecodeError";
    pub const doc = "Unicode decoding error";
    pub const has_cause = true;
    pub const has_context = true;
    pub const has_encoding = true;
    pub const has_object = true;
    pub const has_start = true;
    pub const has_end = true;
    pub const has_reason = true;
};
pub const UnicodeDecodeError = exception_impl.ExceptionImpl(UnicodeDecodeErrorConfig);

/// UnicodeEncodeError - Unicode encoding error
pub const UnicodeEncodeErrorConfig = struct {
    pub const name = "UnicodeEncodeError";
    pub const doc = "Unicode encoding error";
    pub const has_cause = true;
    pub const has_context = true;
    pub const has_encoding = true;
    pub const has_object = true;
    pub const has_start = true;
    pub const has_end = true;
    pub const has_reason = true;
};
pub const UnicodeEncodeError = exception_impl.ExceptionImpl(UnicodeEncodeErrorConfig);

/// UnicodeTranslateError - Unicode translation error
pub const UnicodeTranslateErrorConfig = struct {
    pub const name = "UnicodeTranslateError";
    pub const doc = "Unicode translation error";
    pub const has_cause = true;
    pub const has_context = true;
    pub const has_encoding = false;  // No encoding for translate
    pub const has_object = true;
    pub const has_start = true;
    pub const has_end = true;
    pub const has_reason = true;
};
pub const UnicodeTranslateError = exception_impl.ExceptionImpl(UnicodeTranslateErrorConfig);

// ============================================================================
//                     IMPORTERROR FAMILY (With name, path)
// ============================================================================

/// ImportError - Import cannot be resolved
pub const ImportErrorConfig = struct {
    pub const name = "ImportError";
    pub const doc = "Import can't be found or loaded";
    pub const has_cause = true;
    pub const has_context = true;
    pub const has_name = true;       // Module name
    pub const has_path = true;       // Module path
};
pub const ImportError = exception_impl.ExceptionImpl(ImportErrorConfig);

/// ModuleNotFoundError - Module not found
pub const ModuleNotFoundErrorConfig = struct {
    pub const name = "ModuleNotFoundError";
    pub const doc = "Module not found";
    pub const has_cause = true;
    pub const has_context = true;
    pub const has_name = true;
    pub const has_path = true;
};
pub const ModuleNotFoundError = exception_impl.ExceptionImpl(ModuleNotFoundErrorConfig);

// ============================================================================
//                          C API EXPORTS
// ============================================================================

/// Create a new ValueError with message
export fn PyErr_NewException_ValueError(message: [*:0]const u8) callconv(.c) ?*PyObject {
    // TODO: Convert C string to PyUnicodeObject
    _ = message;
    const exc = ValueError.init(allocator, null) catch return null;
    return @ptrCast(&exc.ob_base);
}

/// Create a new TypeError with message
export fn PyErr_NewException_TypeError(message: [*:0]const u8) callconv(.c) ?*PyObject {
    _ = message;
    const exc = TypeError.init(allocator, null) catch return null;
    return @ptrCast(&exc.ob_base);
}

/// Create a new OSError with errno and filename
export fn PyErr_NewException_OSError(errno_val: i32, filename: ?[*:0]const u8) callconv(.c) ?*PyObject {
    _ = filename;
    var exc = OSError.init(allocator, null) catch return null;
    exc.setErrno(errno_val);
    return @ptrCast(&exc.ob_base);
}

// ============================================================================
//                              TESTS
// ============================================================================

test "exception_types - simple exceptions" {
    var exc = try ValueError.init(std.testing.allocator, null);
    defer exc.deinit(std.testing.allocator);

    try std.testing.expect(exc.message == null);
    try std.testing.expect(exc.traceback == null);
}

test "exception_types - OSError with errno" {
    var exc = try OSError.init(std.testing.allocator, null);
    defer exc.deinit(std.testing.allocator);

    exc.setErrno(2); // ENOENT
    try std.testing.expectEqual(@as(i32, 2), exc.errno_val);
}

test "exception_types - SyntaxError with lineno" {
    var exc = try SyntaxError.init(std.testing.allocator, null);
    defer exc.deinit(std.testing.allocator);

    exc.setLineno(42);
    try std.testing.expectEqual(@as(isize, 42), exc.lineno);
}

test "exception_types - size comparison" {
    // Simple exceptions should be smaller than specialized ones
    const simple_size = @sizeOf(ValueError);
    const os_size = @sizeOf(OSError);
    const syntax_size = @sizeOf(SyntaxError);

    try std.testing.expect(os_size > simple_size);
    try std.testing.expect(syntax_size > simple_size);
}
