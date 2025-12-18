//! Subinterpreters Test Support Module
//!
//! Test-only module for subinterpreter testing infrastructure.
//! Provides high-level interface to subinterpreter functionality.
//!
//! CPython source: Lib/test/support/interpreters/__init__.py
//! CPython equivalent: Test support for subinterpreters (wraps _interpreters C extension)

const std = @import("std");

/// Subinterpreter errors
pub const InterpreterError = error{
    NotImplemented,
    InterpreterNotFound,
    NotShareable,
    ExecutionFailed,
};

/// Check if a value is shareable between interpreters (stub)
pub fn is_shareable(value: anytype) bool {
    _ = value;
    // In CPython, only basic types (int, str, bytes, None) are shareable
    // For now, return false (not implemented)
    return false;
}

/// Get current interpreter (stub)
pub fn get_current(allocator: std.mem.Allocator) !i64 {
    _ = allocator;
    return error.NotImplemented;
}

/// Get main interpreter (stub)
pub fn get_main(allocator: std.mem.Allocator) !i64 {
    _ = allocator;
    return error.NotImplemented;
}

/// Create new interpreter (stub)
pub fn create(allocator: std.mem.Allocator) !i64 {
    _ = allocator;
    return error.NotImplemented;
}

/// List all interpreters (stub)
pub fn list_all(allocator: std.mem.Allocator) ![]i64 {
    _ = allocator;
    return error.NotImplemented;
}

/// Interpreter object (stub)
pub const Interpreter = struct {
    id: i64,

    pub fn init(id: i64) Interpreter {
        return .{ .id = id };
    }

    pub fn exec(self: Interpreter, allocator: std.mem.Allocator, code: []const u8) !void {
        _ = self;
        _ = allocator;
        _ = code;
        return error.NotImplemented;
    }

    pub fn call(self: Interpreter, allocator: std.mem.Allocator, func: anytype, args: anytype) !void {
        _ = self;
        _ = allocator;
        _ = func;
        _ = args;
        return error.NotImplemented;
    }
};

/// Queue errors
pub const QueueEmpty = error.QueueEmpty;
pub const QueueFull = error.QueueFull;

/// Cross-interpreter queue (stub)
pub const Queue = struct {
    id: i64,

    pub fn init(allocator: std.mem.Allocator) !Queue {
        _ = allocator;
        return error.NotImplemented;
    }

    pub fn put(self: Queue, allocator: std.mem.Allocator, value: anytype) !void {
        _ = self;
        _ = allocator;
        _ = value;
        return error.NotImplemented;
    }

    pub fn get(self: Queue, allocator: std.mem.Allocator) !void {
        _ = self;
        _ = allocator;
        return error.NotImplemented;
    }
};

/// Create queue (stub)
pub fn create_queue(allocator: std.mem.Allocator) !Queue {
    return Queue.init(allocator);
}

/// _crossinterp submodule stub
pub const _crossinterp = struct {
    pub const ChannelError = error{
        ChannelNotFound,
        ChannelClosed,
        ChannelEmpty,
        ChannelFull,
    };

    pub fn create_channel(allocator: std.mem.Allocator) !i64 {
        _ = allocator;
        return error.NotImplemented;
    }

    pub fn destroy_channel(allocator: std.mem.Allocator, channel_id: i64) !void {
        _ = allocator;
        _ = channel_id;
        return error.NotImplemented;
    }

    pub fn send(allocator: std.mem.Allocator, channel_id: i64, value: anytype) !void {
        _ = allocator;
        _ = channel_id;
        _ = value;
        return error.NotImplemented;
    }

    pub fn recv(allocator: std.mem.Allocator, channel_id: i64) !void {
        _ = allocator;
        _ = channel_id;
        return error.NotImplemented;
    }
};

test "interpreters stub" {
    // Basic sanity check that module compiles
    const shareable = is_shareable(42);
    try std.testing.expectEqual(false, shareable);
}
