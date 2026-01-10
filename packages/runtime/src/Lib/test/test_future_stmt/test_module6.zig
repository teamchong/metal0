//! test.test_future_stmt.test_generators - Tests for `from __future__ import generators`
//!
//! PEP 255 introduced generator functions using the yield statement.
//! Generators became standard in Python 2.3 but this future import was
//! available in Python 2.2 for forward compatibility.
//!
//! This module tests generator behavior and iterator protocols.
//!
//! CPython Reference: https://docs.python.org/3/library/__future__.html
//! PEP 255: https://peps.python.org/pep-0255/

const std = @import("std");
const testing = std.testing;

// ============================================================================
// Generator State
// ============================================================================

/// Represents the state of a generator
pub const GeneratorState = enum {
    /// Generator has not started
    created,
    /// Generator is currently executing
    running,
    /// Generator is suspended at a yield
    suspended,
    /// Generator has completed (returned or raised StopIteration)
    completed,

    pub fn name(self: GeneratorState) []const u8 {
        return switch (self) {
            .created => "GEN_CREATED",
            .running => "GEN_RUNNING",
            .suspended => "GEN_SUSPENDED",
            .completed => "GEN_CLOSED",
        };
    }

    /// Check if the generator can be resumed
    pub fn canResume(self: GeneratorState) bool {
        return self == .created or self == .suspended;
    }
};

// ============================================================================
// Simple Generator (Range-like)
// ============================================================================

/// A simple range generator that yields integers
pub const RangeGenerator = struct {
    start: i64,
    stop: i64,
    step: i64,
    current: i64,
    state: GeneratorState,

    const Self = @This();

    /// Create a range generator
    pub fn init(start: i64, stop: i64, step: i64) Self {
        return .{
            .start = start,
            .stop = stop,
            .step = step,
            .current = start,
            .state = .created,
        };
    }

    /// Create a simple range(stop) generator
    pub fn range(stop: i64) Self {
        return init(0, stop, 1);
    }

    /// Get the next value (simulates yield)
    pub fn next(self: *Self) ?i64 {
        if (self.state == .completed) return null;

        if (self.state == .created) {
            self.state = .running;
        }

        if (self.step > 0 and self.current >= self.stop) {
            self.state = .completed;
            return null;
        }
        if (self.step < 0 and self.current <= self.stop) {
            self.state = .completed;
            return null;
        }

        const value = self.current;
        self.current += self.step;
        self.state = .suspended;
        return value;
    }

    /// Close the generator
    pub fn close(self: *Self) void {
        self.state = .completed;
    }

    /// Throw an exception into the generator
    pub fn throw(self: *Self) void {
        self.state = .completed;
    }

    /// Send a value into the generator (for coroutine-like behavior)
    pub fn send(self: *Self, _: anytype) ?i64 {
        return self.next();
    }

    /// Get current state
    pub fn getState(self: Self) GeneratorState {
        return self.state;
    }
};

// ============================================================================
// Generic Generator
// ============================================================================

/// Generic generator that can yield any type
pub fn Generator(comptime T: type) type {
    return struct {
        /// Function that produces the next value
        next_fn: *const fn (*@This()) ?T,
        /// User data pointer
        data: *anyopaque,
        /// Current state
        state: GeneratorState = .created,
        /// Last yielded value
        last_value: ?T = null,

        const Self = @This();

        /// Get the next value
        pub fn next(self: *Self) ?T {
            if (self.state == .completed) return null;

            if (self.state == .created) {
                self.state = .running;
            }

            const value = self.next_fn(self);
            if (value == null) {
                self.state = .completed;
            } else {
                self.state = .suspended;
                self.last_value = value;
            }
            return value;
        }

        /// Convert to a slice (collect all values)
        pub fn collect(self: *Self, allocator: std.mem.Allocator) ![]T {
            var result = std.ArrayList(T).init(allocator);
            while (self.next()) |value| {
                try result.append(value);
            }
            return try result.toOwnedSlice();
        }

        /// Close the generator
        pub fn close(self: *Self) void {
            self.state = .completed;
        }
    };
}

// ============================================================================
// Generator Expression Support
// ============================================================================

/// Represents a generator expression (x for x in iterable if condition)
pub fn GenExpr(comptime T: type, comptime Source: type) type {
    return struct {
        source: Source,
        transform: ?*const fn (anytype) T = null,
        filter: ?*const fn (anytype) bool = null,
        exhausted: bool = false,

        const Self = @This();

        pub fn init(source: Source) Self {
            return .{ .source = source };
        }

        /// Set a transform function
        pub fn map(self: *Self, func: *const fn (anytype) T) *Self {
            self.transform = func;
            return self;
        }

        /// Set a filter function
        pub fn where(self: *Self, predicate: *const fn (anytype) bool) *Self {
            self.filter = predicate;
            return self;
        }

        /// Get the next value
        pub fn next(self: *Self) ?T {
            if (self.exhausted) return null;

            while (self.source.next()) |value| {
                // Apply filter if set
                if (self.filter) |f| {
                    if (!f(value)) continue;
                }
                // Apply transform if set
                if (self.transform) |t| {
                    return t(value);
                }
                return value;
            }

            self.exhausted = true;
            return null;
        }
    };
}

// ============================================================================
// Yield From Support (PEP 380)
// ============================================================================

/// Wrapper for yield from semantics
pub fn YieldFrom(comptime T: type) type {
    return struct {
        inner: *Iterator(T),
        finished: bool = false,

        const Self = @This();

        pub fn init(inner: *Iterator(T)) Self {
            return .{ .inner = inner };
        }

        /// Get next value from inner generator
        pub fn next(self: *Self) ?T {
            if (self.finished) return null;

            if (self.inner.next()) |value| {
                return value;
            } else {
                self.finished = true;
                return null;
            }
        }
    };
}

/// Generic iterator interface
pub fn Iterator(comptime T: type) type {
    return struct {
        next_fn: *const fn (*@This()) ?T,

        const Self = @This();

        pub fn next(self: *Self) ?T {
            return self.next_fn(self);
        }
    };
}

// ============================================================================
// Generator Utilities
// ============================================================================

/// Chain multiple iterators together
pub fn Chain(comptime T: type) type {
    return struct {
        iterators: std.ArrayListUnmanaged(*Iterator(T)),
        allocator: std.mem.Allocator,
        current_index: usize = 0,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .iterators = .{},
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.iterators.deinit(self.allocator);
        }

        pub fn add(self: *Self, iter: *Iterator(T)) !void {
            try self.iterators.append(self.allocator, iter);
        }

        pub fn next(self: *Self) ?T {
            while (self.current_index < self.iterators.items.len) {
                if (self.iterators.items[self.current_index].next()) |value| {
                    return value;
                }
                self.current_index += 1;
            }
            return null;
        }
    };
}

/// Take first n elements from an iterator
pub fn Take(comptime T: type) type {
    return struct {
        source: *Iterator(T),
        remaining: usize,

        const Self = @This();

        pub fn init(source: *Iterator(T), n: usize) Self {
            return .{ .source = source, .remaining = n };
        }

        pub fn next(self: *Self) ?T {
            if (self.remaining == 0) return null;
            self.remaining -= 1;
            return self.source.next();
        }
    };
}

/// Skip first n elements from an iterator
pub fn Skip(comptime T: type) type {
    return struct {
        source: *Iterator(T),
        to_skip: usize,
        skipped: bool = false,

        const Self = @This();

        pub fn init(source: *Iterator(T), n: usize) Self {
            return .{ .source = source, .to_skip = n };
        }

        pub fn next(self: *Self) ?T {
            if (!self.skipped) {
                var i: usize = 0;
                while (i < self.to_skip) : (i += 1) {
                    _ = self.source.next();
                }
                self.skipped = true;
            }
            return self.source.next();
        }
    };
}

// ============================================================================
// Generator-based Fibonacci
// ============================================================================

/// Fibonacci generator (infinite sequence)
pub const FibonacciGenerator = struct {
    a: i64 = 0,
    b: i64 = 1,
    state: GeneratorState = .created,

    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    pub fn next(self: *Self) i64 {
        if (self.state == .created) {
            self.state = .suspended;
        }

        const value = self.a;
        const new_b = self.a +| self.b; // Saturating add to prevent overflow
        self.a = self.b;
        self.b = new_b;
        return value;
    }

    pub fn take(self: *Self, allocator: std.mem.Allocator, n: usize) ![]i64 {
        var result = try allocator.alloc(i64, n);
        for (0..n) |i| {
            result[i] = self.next();
        }
        return result;
    }
};

// ============================================================================
// Coroutine-like Generator (send/throw support)
// ============================================================================

/// Generator with coroutine capabilities
pub fn Coroutine(comptime YieldT: type, comptime SendT: type) type {
    return struct {
        state: GeneratorState = .created,
        yield_value: ?YieldT = null,
        send_value: ?SendT = null,
        step_fn: *const fn (*@This()) void,

        const Self = @This();

        /// Send a value and get the next yielded value
        pub fn send(self: *Self, value: SendT) ?YieldT {
            if (!self.state.canResume()) return null;

            self.send_value = value;
            self.state = .running;
            self.step_fn(self);

            if (self.state == .completed) return null;
            return self.yield_value;
        }

        /// Resume without sending a value
        pub fn next(self: *Self) ?YieldT {
            return self.send(undefined);
        }

        /// Close the coroutine
        pub fn close(self: *Self) void {
            self.state = .completed;
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "generator_state_names" {
    try testing.expectEqualStrings("GEN_CREATED", GeneratorState.created.name());
    try testing.expectEqualStrings("GEN_RUNNING", GeneratorState.running.name());
    try testing.expectEqualStrings("GEN_SUSPENDED", GeneratorState.suspended.name());
    try testing.expectEqualStrings("GEN_CLOSED", GeneratorState.completed.name());
}

test "generator_state_can_resume" {
    try testing.expect(GeneratorState.created.canResume());
    try testing.expect(GeneratorState.suspended.canResume());
    try testing.expect(!GeneratorState.running.canResume());
    try testing.expect(!GeneratorState.completed.canResume());
}

test "range_generator_basic" {
    var gen = RangeGenerator.range(3);

    try testing.expectEqual(@as(?i64, 0), gen.next());
    try testing.expectEqual(@as(?i64, 1), gen.next());
    try testing.expectEqual(@as(?i64, 2), gen.next());
    try testing.expect(gen.next() == null);
}

test "range_generator_with_step" {
    var gen = RangeGenerator.init(0, 10, 2);

    try testing.expectEqual(@as(?i64, 0), gen.next());
    try testing.expectEqual(@as(?i64, 2), gen.next());
    try testing.expectEqual(@as(?i64, 4), gen.next());
    try testing.expectEqual(@as(?i64, 6), gen.next());
    try testing.expectEqual(@as(?i64, 8), gen.next());
    try testing.expect(gen.next() == null);
}

test "range_generator_negative_step" {
    var gen = RangeGenerator.init(5, 0, -1);

    try testing.expectEqual(@as(?i64, 5), gen.next());
    try testing.expectEqual(@as(?i64, 4), gen.next());
    try testing.expectEqual(@as(?i64, 3), gen.next());
    try testing.expectEqual(@as(?i64, 2), gen.next());
    try testing.expectEqual(@as(?i64, 1), gen.next());
    try testing.expect(gen.next() == null);
}

test "range_generator_state_transitions" {
    var gen = RangeGenerator.range(2);

    try testing.expectEqual(GeneratorState.created, gen.getState());

    _ = gen.next();
    try testing.expectEqual(GeneratorState.suspended, gen.getState());

    _ = gen.next();
    _ = gen.next();
    try testing.expectEqual(GeneratorState.completed, gen.getState());
}

test "range_generator_close" {
    var gen = RangeGenerator.range(100);

    _ = gen.next();
    gen.close();

    try testing.expectEqual(GeneratorState.completed, gen.getState());
    try testing.expect(gen.next() == null);
}

test "fibonacci_generator" {
    var fib = FibonacciGenerator.init();

    try testing.expectEqual(@as(i64, 0), fib.next());
    try testing.expectEqual(@as(i64, 1), fib.next());
    try testing.expectEqual(@as(i64, 1), fib.next());
    try testing.expectEqual(@as(i64, 2), fib.next());
    try testing.expectEqual(@as(i64, 3), fib.next());
    try testing.expectEqual(@as(i64, 5), fib.next());
    try testing.expectEqual(@as(i64, 8), fib.next());
}

test "fibonacci_take" {
    var fib = FibonacciGenerator.init();
    const values = try fib.take(testing.allocator, 7);
    defer testing.allocator.free(values);

    try testing.expectEqualSlices(i64, &.{ 0, 1, 1, 2, 3, 5, 8 }, values);
}

test "range_generator_empty" {
    var gen = RangeGenerator.range(0);
    try testing.expect(gen.next() == null);
    try testing.expectEqual(GeneratorState.completed, gen.getState());
}

test "range_generator_send" {
    var gen = RangeGenerator.range(3);
    // send should work like next for simple generators
    try testing.expectEqual(@as(?i64, 0), gen.send(42));
    try testing.expectEqual(@as(?i64, 1), gen.send(43));
}

test "generator_state_after_throw" {
    var gen = RangeGenerator.range(5);
    _ = gen.next();
    gen.throw();
    try testing.expectEqual(GeneratorState.completed, gen.getState());
    try testing.expect(gen.next() == null);
}

test "range_generator_start_stop" {
    var gen = RangeGenerator.init(5, 10, 1);

    try testing.expectEqual(@as(?i64, 5), gen.next());
    try testing.expectEqual(@as(?i64, 6), gen.next());
    try testing.expectEqual(@as(?i64, 7), gen.next());
    try testing.expectEqual(@as(?i64, 8), gen.next());
    try testing.expectEqual(@as(?i64, 9), gen.next());
    try testing.expect(gen.next() == null);
}

test "chain_type_compiles" {
    var chain = Chain(i64).init(testing.allocator);
    defer chain.deinit();
    try testing.expectEqual(@as(usize, 0), chain.iterators.items.len);
}

test "fibonacci_state" {
    var fib = FibonacciGenerator.init();
    try testing.expectEqual(GeneratorState.created, fib.state);

    _ = fib.next();
    try testing.expectEqual(GeneratorState.suspended, fib.state);
}
