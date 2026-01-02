/// Python exception types
const std = @import("std");
const PyValue = @import("../Objects/object.zig").PyValue;

/// Python exception types mapped to Zig errors
pub const PythonError = error{
    ZeroDivisionError,
    IndexError,
    ValueError,
    TypeError,
    KeyError,
    OverflowError,
    OutOfMemory, // Python's MemoryError
    Exception, // Generic exception catch-all
};

/// Thread-local storage for the last exception message
/// This allows us to preserve Python exception messages through Zig's error system
threadlocal var last_exception_message: ?[]const u8 = null;
threadlocal var last_exception_type: ?[]const u8 = null;

/// Thread-local storage for exception args (for cm.exception.args[0] access)
threadlocal var last_exception_args: [8][]const u8 = .{""} ** 8;
threadlocal var last_exception_args_len: usize = 0;

/// Thread-local storage for SyntaxError attributes
threadlocal var last_syntax_error_filename: ?[]const u8 = null;
threadlocal var last_syntax_error_lineno: ?i64 = null;
threadlocal var last_syntax_error_offset: ?i64 = null;
threadlocal var last_syntax_error_text: ?[]const u8 = null;
threadlocal var last_syntax_error_end_lineno: ?i64 = null;
threadlocal var last_syntax_error_end_offset: ?i64 = null;

/// Thread-local buffer for formatted exception messages (e.g., with repr values)
threadlocal var exception_message_buffer: [512]u8 = undefined;

/// Unraisable exception info - used by sys.unraisablehook
/// This is for exceptions that occur in contexts where they can't be propagated
/// (e.g., in __del__ methods, during garbage collection, etc.)
pub const UnraisableInfo = struct {
    exc_type: []const u8 = "Exception",
    exc_value: ?[]const u8 = null,
    err_msg: ?[]const u8 = null,
    object: ?*anyopaque = null,
};

/// Thread-local hook for capturing unraisable exceptions
/// When set, exceptions that would normally be "unraisable" (from __del__, etc.)
/// are passed to this hook instead of being silently discarded
threadlocal var unraisable_hook: ?*const fn (info: UnraisableInfo) void = null;

/// Set the unraisable hook (used by catch_unraisable_exception context manager)
pub fn setUnraisableHook(hook: ?*const fn (info: UnraisableInfo) void) void {
    unraisable_hook = hook;
}

/// Get the current unraisable hook
pub fn getUnraisableHook() ?*const fn (info: UnraisableInfo) void {
    return unraisable_hook;
}

/// Call the unraisable hook if set, otherwise print to stderr
/// This should be called when an exception occurs in a context where it can't propagate
pub fn callUnraisableHook(exc_type: []const u8, exc_value: ?[]const u8) void {
    const info = UnraisableInfo{
        .exc_type = exc_type,
        .exc_value = exc_value,
    };
    if (unraisable_hook) |hook| {
        hook(info);
    } else {
        // Default behavior: print to stderr (Python's default)
        std.debug.print("Exception ignored in: <unknown>\n", .{});
        if (exc_value) |val| {
            std.debug.print("{s}: {s}\n", .{ exc_type, val });
        } else {
            std.debug.print("{s}\n", .{exc_type});
        }
    }
}

// ============================================================================
// Exception Stack - for tracking active exceptions (bare raise re-raise)
// ============================================================================

/// Maximum depth of nested exception handlers
const MAX_EXCEPTION_DEPTH = 8;

/// Thread-local counter for generating unique exception IDs
/// Used for Python identity comparison (assertIs) across re-raises
threadlocal var next_exception_id: u64 = 1;

/// Entry in the exception stack
pub const ExceptionStackEntry = struct {
    type_name: []const u8,
    message: []const u8,
    exception_id: u64 = 0,
};

/// Thread-local exception stack for tracking active exceptions
/// Used by bare `raise` to know what exception to re-raise
threadlocal var exception_stack: [MAX_EXCEPTION_DEPTH]ExceptionStackEntry = undefined;
threadlocal var exception_stack_len: usize = 0;

/// Push an exception onto the stack (called when entering an except handler)
/// Assigns a unique exception ID for identity tracking
pub fn pushException(type_name: []const u8, message: []const u8) void {
    const id = next_exception_id;
    next_exception_id += 1;
    if (exception_stack_len < MAX_EXCEPTION_DEPTH) {
        exception_stack[exception_stack_len] = .{ .type_name = type_name, .message = message, .exception_id = id };
        exception_stack_len += 1;
    }
}

/// Push an exception with a specific ID (for re-raises that preserve identity)
pub fn pushExceptionWithId(type_name: []const u8, message: []const u8, id: u64) void {
    if (exception_stack_len < MAX_EXCEPTION_DEPTH) {
        exception_stack[exception_stack_len] = .{ .type_name = type_name, .message = message, .exception_id = id };
        exception_stack_len += 1;
    }
}

/// Get the exception ID of the current exception (for assertIs comparison)
pub fn getCurrentExceptionId() u64 {
    if (exception_stack_len > 0) {
        return exception_stack[exception_stack_len - 1].exception_id;
    }
    return 0;
}

/// Pop an exception from the stack (called when exiting an except handler)
pub fn popException() void {
    if (exception_stack_len > 0) {
        exception_stack_len -= 1;
    }
}

/// Get the currently active exception (for bare raise)
/// Returns null if no exception is active (raise outside except handler)
pub fn getCurrentException() ?ExceptionStackEntry {
    if (exception_stack_len > 0) {
        return exception_stack[exception_stack_len - 1];
    }
    return null;
}

/// Check if we're inside an exception handler
pub fn hasActiveException() bool {
    return exception_stack_len > 0;
}

// ============================================================================
// Exception Cause Tracking (for `raise X from Y` syntax)
// ============================================================================

/// Thread-local storage for exception cause data (set by `raise X from Y`)
/// We store the data, not a pointer, to avoid stack lifetime issues
threadlocal var pending_cause_type_name: []const u8 = "";
threadlocal var pending_cause_message: []const u8 = "";
threadlocal var pending_cause_id: u64 = 0;
threadlocal var pending_has_cause: bool = false;

/// Thread-local storage for __suppress_context__ (set by `raise X from Y` or `raise X from None`)
/// When true, __context__ won't be displayed even if set
threadlocal var pending_suppress_context: bool = false;

/// Thread-local for tracking if cause was explicitly set to None
/// `raise X from None` is different from just `raise X`
threadlocal var pending_cause_is_none: bool = false;

/// Set the exception cause for the next raised exception (from PyException pointer)
/// Called during `raise X from Y` processing
pub fn setExceptionCause(cause: ?*PyException) void {
    if (cause) |c| {
        pending_cause_type_name = c.type_name;
        pending_cause_message = c.message;
        pending_cause_id = c.exception_id;
        pending_has_cause = true;
    } else {
        pending_has_cause = false;
    }
    pending_suppress_context = true; // `raise X from Y` always sets __suppress_context__ = True
    pending_cause_is_none = cause == null;
}

/// Set the exception cause from type name and message directly
/// Used when we don't have a full PyException object
pub fn setExceptionCauseFromData(type_name: []const u8, message: []const u8, exc_id: u64) void {
    pending_cause_type_name = type_name;
    pending_cause_message = message;
    pending_cause_id = exc_id;
    pending_has_cause = true;
    pending_suppress_context = true;
    pending_cause_is_none = false;
}

/// Check if there's a pending cause
pub fn hasPendingCause() bool {
    return pending_has_cause;
}

/// Get the pending cause type name
pub fn getPendingCauseTypeName() []const u8 {
    return pending_cause_type_name;
}

/// Get the pending cause message
pub fn getPendingCauseMessage() []const u8 {
    return pending_cause_message;
}

/// Get the pending cause exception ID
pub fn getPendingCauseId() u64 {
    return pending_cause_id;
}

/// Get the pending suppress_context flag (and clear it)
pub fn consumeSuppressContext() bool {
    const suppress = pending_suppress_context;
    pending_suppress_context = false;
    pending_cause_is_none = false;
    return suppress;
}

/// Check if `raise X from None` was used (for tests)
pub fn wasCauseExplicitlyNone() bool {
    return pending_cause_is_none;
}

/// Clear all pending cause state
pub fn clearPendingCause() void {
    pending_cause_type_name = "";
    pending_cause_message = "";
    pending_cause_id = 0;
    pending_has_cause = false;
    pending_suppress_context = false;
    pending_cause_is_none = false;
}

/// Map exception type name to Zig error type for bare raise re-raising
/// This allows the correct error to propagate through catch blocks
pub fn getErrorFromTypeName(type_name: []const u8) anyerror {
    // Common exceptions (ordered by frequency)
    if (std.mem.eql(u8, type_name, "TypeError")) return error.TypeError;
    if (std.mem.eql(u8, type_name, "ValueError")) return error.ValueError;
    if (std.mem.eql(u8, type_name, "KeyError")) return error.KeyError;
    if (std.mem.eql(u8, type_name, "IndexError")) return error.IndexError;
    if (std.mem.eql(u8, type_name, "AttributeError")) return error.AttributeError;
    if (std.mem.eql(u8, type_name, "RuntimeError")) return error.RuntimeError;
    if (std.mem.eql(u8, type_name, "NameError")) return error.NameError;
    if (std.mem.eql(u8, type_name, "ZeroDivisionError")) return error.ZeroDivisionError;
    if (std.mem.eql(u8, type_name, "OverflowError")) return error.OverflowError;
    if (std.mem.eql(u8, type_name, "StopIteration")) return error.StopIteration;
    if (std.mem.eql(u8, type_name, "AssertionError")) return error.AssertionError;
    if (std.mem.eql(u8, type_name, "ImportError")) return error.ImportError;
    if (std.mem.eql(u8, type_name, "ModuleNotFoundError")) return error.ModuleNotFoundError;
    if (std.mem.eql(u8, type_name, "OSError")) return error.OSError;
    if (std.mem.eql(u8, type_name, "IOError")) return error.IOError;
    if (std.mem.eql(u8, type_name, "FileNotFoundError")) return error.FileNotFoundError;
    if (std.mem.eql(u8, type_name, "PermissionError")) return error.PermissionError;
    if (std.mem.eql(u8, type_name, "NotImplementedError")) return error.NotImplementedError;
    if (std.mem.eql(u8, type_name, "LookupError")) return error.LookupError;
    if (std.mem.eql(u8, type_name, "UnicodeError")) return error.UnicodeError;
    if (std.mem.eql(u8, type_name, "UnicodeDecodeError")) return error.UnicodeDecodeError;
    if (std.mem.eql(u8, type_name, "UnicodeEncodeError")) return error.UnicodeEncodeError;
    if (std.mem.eql(u8, type_name, "SystemError")) return error.SystemError;
    if (std.mem.eql(u8, type_name, "RecursionError")) return error.RecursionError;
    if (std.mem.eql(u8, type_name, "MemoryError")) return error.MemoryError;
    if (std.mem.eql(u8, type_name, "BufferError")) return error.BufferError;
    if (std.mem.eql(u8, type_name, "ConnectionError")) return error.ConnectionError;
    if (std.mem.eql(u8, type_name, "TimeoutError")) return error.TimeoutError;
    if (std.mem.eql(u8, type_name, "ArithmeticError")) return error.ArithmeticError;
    if (std.mem.eql(u8, type_name, "EOFError")) return error.EOFError;
    if (std.mem.eql(u8, type_name, "GeneratorExit")) return error.GeneratorExit;
    if (std.mem.eql(u8, type_name, "SystemExit")) return error.SystemExit;
    if (std.mem.eql(u8, type_name, "KeyboardInterrupt")) return error.KeyboardInterrupt;
    if (std.mem.eql(u8, type_name, "SyntaxError")) return error.SyntaxError;
    if (std.mem.eql(u8, type_name, "IndentationError")) return error.IndentationError;
    if (std.mem.eql(u8, type_name, "TabError")) return error.TabError;
    if (std.mem.eql(u8, type_name, "UnboundLocalError")) return error.UnboundLocalError;
    if (std.mem.eql(u8, type_name, "FloatingPointError")) return error.FloatingPointError;
    if (std.mem.eql(u8, type_name, "FileExistsError")) return error.FileExistsError;
    if (std.mem.eql(u8, type_name, "IsADirectoryError")) return error.IsADirectoryError;
    if (std.mem.eql(u8, type_name, "NotADirectoryError")) return error.NotADirectoryError;
    if (std.mem.eql(u8, type_name, "BrokenPipeError")) return error.BrokenPipeError;
    if (std.mem.eql(u8, type_name, "ConnectionAbortedError")) return error.ConnectionAbortedError;
    if (std.mem.eql(u8, type_name, "ConnectionRefusedError")) return error.ConnectionRefusedError;
    if (std.mem.eql(u8, type_name, "ConnectionResetError")) return error.ConnectionResetError;
    if (std.mem.eql(u8, type_name, "BaseException")) return error.BaseException;
    // Default fallback for unknown or custom exceptions
    return error.Exception;
}

// ============================================================================
// Exception Message Storage
// ============================================================================

/// Set the last exception message (call before returning an error)
pub fn setExceptionMessage(msg: []const u8) void {
    last_exception_message = msg;
}

/// Set the last exception type name
pub fn setExceptionType(type_name: []const u8) void {
    last_exception_type = type_name;
}

/// Set both exception type and message
pub fn setException(type_name: []const u8, msg: []const u8) void {
    last_exception_type = type_name;
    last_exception_message = msg;
    // Store message as first arg (Python exception args[0] is typically the message)
    last_exception_args[0] = msg;
    last_exception_args_len = if (msg.len > 0) 1 else 0;
}

/// Get exception args slice
pub fn getExceptionArgs() []const []const u8 {
    return last_exception_args[0..last_exception_args_len];
}

/// Set multiple exception args
pub fn setExceptionArgs(args: []const []const u8) void {
    const copy_len = @min(args.len, last_exception_args.len);
    for (0..copy_len) |i| {
        last_exception_args[i] = args[i];
    }
    last_exception_args_len = copy_len;
}

/// Get the last exception message (returns empty string if none)
pub fn getExceptionMessage() []const u8 {
    return last_exception_message orelse "";
}

/// Get the last exception type name (returns "Exception" if none)
pub fn getExceptionType() []const u8 {
    return last_exception_type orelse "Exception";
}

/// Get formatted exception string like Python's str(e)
pub fn getExceptionStr() []const u8 {
    return last_exception_message orelse "";
}

/// Clear the last exception (call after handling)
pub fn clearException() void {
    last_exception_message = null;
    last_exception_type = null;
    last_exception_full = null;
    last_exception_args_len = 0;
    // Clear SyntaxError attributes
    last_syntax_error_filename = null;
    last_syntax_error_lineno = null;
    last_syntax_error_offset = null;
    last_syntax_error_text = null;
    last_syntax_error_end_lineno = null;
    last_syntax_error_end_offset = null;
    // Clear pending cause state
    clearPendingCause();
}

/// Set SyntaxError attributes
pub fn setSyntaxError(
    message: []const u8,
    filename: ?[]const u8,
    lineno: ?i64,
    offset: ?i64,
    text: ?[]const u8,
) void {
    setException("SyntaxError", message);
    last_syntax_error_filename = filename;
    last_syntax_error_lineno = lineno;
    last_syntax_error_offset = offset;
    last_syntax_error_text = text;
}

/// Get SyntaxError filename
pub fn getSyntaxErrorFilename() ?[]const u8 {
    return last_syntax_error_filename;
}

/// Get SyntaxError lineno
pub fn getSyntaxErrorLineno() ?i64 {
    return last_syntax_error_lineno;
}

/// Get SyntaxError offset
pub fn getSyntaxErrorOffset() ?i64 {
    return last_syntax_error_offset;
}

/// Get SyntaxError text
pub fn getSyntaxErrorText() ?[]const u8 {
    return last_syntax_error_text;
}

/// Python traceback object - represents a stack frame in the exception traceback
pub const PyTraceback = struct {
    tb_filename: []const u8,
    tb_lineno: u32,
    tb_name: []const u8,
    tb_next: ?*PyTraceback = null,

    pub fn init(allocator: std.mem.Allocator, filename: []const u8, lineno: u32, name: []const u8) !*PyTraceback {
        const self = try allocator.create(PyTraceback);
        self.* = .{
            .tb_filename = filename,
            .tb_lineno = lineno,
            .tb_name = name,
            .tb_next = null,
        };
        return self;
    }
};

/// Python exception object - provides full Python exception semantics
/// This is used for `except X as e:` where `e` needs __traceback__, __context__, etc.
pub const PyException = struct {
    /// The exception type name (e.g., "ValueError", "TypeError")
    type_name: []const u8,
    /// The exception message (equivalent to str(e))
    message: []const u8,
    /// The exception arguments (e.args in Python)
    args: []const PyValue = &[_]PyValue{},
    /// The traceback object (__traceback__ in Python)
    __traceback__: ?*PyTraceback = null,
    /// The exception that was being handled when this was raised (__context__ in Python)
    __context__: ?*PyException = null,
    /// The explicit cause of this exception (__cause__ in Python, from `raise X from Y`)
    __cause__: ?*PyException = null,
    /// Whether __context__ should be suppressed when displaying (__suppress_context__ in Python)
    __suppress_context__: bool = false,
    /// Unique ID for identity comparison (assertIs) - same ID = same exception object
    exception_id: u64 = 0,

    const Self = @This();

    /// Initialize an empty exception with just type and message
    pub fn init(type_name: []const u8, message: []const u8) Self {
        return .{
            .type_name = type_name,
            .message = message,
            .exception_id = getCurrentExceptionId(),
        };
    }

    /// Initialize with a specific exception ID (for re-raises)
    pub fn initWithId(type_name: []const u8, message: []const u8, id: u64) Self {
        return .{
            .type_name = type_name,
            .message = message,
            .exception_id = id,
        };
    }

    /// Initialize from current thread-local exception state
    pub fn fromCurrent() Self {
        return .{
            .type_name = last_exception_type orelse "Exception",
            .message = last_exception_message orelse "",
            .exception_id = getCurrentExceptionId(),
        };
    }

    /// Get string representation (equivalent to str(e) in Python)
    pub fn __str__(self: *const Self) []const u8 {
        return self.message;
    }

    /// Get repr representation (equivalent to repr(e) in Python)
    pub fn __repr__(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
        if (self.message.len == 0) {
            return try std.fmt.allocPrint(allocator, "{s}()", .{self.type_name});
        } else {
            return try std.fmt.allocPrint(allocator, "{s}('{s}')", .{ self.type_name, self.message });
        }
    }

    /// Convert to PyValue (stores as string message for compatibility)
    /// Used when exception is assigned to a variable that expects PyValue
    pub fn toPyValue(self: Self) PyValue {
        return .{ .string = self.message };
    }

    /// Convert to PyValue with full type info (stores as ptr)
    /// Use this when full exception info needs to be preserved
    pub fn toPyValueFull(self: *Self) PyValue {
        return .{ .ptr = @ptrCast(self) };
    }
};

/// Thread-local storage for the full exception object
threadlocal var last_exception_full: ?PyException = null;

/// Set the full exception object
pub fn setExceptionFull(exc: PyException) void {
    last_exception_full = exc;
    last_exception_type = exc.type_name;
    last_exception_message = exc.message;
}

/// Thread-local storage for the cause PyException (so we can return a pointer)
/// Use direct struct initialization to avoid calling runtime functions at comptime
threadlocal var cause_exception_storage: PyException = .{
    .type_name = "",
    .message = "",
};

/// Get the full exception object (returns default if none set)
/// Also applies pending __cause__ and __suppress_context__ from `raise X from Y`
pub fn getExceptionFull() PyException {
    var exc = last_exception_full orelse PyException.fromCurrent();
    // Apply pending cause from `raise X from Y`
    if (pending_suppress_context) {
        exc.__suppress_context__ = true;
        if (pending_has_cause) {
            // Create the cause exception in thread-local storage
            cause_exception_storage = PyException.initWithId(
                pending_cause_type_name,
                pending_cause_message,
                pending_cause_id,
            );
            exc.__cause__ = &cause_exception_storage;
        } else {
            exc.__cause__ = null;
        }
        // Clear pending state
        clearPendingCause();
    }
    return exc;
}

/// Set exception message with bytes repr formatted into the message
/// Format: "could not convert string to float: b'...'"
pub fn setFloatConversionError(bytes_data: []const u8) void {
    var stream = std.io.fixedBufferStream(&exception_message_buffer);
    const writer = stream.writer();

    writer.writeAll("could not convert string to float: b'") catch return;

    // Write bytes repr (escape non-printable chars)
    for (bytes_data) |byte| {
        if (byte >= 0x20 and byte < 0x7f and byte != '\'' and byte != '\\') {
            writer.writeByte(byte) catch return;
        } else {
            // Use \xNN format for non-printable bytes
            writer.print("\\x{x:0>2}", .{byte}) catch return;
        }
    }

    writer.writeAll("'") catch return;

    last_exception_message = exception_message_buffer[0..stream.pos];
}

/// Set exception message with string repr formatted into the message
/// Format: "could not convert string to float: '...'"
pub fn setFloatConversionErrorStr(str_data: []const u8) void {
    var stream = std.io.fixedBufferStream(&exception_message_buffer);
    const writer = stream.writer();

    writer.writeAll("could not convert string to float: '") catch return;

    // Write string repr (escape non-printable chars)
    for (str_data) |byte| {
        if (byte >= 0x20 and byte < 0x7f and byte != '\'' and byte != '\\') {
            writer.writeByte(byte) catch return;
        } else if (byte == '\\') {
            writer.writeAll("\\\\") catch return;
        } else if (byte == '\'') {
            writer.writeAll("\\'") catch return;
        } else if (byte == '\n') {
            writer.writeAll("\\n") catch return;
        } else if (byte == '\r') {
            writer.writeAll("\\r") catch return;
        } else if (byte == '\t') {
            writer.writeAll("\\t") catch return;
        } else {
            // Use \xNN format for non-printable bytes
            writer.print("\\x{x:0>2}", .{byte}) catch return;
        }
    }

    writer.writeAll("'") catch return;

    last_exception_message = exception_message_buffer[0..stream.pos];
}

/// Python exception type enum - integer values that can be stored in lists/tuples
/// Used when Python code stores exception types as values: [("x", ValueError), ("y", 1)]
pub const ExceptionTypeId = enum(i64) {
    TypeError = -1000001,
    ValueError = -1000002,
    KeyError = -1000003,
    IndexError = -1000004,
    ZeroDivisionError = -1000005,
    AttributeError = -1000006,
    NameError = -1000007,
    FileNotFoundError = -1000008,
    IOError = -1000009,
    RuntimeError = -1000010,
    StopIteration = -1000011,
    NotImplementedError = -1000012,
    AssertionError = -1000013,
    OverflowError = -1000014,
    ImportError = -1000015,
    ModuleNotFoundError = -1000016,
    OSError = -1000017,
    PermissionError = -1000018,
    TimeoutError = -1000019,
    ConnectionError = -1000020,
    RecursionError = -1000021,
    MemoryError = -1000022,
    LookupError = -1000023,
    ArithmeticError = -1000024,
    UnicodeError = -1000025,
    UnicodeDecodeError = -1000026,
    UnicodeEncodeError = -1000027,
    BlockingIOError = -1000028,
    Exception = -1000029,
    BaseException = -1000030,
    ExceptionGroup = -1000031,
    BaseExceptionGroup = -1000032,
    _,

    /// Check if an i64 value represents an exception type
    pub fn isExceptionType(value: i64) bool {
        return value <= -1000001 and value >= -1000032;
    }
};

/// Helper to create an exception struct with proper init methods
fn ExceptionClass(comptime exception_name: []const u8) type {
    return struct {
        pub const name = exception_name;
        args: []const PyValue = &[_]PyValue{},
        allocator: std.mem.Allocator = undefined,

        // PyException-compatible interface for `raise X from cause`
        // These are instance fields with default values (accessed via pointer)
        type_name: []const u8 = exception_name,
        message: []const u8 = "",
        exception_id: u64 = 0,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) !*Self {
            const self = try allocator.create(Self);
            self.* = .{
                .args = &[_]PyValue{},
                .allocator = allocator,
                .type_name = exception_name,
                .message = "",
                .exception_id = 0,
            };
            return self;
        }

        pub fn initWithArg(allocator: std.mem.Allocator, arg: anytype) !*Self {
            const self = try allocator.create(Self);
            const args_copy = try allocator.alloc(PyValue, 1);
            args_copy[0] = try PyValue.fromAlloc(allocator, arg);
            self.* = .{
                .args = args_copy,
                .allocator = allocator,
            };
            return self;
        }

        pub fn initWithArgs(allocator: std.mem.Allocator, args: []const PyValue) !*Self {
            const self = try allocator.create(Self);
            const args_copy = try allocator.alloc(PyValue, args.len);
            @memcpy(args_copy, args);
            self.* = .{
                .args = args_copy,
                .allocator = allocator,
            };
            return self;
        }

        pub fn __str__(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
            if (self.args.len == 0) {
                return "";
            } else if (self.args.len == 1) {
                return try self.args[0].toString(allocator);
            } else {
                var result: std.ArrayList(u8) = .{};
                try result.appendSlice(allocator, "(");
                for (self.args, 0..) |arg, i| {
                    if (i > 0) try result.appendSlice(allocator, ", ");
                    const s = try arg.toRepr(allocator);
                    try result.appendSlice(allocator, s);
                }
                try result.appendSlice(allocator, ")");
                return result.toOwnedSlice(allocator);
            }
        }

        pub fn __repr__(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
            var result: std.ArrayList(u8) = .{};
            try result.appendSlice(allocator, name);
            try result.appendSlice(allocator, "(");
            for (self.args, 0..) |arg, i| {
                if (i > 0) try result.appendSlice(allocator, ", ");
                const s = try arg.toRepr(allocator);
                try result.appendSlice(allocator, s);
            }
            try result.appendSlice(allocator, ")");
            return result.toOwnedSlice(allocator);
        }
    };
}

/// Python exception types - all with proper init, __str__, __repr__ methods
pub const TypeError = ExceptionClass("TypeError");
pub const ValueError = ExceptionClass("ValueError");
pub const KeyError = ExceptionClass("KeyError");
pub const IndexError = ExceptionClass("IndexError");
pub const ZeroDivisionError = ExceptionClass("ZeroDivisionError");
pub const AttributeError = ExceptionClass("AttributeError");
pub const NameError = ExceptionClass("NameError");
pub const FileNotFoundError = ExceptionClass("FileNotFoundError");
pub const IOError = ExceptionClass("IOError");
pub const RuntimeError = ExceptionClass("RuntimeError");
pub const StopIteration = ExceptionClass("StopIteration");
pub const NotImplementedError = ExceptionClass("NotImplementedError");
pub const AssertionError = ExceptionClass("AssertionError");
pub const OverflowError = ExceptionClass("OverflowError");
pub const ImportError = ExceptionClass("ImportError");
pub const ModuleNotFoundError = ExceptionClass("ModuleNotFoundError");
pub const OSError = ExceptionClass("OSError");
pub const PermissionError = ExceptionClass("PermissionError");
pub const TimeoutError = ExceptionClass("TimeoutError");
pub const ConnectionError = ExceptionClass("ConnectionError");
pub const RecursionError = ExceptionClass("RecursionError");
pub const MemoryError = ExceptionClass("MemoryError");
pub const LookupError = ExceptionClass("LookupError");
pub const ArithmeticError = ExceptionClass("ArithmeticError");
pub const BufferError = ExceptionClass("BufferError");
pub const EOFError = ExceptionClass("EOFError");
pub const GeneratorExit = ExceptionClass("GeneratorExit");
pub const SystemExit = ExceptionClass("SystemExit");
pub const KeyboardInterrupt = ExceptionClass("KeyboardInterrupt");
/// BaseException - the base class for all built-in exceptions
pub const BaseException = struct {
    pub const name = "BaseException";
    args: []const PyValue,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !*BaseException {
        const self = try allocator.create(BaseException);
        self.* = .{
            .args = &[_]PyValue{},
            .allocator = allocator,
        };
        return self;
    }

    pub fn initWithArgs(allocator: std.mem.Allocator, args: []const PyValue) !*BaseException {
        const self = try allocator.create(BaseException);
        // Copy args
        const args_copy = try allocator.alloc(PyValue, args.len);
        @memcpy(args_copy, args);
        self.* = .{
            .args = args_copy,
            .allocator = allocator,
        };
        return self;
    }

    pub fn initWithArg(allocator: std.mem.Allocator, arg: anytype) !*BaseException {
        const self = try allocator.create(BaseException);
        const args_copy = try allocator.alloc(PyValue, 1);
        args_copy[0] = try PyValue.fromAlloc(allocator, arg);
        self.* = .{
            .args = args_copy,
            .allocator = allocator,
        };
        return self;
    }

    pub fn __str__(self: *const BaseException, allocator: std.mem.Allocator) ![]const u8 {
        if (self.args.len == 0) {
            return "";
        } else if (self.args.len == 1) {
            return try self.args[0].toString(allocator);
        } else {
            // Format as tuple
            var result: std.ArrayList(u8) = .{};
            try result.appendSlice(allocator, "(");
            for (self.args, 0..) |arg, i| {
                if (i > 0) try result.appendSlice(allocator, ", ");
                const s = try arg.toRepr(allocator);
                try result.appendSlice(allocator, s);
            }
            try result.appendSlice(allocator, ")");
            return result.toOwnedSlice(allocator);
        }
    }

    pub fn __repr__(self: *const BaseException, allocator: std.mem.Allocator) ![]const u8 {
        var result: std.ArrayList(u8) = .{};
        try result.appendSlice(allocator, name);
        try result.appendSlice(allocator, "(");
        for (self.args, 0..) |arg, i| {
            if (i > 0) try result.appendSlice(allocator, ", ");
            const s = try arg.toRepr(allocator);
            try result.appendSlice(allocator, s);
        }
        try result.appendSlice(allocator, ")");
        return result.toOwnedSlice(allocator);
    }
};

/// Exception - the common base class for all non-exit exceptions
pub const Exception = struct {
    pub const name = "Exception";
    args: []const PyValue,
    allocator: std.mem.Allocator,
    // Note: Removed __class__: type = Exception as it was comptime-only and blocked runtime usage.
    // Use Exception.name for type identification at runtime.

    pub fn init(allocator: std.mem.Allocator) !*Exception {
        const self = try allocator.create(Exception);
        self.* = .{
            .args = &[_]PyValue{},
            .allocator = allocator,
        };
        return self;
    }

    pub fn initWithArgs(allocator: std.mem.Allocator, args: []const PyValue) !*Exception {
        const self = try allocator.create(Exception);
        // Copy args
        const args_copy = try allocator.alloc(PyValue, args.len);
        @memcpy(args_copy, args);
        self.* = .{
            .args = args_copy,
            .allocator = allocator,
        };
        return self;
    }

    pub fn initWithArg(allocator: std.mem.Allocator, arg: anytype) !*Exception {
        const self = try allocator.create(Exception);
        const args_copy = try allocator.alloc(PyValue, 1);
        args_copy[0] = try PyValue.fromAlloc(allocator, arg);
        self.* = .{
            .args = args_copy,
            .allocator = allocator,
        };
        return self;
    }

    pub fn __str__(self: *const Exception, allocator: std.mem.Allocator) ![]const u8 {
        if (self.args.len == 0) {
            return "";
        } else if (self.args.len == 1) {
            return try self.args[0].toString(allocator);
        } else {
            // Format as tuple
            var result: std.ArrayList(u8) = .{};
            try result.appendSlice(allocator, "(");
            for (self.args, 0..) |arg, i| {
                if (i > 0) try result.appendSlice(allocator, ", ");
                const s = try arg.toRepr(allocator);
                try result.appendSlice(allocator, s);
            }
            try result.appendSlice(allocator, ")");
            return result.toOwnedSlice(allocator);
        }
    }

    pub fn __repr__(self: *const Exception, allocator: std.mem.Allocator) ![]const u8 {
        var result: std.ArrayList(u8) = .{};
        try result.appendSlice(allocator, name);
        try result.appendSlice(allocator, "(");
        for (self.args, 0..) |arg, i| {
            if (i > 0) try result.appendSlice(allocator, ", ");
            const s = try arg.toRepr(allocator);
            try result.appendSlice(allocator, s);
        }
        try result.appendSlice(allocator, ")");
        return result.toOwnedSlice(allocator);
    }
};
pub const SyntaxError = struct {
    pub const name = "SyntaxError";
};
pub const UnicodeError = struct {
    pub const name = "UnicodeError";
};
pub const UnicodeDecodeError = struct {
    pub const name = "UnicodeDecodeError";
};
pub const UnicodeEncodeError = struct {
    pub const name = "UnicodeEncodeError";
};

/// BaseExceptionGroup - groups multiple exceptions together (Python 3.11+)
/// Can contain any BaseException subclasses
pub const BaseExceptionGroup = struct {
    pub const __name__ = "BaseExceptionGroup";
    pub const name = "BaseExceptionGroup";
    message: []const u8,
    exceptions: []const PyValue,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, message: anytype, exceptions: anytype) !*Self {
        const self = try allocator.create(Self);
        const msg = switch (@TypeOf(message)) {
            []const u8 => message,
            else => if (@hasDecl(@TypeOf(message), "__str__"))
                try message.__str__(allocator)
            else
                "",
        };
        // Convert exceptions to PyValue slice
        const exc_slice = switch (@TypeOf(exceptions)) {
            []const PyValue => exceptions,
            else => blk: {
                const exc_copy = try allocator.alloc(PyValue, exceptions.len);
                for (exceptions, 0..) |exc, i| {
                    exc_copy[i] = PyValue.from(exc);
                }
                break :blk exc_copy;
            },
        };
        self.* = .{
            .message = msg,
            .exceptions = exc_slice,
            .allocator = allocator,
        };
        return self;
    }

    pub fn __str__(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
        return try std.fmt.allocPrint(allocator, "{s} ({d} sub-exception(s))", .{ self.message, self.exceptions.len });
    }

    pub fn __repr__(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
        return try std.fmt.allocPrint(allocator, "BaseExceptionGroup('{s}', [{d} exceptions])", .{ self.message, self.exceptions.len });
    }

    /// Return a subgroup of exceptions matching the given type
    /// The match_type should have a `name` field (comptime string) or be a type predicate
    pub fn subgroup(self: *const Self, comptime match_type: type) ?*Self {
        const match_name = if (@hasDecl(match_type, "name")) match_type.name else @typeName(match_type);

        // Count matching exceptions
        var match_count: usize = 0;
        for (self.exceptions) |exc| {
            if (matchesType(exc, match_name)) {
                match_count += 1;
            }
        }

        if (match_count == 0) return null;
        if (match_count == self.exceptions.len) return @constCast(self);

        // Create new group with matching exceptions
        const matching = self.allocator.alloc(PyValue, match_count) catch return null;
        var idx: usize = 0;
        for (self.exceptions) |exc| {
            if (matchesType(exc, match_name)) {
                matching[idx] = exc;
                idx += 1;
            }
        }

        const new_group = self.allocator.create(Self) catch return null;
        new_group.* = .{
            .message = self.message,
            .exceptions = matching,
            .allocator = self.allocator,
        };
        return new_group;
    }

    /// Split the group into matching and non-matching subgroups
    pub fn split(self: *const Self, comptime match_type: type) struct { ?*Self, ?*Self } {
        const match_name = if (@hasDecl(match_type, "name")) match_type.name else @typeName(match_type);

        // Count matching and non-matching
        var match_count: usize = 0;
        var non_match_count: usize = 0;
        for (self.exceptions) |exc| {
            if (matchesType(exc, match_name)) {
                match_count += 1;
            } else {
                non_match_count += 1;
            }
        }

        // All match
        if (non_match_count == 0) return .{ @constCast(self), null };
        // None match
        if (match_count == 0) return .{ null, @constCast(self) };

        // Create both groups
        const matching = self.allocator.alloc(PyValue, match_count) catch return .{ null, null };
        const non_matching = self.allocator.alloc(PyValue, non_match_count) catch return .{ null, null };

        var match_idx: usize = 0;
        var non_match_idx: usize = 0;
        for (self.exceptions) |exc| {
            if (matchesType(exc, match_name)) {
                matching[match_idx] = exc;
                match_idx += 1;
            } else {
                non_matching[non_match_idx] = exc;
                non_match_idx += 1;
            }
        }

        const match_group = self.allocator.create(Self) catch return .{ null, null };
        match_group.* = .{
            .message = self.message,
            .exceptions = matching,
            .allocator = self.allocator,
        };

        const non_match_group = self.allocator.create(Self) catch return .{ match_group, null };
        non_match_group.* = .{
            .message = self.message,
            .exceptions = non_matching,
            .allocator = self.allocator,
        };

        return .{ match_group, non_match_group };
    }

    /// Helper to check if an exception matches a type name
    fn matchesType(exc: PyValue, type_name: []const u8) bool {
        // For ptr values, check if they have a matching __name__ or name field
        if (exc == .ptr) {
            // Cannot inspect opaque pointers at runtime without type info
            return false;
        }
        // For string values that might be exception type names
        if (exc == .string) {
            return std.mem.eql(u8, exc.string, type_name);
        }
        return false;
    }
};

/// ExceptionGroup - groups multiple Exception subclasses together (Python 3.11+)
/// Can only contain Exception subclasses (not BaseException)
pub const ExceptionGroup = struct {
    pub const __name__ = "ExceptionGroup";
    pub const name = "ExceptionGroup";
    message: []const u8,
    exceptions: []const PyValue,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, message: anytype, exceptions: anytype) !*Self {
        const self = try allocator.create(Self);
        const msg = switch (@TypeOf(message)) {
            []const u8 => message,
            else => if (@hasDecl(@TypeOf(message), "__str__"))
                try message.__str__(allocator)
            else
                "",
        };
        // Convert exceptions to PyValue slice
        const exc_slice = switch (@TypeOf(exceptions)) {
            []const PyValue => exceptions,
            else => blk: {
                const exc_copy = try allocator.alloc(PyValue, exceptions.len);
                for (exceptions, 0..) |exc, i| {
                    exc_copy[i] = PyValue.from(exc);
                }
                break :blk exc_copy;
            },
        };
        self.* = .{
            .message = msg,
            .exceptions = exc_slice,
            .allocator = allocator,
        };
        return self;
    }

    pub fn __str__(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
        return try std.fmt.allocPrint(allocator, "{s} ({d} sub-exception(s))", .{ self.message, self.exceptions.len });
    }

    pub fn __repr__(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
        return try std.fmt.allocPrint(allocator, "ExceptionGroup('{s}', [{d} exceptions])", .{ self.message, self.exceptions.len });
    }

    /// Return a subgroup of exceptions matching the given type
    pub fn subgroup(self: *const Self, comptime match_type: type) ?*Self {
        const match_name = if (@hasDecl(match_type, "name")) match_type.name else @typeName(match_type);

        // Count matching exceptions
        var match_count: usize = 0;
        for (self.exceptions) |exc| {
            if (matchesType(exc, match_name)) {
                match_count += 1;
            }
        }

        if (match_count == 0) return null;
        if (match_count == self.exceptions.len) return @constCast(self);

        // Create new group with matching exceptions
        const matching = self.allocator.alloc(PyValue, match_count) catch return null;
        var idx: usize = 0;
        for (self.exceptions) |exc| {
            if (matchesType(exc, match_name)) {
                matching[idx] = exc;
                idx += 1;
            }
        }

        const new_group = self.allocator.create(Self) catch return null;
        new_group.* = .{
            .message = self.message,
            .exceptions = matching,
            .allocator = self.allocator,
        };
        return new_group;
    }

    /// Split the group into matching and non-matching subgroups
    pub fn split(self: *const Self, comptime match_type: type) struct { ?*Self, ?*Self } {
        const match_name = if (@hasDecl(match_type, "name")) match_type.name else @typeName(match_type);

        // Count matching and non-matching
        var match_count: usize = 0;
        var non_match_count: usize = 0;
        for (self.exceptions) |exc| {
            if (matchesType(exc, match_name)) {
                match_count += 1;
            } else {
                non_match_count += 1;
            }
        }

        // All match
        if (non_match_count == 0) return .{ @constCast(self), null };
        // None match
        if (match_count == 0) return .{ null, @constCast(self) };

        // Create both groups
        const matching = self.allocator.alloc(PyValue, match_count) catch return .{ null, null };
        const non_matching = self.allocator.alloc(PyValue, non_match_count) catch return .{ null, null };

        var match_idx: usize = 0;
        var non_match_idx: usize = 0;
        for (self.exceptions) |exc| {
            if (matchesType(exc, match_name)) {
                matching[match_idx] = exc;
                match_idx += 1;
            } else {
                non_matching[non_match_idx] = exc;
                non_match_idx += 1;
            }
        }

        const match_group = self.allocator.create(Self) catch return .{ null, null };
        match_group.* = .{
            .message = self.message,
            .exceptions = matching,
            .allocator = self.allocator,
        };

        const non_match_group = self.allocator.create(Self) catch return .{ match_group, null };
        non_match_group.* = .{
            .message = self.message,
            .exceptions = non_matching,
            .allocator = self.allocator,
        };

        return .{ match_group, non_match_group };
    }

    /// Helper to check if an exception matches a type name
    fn matchesType(exc: PyValue, type_name: []const u8) bool {
        if (exc == .ptr) {
            return false;
        }
        if (exc == .string) {
            return std.mem.eql(u8, exc.string, type_name);
        }
        return false;
    }
};
