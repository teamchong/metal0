/// Python exception types
const std = @import("std");
const PyValue = @import("../py_value.zig").PyValue;

/// Python exception types mapped to Zig errors
pub const PythonError = error{
    ZeroDivisionError,
    IndexError,
    ValueError,
    TypeError,
    KeyError,
    OverflowError,
};

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

/// Python exception type constants for use in assertRaises, etc.
/// These are marker types that can be passed around and compared
pub const TypeError = struct {
    pub const name = "TypeError";
};
pub const ValueError = struct {
    pub const name = "ValueError";
};
pub const KeyError = struct {
    pub const name = "KeyError";
};
pub const IndexError = struct {
    pub const name = "IndexError";
};
pub const ZeroDivisionError = struct {
    pub const name = "ZeroDivisionError";
};
pub const AttributeError = struct {
    pub const name = "AttributeError";
};
pub const NameError = struct {
    pub const name = "NameError";
};
pub const FileNotFoundError = struct {
    pub const name = "FileNotFoundError";
};
pub const IOError = struct {
    pub const name = "IOError";
};
pub const RuntimeError = struct {
    pub const name = "RuntimeError";
    args: []const PyValue = &[_]PyValue{},
    allocator: std.mem.Allocator = undefined,

    pub fn init(allocator: std.mem.Allocator) !*RuntimeError {
        const self = try allocator.create(RuntimeError);
        self.* = .{
            .args = &[_]PyValue{},
            .allocator = allocator,
        };
        return self;
    }

    pub fn initWithArg(allocator: std.mem.Allocator, arg: anytype) !*RuntimeError {
        const self = try allocator.create(RuntimeError);
        const args_copy = try allocator.alloc(PyValue, 1);
        args_copy[0] = try PyValue.fromAlloc(allocator, arg);
        self.* = .{
            .args = args_copy,
            .allocator = allocator,
        };
        return self;
    }

    pub fn initWithArgs(allocator: std.mem.Allocator, args: []const PyValue) !*RuntimeError {
        const self = try allocator.create(RuntimeError);
        const args_copy = try allocator.alloc(PyValue, args.len);
        @memcpy(args_copy, args);
        self.* = .{
            .args = args_copy,
            .allocator = allocator,
        };
        return self;
    }
};
pub const StopIteration = struct {
    pub const name = "StopIteration";
};
pub const NotImplementedError = struct {
    pub const name = "NotImplementedError";
};
pub const AssertionError = struct {
    pub const name = "AssertionError";
};
pub const OverflowError = struct {
    pub const name = "OverflowError";
};
pub const ImportError = struct {
    pub const name = "ImportError";
};
pub const ModuleNotFoundError = struct {
    pub const name = "ModuleNotFoundError";
};
pub const OSError = struct {
    pub const name = "OSError";
};
pub const PermissionError = struct {
    pub const name = "PermissionError";
};
pub const TimeoutError = struct {
    pub const name = "TimeoutError";
};
pub const ConnectionError = struct {
    pub const name = "ConnectionError";
};
pub const RecursionError = struct {
    pub const name = "RecursionError";
};
pub const MemoryError = struct {
    pub const name = "MemoryError";
};
pub const LookupError = struct {
    pub const name = "LookupError";
};
pub const ArithmeticError = struct {
    pub const name = "ArithmeticError";
};
pub const BufferError = struct {
    pub const name = "BufferError";
};
pub const EOFError = struct {
    pub const name = "EOFError";
};
pub const GeneratorExit = struct {
    pub const name = "GeneratorExit";
};
pub const SystemExit = struct {
    pub const name = "SystemExit";
};
pub const KeyboardInterrupt = struct {
    pub const name = "KeyboardInterrupt";
};
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
