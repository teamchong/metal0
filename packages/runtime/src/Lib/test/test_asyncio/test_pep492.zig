//! test.test_asyncio.test_pep492 - Tests for PEP 492 async/await
//! Reference: cpython/Lib/test/test_asyncio/test_pep492.py
//!
//! Tests for async/await syntax and semantics (PEP 492)

const std = @import("std");
const utils = @import("utils.zig");
const test_events = @import("test_events.zig");

// ============================================================================
// Coroutine Type Checking
// ============================================================================

/// Check if a type is a coroutine
pub fn iscoroutine(comptime T: type) bool {
    return @hasDecl(T, "send") and @hasDecl(T, "throw") and @hasDecl(T, "close");
}

/// Check if a function is a coroutine function
pub fn iscoroutinefunction(comptime T: type) bool {
    return @typeInfo(T) == .Fn and @hasDecl(T, "is_coroutine");
}

// ============================================================================
// Awaitable Protocol
// ============================================================================

/// Check if a type is awaitable
pub fn isawaitable(comptime T: type) bool {
    return @hasDecl(T, "__await__") or
        @hasDecl(T, "send") or
        @hasField(T, "_asyncio_future_blocking");
}

/// An awaitable wrapper
pub fn Awaitable(comptime T: type) type {
    return struct {
        const Self = @This();

        _value: T,
        _ready: bool = false,

        pub fn init(value: T) Self {
            return .{ ._value = value };
        }

        pub fn __await__(self: *Self) *Self {
            return self;
        }

        pub fn send(self: *Self, _: ?*anyopaque) !?T {
            if (self._ready) {
                return self._value;
            }
            self._ready = true;
            return null;
        }

        pub fn throw(self: *Self, exc: anyerror) !void {
            _ = self;
            return exc;
        }

        pub fn close(self: *Self) void {
            self._ready = true;
        }
    };
}

// ============================================================================
// Async Iterator Protocol
// ============================================================================

/// Check if a type is an async iterator
pub fn isasyncgen(comptime T: type) bool {
    return @hasDecl(T, "__anext__") and @hasDecl(T, "__aiter__");
}

/// Check if a function is an async generator function
pub fn isasyncgenfunction(comptime T: type) bool {
    return @hasDecl(T, "is_async_generator");
}

/// Async iterator wrapper
pub fn AsyncIterator(comptime T: type) type {
    return struct {
        const Self = @This();

        _items: []const T,
        _index: usize = 0,

        pub fn init(items: []const T) Self {
            return .{ ._items = items };
        }

        pub fn __aiter__(self: *Self) *Self {
            return self;
        }

        pub fn __anext__(self: *Self) !?T {
            if (self._index >= self._items.len) {
                return error.StopAsyncIteration;
            }
            const item = self._items[self._index];
            self._index += 1;
            return item;
        }
    };
}

// ============================================================================
// Async Context Manager Protocol
// ============================================================================

/// Check if a type is an async context manager
pub fn isasynccontextmanager(comptime T: type) bool {
    return @hasDecl(T, "__aenter__") and @hasDecl(T, "__aexit__");
}

/// Async context manager wrapper
pub fn AsyncContextManager(comptime T: type) type {
    return struct {
        const Self = @This();

        _value: T,
        _entered: bool = false,
        _exited: bool = false,

        pub fn init(value: T) Self {
            return .{ ._value = value };
        }

        pub fn __aenter__(self: *Self) !T {
            self._entered = true;
            return self._value;
        }

        pub fn __aexit__(self: *Self, exc_type: ?anyerror, exc_val: ?*anyopaque, exc_tb: ?*anyopaque) !bool {
            _ = exc_type;
            _ = exc_val;
            _ = exc_tb;
            self._exited = true;
            return false; // Don't suppress exception
        }
    };
}

// ============================================================================
// Test Cases
// ============================================================================

fn testIscoroutine() !void {
    const Coro = struct {
        pub fn send(_: *@This(), _: ?*anyopaque) !?i32 {
            return null;
        }
        pub fn throw(_: *@This(), _: anyerror) !void {}
        pub fn close(_: *@This()) void {}
    };

    try std.testing.expect(iscoroutine(Coro));

    const NotCoro = struct { value: i32 };
    try std.testing.expect(!iscoroutine(NotCoro));
}

fn testIsawaitable() !void {
    const AwaitableType = struct {
        _asyncio_future_blocking: bool = false,
    };

    try std.testing.expect(isawaitable(AwaitableType));

    const NotAwaitable = struct { value: i32 };
    try std.testing.expect(!isawaitable(NotAwaitable));
}

fn testAwaitable() !void {
    var awaitable = Awaitable(i32).init(42);

    // First send returns null (not ready)
    const first = try awaitable.send(null);
    try std.testing.expect(first == null);

    // Second send returns value
    const second = try awaitable.send(null);
    try std.testing.expectEqual(@as(?i32, 42), second);
}

fn testAsyncIterator() !void {
    const items = [_]i32{ 1, 2, 3 };
    var iter = AsyncIterator(i32).init(&items);

    try std.testing.expectEqual(@as(?i32, 1), try iter.__anext__());
    try std.testing.expectEqual(@as(?i32, 2), try iter.__anext__());
    try std.testing.expectEqual(@as(?i32, 3), try iter.__anext__());

    const err = iter.__anext__();
    try std.testing.expectError(error.StopAsyncIteration, err);
}

fn testIsasyncgen() !void {
    const AsyncGen = struct {
        pub fn __aiter__(_: *@This()) *@This() {
            return undefined;
        }
        pub fn __anext__(_: *@This()) !?i32 {
            return null;
        }
    };

    try std.testing.expect(isasyncgen(AsyncGen));
}

fn testAsyncContextManager() !void {
    var ctx = AsyncContextManager(i32).init(42);

    try std.testing.expect(!ctx._entered);
    try std.testing.expect(!ctx._exited);

    const value = try ctx.__aenter__();
    try std.testing.expectEqual(@as(i32, 42), value);
    try std.testing.expect(ctx._entered);

    _ = try ctx.__aexit__(null, null, null);
    try std.testing.expect(ctx._exited);
}

fn testIsasynccontextmanager() !void {
    const AsyncCM = struct {
        pub fn __aenter__(_: *@This()) !void {}
        pub fn __aexit__(_: *@This(), _: ?anyerror, _: ?*anyopaque, _: ?*anyopaque) !bool {
            return false;
        }
    };

    try std.testing.expect(isasynccontextmanager(AsyncCM));
}

fn testAwaitableClose() !void {
    var awaitable = Awaitable(i32).init(42);
    awaitable.close();
    try std.testing.expect(awaitable._ready);
}

fn testAsyncIteratorAiter() !void {
    const items = [_]i32{ 1, 2 };
    var iter = AsyncIterator(i32).init(&items);

    const self_ref = iter.__aiter__();
    try std.testing.expect(self_ref == &iter);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "iscoroutine" {
    try testIscoroutine();
}

test "isawaitable" {
    try testIsawaitable();
}

test "Awaitable" {
    try testAwaitable();
}

test "AsyncIterator" {
    try testAsyncIterator();
}

test "isasyncgen" {
    try testIsasyncgen();
}

test "AsyncContextManager" {
    try testAsyncContextManager();
}

test "isasynccontextmanager" {
    try testIsasynccontextmanager();
}

test "Awaitable close" {
    try testAwaitableClose();
}

test "AsyncIterator aiter" {
    try testAsyncIteratorAiter();
}
