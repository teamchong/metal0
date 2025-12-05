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

/// Thread-local buffer for formatted exception messages (e.g., with repr values)
threadlocal var exception_message_buffer: [512]u8 = undefined;

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
    _,

    /// Check if an i64 value represents an exception type
    pub fn isExceptionType(value: i64) bool {
        return value <= -1000001 and value >= -1000028;
    }
};

/// Helper to create an exception struct with proper init methods
fn ExceptionClass(comptime exception_name: []const u8) type {
    return struct {
        pub const name = exception_name;
        args: []const PyValue = &[_]PyValue{},
        allocator: std.mem.Allocator = undefined,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) !*Self {
            const self = try allocator.create(Self);
            self.* = .{
                .args = &[_]PyValue{},
                .allocator = allocator,
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
                var result = std.ArrayList(u8).init(allocator);
                try result.appendSlice("(");
                for (self.args, 0..) |arg, i| {
                    if (i > 0) try result.appendSlice(", ");
                    const s = try arg.toRepr(allocator);
                    try result.appendSlice(s);
                }
                try result.appendSlice(")");
                return result.toOwnedSlice();
            }
        }

        pub fn __repr__(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
            var result = std.ArrayList(u8).init(allocator);
            try result.appendSlice(name);
            try result.appendSlice("(");
            for (self.args, 0..) |arg, i| {
                if (i > 0) try result.appendSlice(", ");
                const s = try arg.toRepr(allocator);
                try result.appendSlice(s);
            }
            try result.appendSlice(")");
            return result.toOwnedSlice();
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
            var result = std.ArrayList(u8).init(allocator);
            try result.appendSlice("(");
            for (self.args, 0..) |arg, i| {
                if (i > 0) try result.appendSlice(", ");
                const s = try arg.toRepr(allocator);
                try result.appendSlice(s);
            }
            try result.appendSlice(")");
            return result.toOwnedSlice();
        }
    }

    pub fn __repr__(self: *const BaseException, allocator: std.mem.Allocator) ![]const u8 {
        var result = std.ArrayList(u8).init(allocator);
        try result.appendSlice(name);
        try result.appendSlice("(");
        for (self.args, 0..) |arg, i| {
            if (i > 0) try result.appendSlice(", ");
            const s = try arg.toRepr(allocator);
            try result.appendSlice(s);
        }
        try result.appendSlice(")");
        return result.toOwnedSlice();
    }
};

/// Exception - the common base class for all non-exit exceptions
pub const Exception = struct {
    pub const name = "Exception";
    args: []const PyValue,
    allocator: std.mem.Allocator,
    __class__: type = Exception,

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
            var result = std.ArrayList(u8).init(allocator);
            try result.appendSlice("(");
            for (self.args, 0..) |arg, i| {
                if (i > 0) try result.appendSlice(", ");
                const s = try arg.toRepr(allocator);
                try result.appendSlice(s);
            }
            try result.appendSlice(")");
            return result.toOwnedSlice();
        }
    }

    pub fn __repr__(self: *const Exception, allocator: std.mem.Allocator) ![]const u8 {
        var result = std.ArrayList(u8).init(allocator);
        try result.appendSlice(name);
        try result.appendSlice("(");
        for (self.args, 0..) |arg, i| {
            if (i > 0) try result.appendSlice(", ");
            const s = try arg.toRepr(allocator);
            try result.appendSlice(s);
        }
        try result.appendSlice(")");
        return result.toOwnedSlice();
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
