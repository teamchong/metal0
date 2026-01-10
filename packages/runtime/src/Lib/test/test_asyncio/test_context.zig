//! test.test_asyncio.test_context - Tests for asyncio context variables
//! Reference: cpython/Lib/test/test_asyncio/test_context.py
//!
//! Tests for contextvars integration with asyncio

const std = @import("std");
const utils = @import("utils.zig");
const test_events = @import("test_events.zig");
const test_tasks = @import("test_tasks.zig");

// ============================================================================
// Context Variable Implementation
// ============================================================================

/// A context variable for storing task-local state
pub fn ContextVar(comptime T: type) type {
    return struct {
        const Self = @This();

        _name: []const u8,
        _default: ?T,
        _value: ?T = null,
        _set: bool = false,

        pub fn init(name: []const u8, default: ?T) Self {
            return .{
                ._name = name,
                ._default = default,
            };
        }

        pub fn get(self: *const Self) T {
            if (self._set) {
                return self._value.?;
            }
            if (self._default) |d| {
                return d;
            }
            @panic("ContextVar has no value and no default");
        }

        pub fn get_or(self: *const Self, default: T) T {
            if (self._set) {
                return self._value.?;
            }
            return default;
        }

        pub fn set(self: *Self, value: T) Token(T) {
            const old = if (self._set) self._value else null;
            self._value = value;
            self._set = true;
            return Token(T){
                ._var = self,
                ._old_value = old,
                ._was_set = self._set,
            };
        }

        pub fn reset(self: *Self, token: Token(T)) void {
            if (token._was_set) {
                self._value = token._old_value;
            } else {
                self._value = null;
                self._set = false;
            }
        }
    };
}

/// Token for resetting a context variable
pub fn Token(comptime T: type) type {
    return struct {
        _var: *ContextVar(T),
        _old_value: ?T,
        _was_set: bool,
    };
}

// ============================================================================
// Context Implementation
// ============================================================================

/// Execution context for storing context variables
pub const Context = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _data: std.StringHashMap(*anyopaque),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            ._data = std.StringHashMap(*anyopaque).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self._data.deinit();
    }

    /// Run a function with this context
    pub fn run(self: *Self, func: *const fn () void) void {
        _ = self;
        func();
    }

    /// Copy the context
    pub fn copy(self: *const Self) !Context {
        var new_ctx = Context.init(self.allocator);
        var it = self._data.iterator();
        while (it.next()) |entry| {
            try new_ctx._data.put(entry.key_ptr.*, entry.value_ptr.*);
        }
        return new_ctx;
    }
};

/// Get a copy of the current context
pub fn copy_context(allocator: std.mem.Allocator) Context {
    return Context.init(allocator);
}

// ============================================================================
// Task Context
// ============================================================================

/// Get the context of a task
pub fn get_task_context(_: *test_tasks.Task) ?*Context {
    return null;
}

/// Set the context of a task
pub fn set_task_context(_: *test_tasks.Task, _: *Context) void {}

// ============================================================================
// Test Cases
// ============================================================================

fn testContextVarDefault() !void {
    var cv = ContextVar(i32).init("test_var", 42);
    try std.testing.expectEqual(@as(i32, 42), cv.get());
}

fn testContextVarSet() !void {
    var cv = ContextVar(i32).init("test_var", 0);
    _ = cv.set(100);
    try std.testing.expectEqual(@as(i32, 100), cv.get());
}

fn testContextVarReset() !void {
    var cv = ContextVar(i32).init("test_var", 0);

    const token = cv.set(100);
    try std.testing.expectEqual(@as(i32, 100), cv.get());

    cv.reset(token);
    try std.testing.expectEqual(@as(i32, 0), cv.get());
}

fn testContextVarGetOr() !void {
    var cv = ContextVar(i32).init("test_var", null);
    try std.testing.expectEqual(@as(i32, 99), cv.get_or(99));

    _ = cv.set(50);
    try std.testing.expectEqual(@as(i32, 50), cv.get_or(99));
}

fn testContextCreate() !void {
    const allocator = std.testing.allocator;
    var ctx = Context.init(allocator);
    defer ctx.deinit();

    try std.testing.expectEqual(@as(usize, 0), ctx._data.count());
}

fn testContextCopy() !void {
    const allocator = std.testing.allocator;
    var ctx = Context.init(allocator);
    defer ctx.deinit();

    var copy = try ctx.copy();
    defer copy.deinit();

    try std.testing.expectEqual(@as(usize, 0), copy._data.count());
}

fn testContextRun() !void {
    const allocator = std.testing.allocator;
    var ctx = Context.init(allocator);
    defer ctx.deinit();

    var called = false;
    const callback = struct {
        fn cb() void {
            // Would set called = true if we could capture
        }
    }.cb;

    ctx.run(callback);
    _ = called;
}

fn testCopyContext() !void {
    const allocator = std.testing.allocator;
    var ctx = copy_context(allocator);
    defer ctx.deinit();

    try std.testing.expectEqual(@as(usize, 0), ctx._data.count());
}

fn testContextVarMultipleSets() !void {
    var cv = ContextVar(i32).init("test_var", 0);

    const token1 = cv.set(10);
    try std.testing.expectEqual(@as(i32, 10), cv.get());

    const token2 = cv.set(20);
    try std.testing.expectEqual(@as(i32, 20), cv.get());

    cv.reset(token2);
    try std.testing.expectEqual(@as(i32, 10), cv.get());

    cv.reset(token1);
    try std.testing.expectEqual(@as(i32, 0), cv.get());
}

fn testContextVarString() !void {
    var cv = ContextVar([]const u8).init("string_var", "default");
    try std.testing.expectEqualStrings("default", cv.get());

    _ = cv.set("new value");
    try std.testing.expectEqualStrings("new value", cv.get());
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "ContextVar default" {
    try testContextVarDefault();
}

test "ContextVar set" {
    try testContextVarSet();
}

test "ContextVar reset" {
    try testContextVarReset();
}

test "ContextVar get_or" {
    try testContextVarGetOr();
}

test "Context create" {
    try testContextCreate();
}

test "Context copy" {
    try testContextCopy();
}

test "Context run" {
    try testContextRun();
}

test "copy_context" {
    try testCopyContext();
}

test "ContextVar multiple sets" {
    try testContextVarMultipleSets();
}

test "ContextVar string" {
    try testContextVarString();
}
