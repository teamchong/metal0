//! test.test_capi.test_module3 - C API Module Tests Part 3 - Exception Handling
const std = @import("std");

/// Exception type
pub const PyExceptionType = enum {
    BaseException,
    Exception,
    TypeError,
    ValueError,
    KeyError,
    IndexError,
    AttributeError,
    RuntimeError,
    StopIteration,
    OverflowError,
    ZeroDivisionError,
    MemoryError,
    ImportError,
    OSError,
    SystemError,
};

/// Exception instance
pub const PyException = struct {
    type_: PyExceptionType,
    message: []const u8,
    traceback: ?*Traceback = null,
    cause: ?*PyException = null,
    context: ?*PyException = null,

    pub fn init(type_: PyExceptionType, message: []const u8) PyException {
        return .{ .type_ = type_, .message = message };
    }

    pub fn with_cause(self: PyException, cause: *PyException) PyException {
        var copy = self;
        copy.cause = cause;
        return copy;
    }

    pub fn format(self: *const PyException, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{s}: {s}", .{ @tagName(self.type_), self.message });
    }
};

/// Traceback frame
pub const TracebackFrame = struct {
    filename: []const u8,
    lineno: u32,
    name: []const u8,
};

/// Traceback
pub const Traceback = struct {
    frames: std.ArrayList(TracebackFrame),

    pub fn init(allocator: std.mem.Allocator) Traceback {
        return .{ .frames = std.ArrayList(TracebackFrame).init(allocator) };
    }

    pub fn deinit(self: *Traceback) void {
        self.frames.deinit();
    }

    pub fn push(self: *Traceback, filename: []const u8, lineno: u32, name: []const u8) !void {
        try self.frames.append(.{ .filename = filename, .lineno = lineno, .name = name });
    }

    pub fn depth(self: *const Traceback) usize {
        return self.frames.items.len;
    }
};

/// Thread error state
pub const ErrorState = struct {
    current_exception: ?PyException = null,
    exception_stack: std.ArrayList(PyException),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ErrorState {
        return .{
            .exception_stack = std.ArrayList(PyException).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ErrorState) void {
        self.exception_stack.deinit();
    }

    pub fn set_exception(self: *ErrorState, exc: PyException) void {
        self.current_exception = exc;
    }

    pub fn clear(self: *ErrorState) void {
        self.current_exception = null;
    }

    pub fn occurred(self: *const ErrorState) bool {
        return self.current_exception != null;
    }

    pub fn fetch(self: *ErrorState) ?PyException {
        const exc = self.current_exception;
        self.current_exception = null;
        return exc;
    }
};

/// Set an exception
pub fn PyErr_SetString(state: *ErrorState, type_: PyExceptionType, message: []const u8) void {
    state.set_exception(PyException.init(type_, message));
}

/// Clear current exception
pub fn PyErr_Clear(state: *ErrorState) void {
    state.clear();
}

/// Check if exception occurred
pub fn PyErr_Occurred(state: *const ErrorState) bool {
    return state.occurred();
}

/// Fetch and clear exception
pub fn PyErr_Fetch(state: *ErrorState) ?PyException {
    return state.fetch();
}

/// Raise exception from another
pub fn PyErr_SetCause(exc: *PyException, cause: *PyException) void {
    exc.cause = cause;
}

test "PyException creation" {
    const exc = PyException.init(.ValueError, "invalid value");
    try std.testing.expectEqual(PyExceptionType.ValueError, exc.type_);
    try std.testing.expectEqualStrings("invalid value", exc.message);
}

test "PyException format" {
    const allocator = std.testing.allocator;
    const exc = PyException.init(.TypeError, "expected int");
    const formatted = try exc.format(allocator);
    defer allocator.free(formatted);
    try std.testing.expectEqualStrings("TypeError: expected int", formatted);
}

test "Traceback" {
    const allocator = std.testing.allocator;
    var tb = Traceback.init(allocator);
    defer tb.deinit();

    try tb.push("test.py", 10, "foo");
    try tb.push("test.py", 20, "bar");

    try std.testing.expectEqual(@as(usize, 2), tb.depth());
}

test "ErrorState" {
    const allocator = std.testing.allocator;
    var state = ErrorState.init(allocator);
    defer state.deinit();

    try std.testing.expect(!state.occurred());

    PyErr_SetString(&state, .RuntimeError, "something went wrong");
    try std.testing.expect(state.occurred());

    const exc = PyErr_Fetch(&state);
    try std.testing.expect(!state.occurred());
    try std.testing.expectEqual(PyExceptionType.RuntimeError, exc.?.type_);
}

test "exception chaining" {
    var cause = PyException.init(.ValueError, "bad input");
    var exc = PyException.init(.RuntimeError, "processing failed");
    PyErr_SetCause(&exc, &cause);

    try std.testing.expect(exc.cause != null);
    try std.testing.expectEqual(PyExceptionType.ValueError, exc.cause.?.type_);
}
