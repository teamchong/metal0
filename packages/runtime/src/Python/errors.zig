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
const exceptions = @import("../runtime/exceptions.zig");

// ============================================================================
// Thread State Emulation
// ============================================================================

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

// ============================================================================
// Exception Value Type
// ============================================================================

/// Represents a Python exception instance
pub const ExceptionValue = struct {
    /// Exception type name
    type_name: []const u8,

    /// Exception message
    message: []const u8,

    /// Exception args tuple (as strings for simplicity)
    args: []const []const u8 = &[_][]const u8{},

    /// Traceback (as formatted string for now)
    traceback: ?[]const u8 = null,

    /// Exception context (for implicit chaining - "During handling of...")
    context: ?*ExceptionValue = null,

    /// Exception cause (for explicit chaining - "raise X from Y")
    cause: ?*ExceptionValue = null,

    /// Allocator used to create this exception
    allocator: std.mem.Allocator,

    /// Create a new exception value
    pub fn create(allocator: std.mem.Allocator, type_name: []const u8, message: []const u8) !*ExceptionValue {
        const self = try allocator.create(ExceptionValue);
        self.* = .{
            .type_name = try allocator.dupe(u8, type_name),
            .message = try allocator.dupe(u8, message),
            .allocator = allocator,
        };
        return self;
    }

    /// Create from exception type and args
    pub fn createWithArgs(allocator: std.mem.Allocator, type_name: []const u8, args: []const []const u8) !*ExceptionValue {
        const self = try allocator.create(ExceptionValue);
        const args_copy = try allocator.alloc([]const u8, args.len);
        for (args, 0..) |arg, i| {
            args_copy[i] = try allocator.dupe(u8, arg);
        }
        const message = if (args.len > 0) args[0] else "";
        self.* = .{
            .type_name = try allocator.dupe(u8, type_name),
            .message = try allocator.dupe(u8, message),
            .args = args_copy,
            .allocator = allocator,
        };
        return self;
    }

    /// Free exception value memory
    pub fn destroy(self: *ExceptionValue) void {
        self.allocator.free(self.type_name);
        self.allocator.free(self.message);
        for (self.args) |arg| {
            self.allocator.free(arg);
        }
        if (self.args.len > 0) {
            self.allocator.free(self.args);
        }
        if (self.traceback) |tb| {
            self.allocator.free(tb);
        }
        // Note: context and cause are owned elsewhere, don't free
        self.allocator.destroy(self);
    }

    /// Get string representation
    pub fn toString(self: *const ExceptionValue, allocator: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "{s}: {s}", .{ self.type_name, self.message });
    }

    /// Set traceback
    pub fn setTraceback(self: *ExceptionValue, tb: []const u8) !void {
        if (self.traceback) |old_tb| {
            self.allocator.free(old_tb);
        }
        self.traceback = try self.allocator.dupe(u8, tb);
    }

    /// Set exception context (implicit chaining)
    pub fn setContext(self: *ExceptionValue, ctx: ?*ExceptionValue) void {
        self.context = ctx;
    }

    /// Get exception context
    pub fn getContext(self: *const ExceptionValue) ?*ExceptionValue {
        return self.context;
    }

    /// Set exception cause (explicit chaining with "from")
    pub fn setCause(self: *ExceptionValue, c: ?*ExceptionValue) void {
        self.cause = c;
    }

    /// Get exception cause
    pub fn getCause(self: *const ExceptionValue) ?*ExceptionValue {
        return self.cause;
    }

    /// Get traceback
    pub fn getTraceback(self: *const ExceptionValue) ?[]const u8 {
        return self.traceback;
    }
};

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
    const allocator = std.heap.page_allocator;

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
    const tstate = getThreadState();
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

/// Get topmost exception from exc_info stack
/// Mirrors: _PyErr_GetTopmostException
pub fn getTopmostException(tstate: *ThreadState) *ExceptionStackItem {
    var exc_info = tstate.exc_info;
    while (exc_info.exc_value == null and exc_info.previous_item != null) {
        exc_info = exc_info.previous_item.?;
    }
    return exc_info;
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

    const allocator = std.heap.page_allocator;
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

// ============================================================================
// Exception Matching
// ============================================================================

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

// ============================================================================
// Exception Chaining
// ============================================================================

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

// ============================================================================
// Formatted Error Messages
// ============================================================================

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

// ============================================================================
// Convenience Functions
// ============================================================================

/// Set TypeError for bad argument
/// Mirrors: PyErr_BadArgument
pub fn badArgument() void {
    setString("TypeError", "bad argument type for built-in operation");
}

/// Set MemoryError
/// Mirrors: PyErr_NoMemory
pub fn noMemory() void {
    setNone("MemoryError");
}

/// Set error from errno
/// Mirrors: PyErr_SetFromErrno
pub fn setFromErrno(exception_type: []const u8) void {
    const errno_val = std.c.getErrno();
    const message = std.c.strerror(errno_val);
    const msg_slice: []const u8 = std.mem.sliceTo(message, 0);
    format(exception_type, "[Errno {d}] {s}", .{ @intFromEnum(errno_val), msg_slice });
}

/// Set error from errno with filename
/// Mirrors: PyErr_SetFromErrnoWithFilename
pub fn setFromErrnoWithFilename(exception_type: []const u8, filename: []const u8) void {
    const errno_val = std.c.getErrno();
    const message = std.c.strerror(errno_val);
    const msg_slice: []const u8 = std.mem.sliceTo(message, 0);
    format(exception_type, "[Errno {d}] {s}: '{s}'", .{ @intFromEnum(errno_val), msg_slice, filename });
}

/// Set ModuleNotFoundError
/// Mirrors: _PyErr_SetModuleNotFoundError
pub fn setModuleNotFoundError(module_name: []const u8) void {
    format("ModuleNotFoundError", "No module named '{s}'", .{module_name});
}

/// Set ImportError with details
/// Mirrors: PyErr_SetImportError
pub fn setImportError(msg: []const u8, name: ?[]const u8, path: ?[]const u8) void {
    _ = path;
    if (name) |n| {
        format("ImportError", "{s} (name={s})", .{ msg, n });
    } else {
        setString("ImportError", msg);
    }
}

/// Bad internal call error
/// Mirrors: _PyErr_BadInternalCall
pub fn badInternalCall(filename: []const u8, lineno: i32) void {
    format("SystemError", "{s}:{d}: bad argument to internal function", .{ filename, lineno });
}

// ============================================================================
// Syntax Error Handling
// ============================================================================

/// Set syntax error with location info
/// Mirrors: PyErr_SyntaxLocationObject
pub fn syntaxLocation(filename: ?[]const u8, lineno: i32, col_offset: i32) void {
    const fname = filename orelse "<unknown>";
    if (col_offset >= 0) {
        format("SyntaxError", "invalid syntax ({s}, line {d}, column {d})", .{ fname, lineno, col_offset });
    } else {
        format("SyntaxError", "invalid syntax ({s}, line {d})", .{ fname, lineno });
    }
}

/// Raise a SyntaxError with full location
/// Mirrors: _PyErr_RaiseSyntaxError
pub fn raiseSyntaxError(msg: []const u8, filename: ?[]const u8, lineno: i32, col_offset: i32, end_lineno: i32, end_col_offset: i32) void {
    _ = end_lineno;
    _ = end_col_offset;
    const fname = filename orelse "<unknown>";
    format("SyntaxError", "{s} ({s}, line {d}, col {d})", .{ msg, fname, lineno, col_offset });
}

// ============================================================================
// Unraisable Exception Handling
// ============================================================================

/// Write unraisable exception info (for exceptions in __del__, etc.)
/// Mirrors: PyErr_WriteUnraisable
pub fn writeUnraisable(obj_repr: ?[]const u8) void {
    const tstate = getThreadState();
    if (tstate.current_exception) |exc| {
        const stderr = std.io.getStdErr().writer();
        if (obj_repr) |obj| {
            stderr.print("Exception ignored in: {s}\n", .{obj}) catch {};
        }
        if (exc.traceback) |tb| {
            stderr.print("{s}", .{tb}) catch {};
        }
        stderr.print("{s}: {s}\n", .{ exc.type_name, exc.message }) catch {};
    }
    clear();
}

/// Format unraisable exception
/// Mirrors: PyErr_FormatUnraisable
pub fn formatUnraisable(comptime fmt: []const u8, args: anytype) void {
    const obj_repr = std.fmt.bufPrint(&format_buffer, fmt, args) catch &format_buffer;
    writeUnraisable(obj_repr);
}

// ============================================================================
// New Exception Type Creation
// ============================================================================

/// Create a new exception class (returns type name for now)
/// Mirrors: PyErr_NewException
pub fn newException(name: []const u8, base: ?[]const u8, doc: ?[]const u8) []const u8 {
    _ = base;
    _ = doc;
    // In AOT compiled code, exception types are static
    // Just return the name for registration
    return name;
}

/// Create new exception with docstring
/// Mirrors: PyErr_NewExceptionWithDoc
pub fn newExceptionWithDoc(name: []const u8, doc: []const u8, base: ?[]const u8, dict: anytype) []const u8 {
    _ = dict;
    _ = base;
    _ = doc;
    return name;
}

// ============================================================================
// Initialization
// ============================================================================

/// Initialize error handling subsystem
pub fn init() void {
    // Initialize thread state exc_info
    thread_state.exc_info = &root_exc_info;
}

/// Finalize error handling subsystem
pub fn fini() void {
    // Clean up any remaining exceptions
    clear();
}

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
