/// unittest.case - TestCase base class
/// Mirrors: CPython Lib/unittest/case.py
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Result of an assertion
pub const AssertResult = union(enum) {
    pass,
    fail: []const u8,
    error_: anyerror,
    skip: []const u8,
};

/// TestCase - base class for test cases
pub const TestCase = struct {
    allocator: Allocator,
    name: []const u8,
    failures: std.ArrayList([]const u8),
    errors: std.ArrayList([]const u8),
    skipped: bool,
    skip_reason: ?[]const u8,

    const Self = @This();

    pub fn init(allocator: Allocator, name: []const u8) Self {
        return .{
            .allocator = allocator,
            .name = name,
            .failures = .{},
            .errors = .{},
            .skipped = false,
            .skip_reason = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.failures.deinit(self.allocator);
        self.errors.deinit(self.allocator);
    }

    /// setUp - called before each test method
    pub fn setUp(self: *Self) !void {
        _ = self;
        // Override in subclass
    }

    /// tearDown - called after each test method
    pub fn tearDown(self: *Self) !void {
        _ = self;
        // Override in subclass
    }

    /// setUpClass - called once before any tests in the class
    pub fn setUpClass(self: *Self) !void {
        _ = self;
        // Override in subclass
    }

    /// tearDownClass - called once after all tests in the class
    pub fn tearDownClass(self: *Self) !void {
        _ = self;
        // Override in subclass
    }

    // === Assertion Methods ===

    /// assertTrue - assert that value is true
    pub fn assertTrue(self: *Self, value: bool, msg: ?[]const u8) !void {
        if (!value) {
            const message = msg orelse "assertTrue failed";
            try self.failures.append(self.allocator,self.allocator, message);
            return error.AssertionFailed;
        }
    }

    /// assertFalse - assert that value is false
    pub fn assertFalse(self: *Self, value: bool, msg: ?[]const u8) !void {
        if (value) {
            const message = msg orelse "assertFalse failed";
            try self.failures.append(self.allocator,self.allocator, message);
            return error.AssertionFailed;
        }
    }

    /// assertEqual - assert that two values are equal
    pub fn assertEqual(self: *Self, comptime T: type, actual: T, expected: T, msg: ?[]const u8) !void {
        if (actual != expected) {
            const message = msg orelse "assertEqual failed";
            try self.failures.append(self.allocator,self.allocator, message);
            return error.AssertionFailed;
        }
    }

    /// assertNotEqual - assert that two values are not equal
    pub fn assertNotEqual(self: *Self, comptime T: type, actual: T, expected: T, msg: ?[]const u8) !void {
        if (actual == expected) {
            const message = msg orelse "assertNotEqual failed";
            try self.failures.append(self.allocator,self.allocator, message);
            return error.AssertionFailed;
        }
    }

    /// assertIs - assert that two references are the same object
    pub fn assertIs(self: *Self, comptime T: type, actual: T, expected: T, msg: ?[]const u8) !void {
        if (@intFromPtr(actual) != @intFromPtr(expected)) {
            const message = msg orelse "assertIs failed";
            try self.failures.append(self.allocator,self.allocator, message);
            return error.AssertionFailed;
        }
    }

    /// assertIsNot - assert that two references are different objects
    pub fn assertIsNot(self: *Self, comptime T: type, actual: T, expected: T, msg: ?[]const u8) !void {
        if (@intFromPtr(actual) == @intFromPtr(expected)) {
            const message = msg orelse "assertIsNot failed";
            try self.failures.append(self.allocator,self.allocator, message);
            return error.AssertionFailed;
        }
    }

    /// assertIsNone - assert value is null
    pub fn assertIsNone(self: *Self, value: anytype, msg: ?[]const u8) !void {
        if (value != null) {
            const message = msg orelse "assertIsNone failed";
            try self.failures.append(self.allocator,self.allocator, message);
            return error.AssertionFailed;
        }
    }

    /// assertIsNotNone - assert value is not null
    pub fn assertIsNotNone(self: *Self, value: anytype, msg: ?[]const u8) !void {
        if (value == null) {
            const message = msg orelse "assertIsNotNone failed";
            try self.failures.append(self.allocator,self.allocator, message);
            return error.AssertionFailed;
        }
    }

    /// assertIn - assert item is in container
    pub fn assertIn(self: *Self, comptime T: type, item: T, container: []const T, msg: ?[]const u8) !void {
        for (container) |c| {
            if (c == item) return;
        }
        const message = msg orelse "assertIn failed";
        try self.failures.append(self.allocator, message);
        return error.AssertionFailed;
    }

    /// assertNotIn - assert item is not in container
    pub fn assertNotIn(self: *Self, comptime T: type, item: T, container: []const T, msg: ?[]const u8) !void {
        for (container) |c| {
            if (c == item) {
                const message = msg orelse "assertNotIn failed";
                try self.failures.append(self.allocator,self.allocator, message);
                return error.AssertionFailed;
            }
        }
    }

    /// assertGreater - assert a > b
    pub fn assertGreater(self: *Self, comptime T: type, a: T, b: T, msg: ?[]const u8) !void {
        if (a <= b) {
            const message = msg orelse "assertGreater failed";
            try self.failures.append(self.allocator,self.allocator, message);
            return error.AssertionFailed;
        }
    }

    /// assertGreaterEqual - assert a >= b
    pub fn assertGreaterEqual(self: *Self, comptime T: type, a: T, b: T, msg: ?[]const u8) !void {
        if (a < b) {
            const message = msg orelse "assertGreaterEqual failed";
            try self.failures.append(self.allocator,self.allocator, message);
            return error.AssertionFailed;
        }
    }

    /// assertLess - assert a < b
    pub fn assertLess(self: *Self, comptime T: type, a: T, b: T, msg: ?[]const u8) !void {
        if (a >= b) {
            const message = msg orelse "assertLess failed";
            try self.failures.append(self.allocator,self.allocator, message);
            return error.AssertionFailed;
        }
    }

    /// assertLessEqual - assert a <= b
    pub fn assertLessEqual(self: *Self, comptime T: type, a: T, b: T, msg: ?[]const u8) !void {
        if (a > b) {
            const message = msg orelse "assertLessEqual failed";
            try self.failures.append(self.allocator,self.allocator, message);
            return error.AssertionFailed;
        }
    }

    /// assertAlmostEqual - assert floats are approximately equal
    pub fn assertAlmostEqual(self: *Self, actual: f64, expected: f64, places: u8, msg: ?[]const u8) !void {
        const tolerance = std.math.pow(f64, 10.0, -@as(f64, @floatFromInt(places)));
        if (@abs(actual - expected) > tolerance) {
            const message = msg orelse "assertAlmostEqual failed";
            try self.failures.append(self.allocator,self.allocator, message);
            return error.AssertionFailed;
        }
    }

    /// skip - skip the test with reason
    pub fn skip(self: *Self, reason: []const u8) void {
        self.skipped = true;
        self.skip_reason = reason;
    }

    /// fail - explicitly fail the test
    pub fn fail(self: *Self, msg: []const u8) !void {
        try self.failures.append(self.allocator, msg);
        return error.AssertionFailed;
    }

    /// Run a test method
    pub fn run(self: *Self, test_fn: *const fn (*Self) anyerror!void) AssertResult {
        // setUp
        self.setUp() catch |err| {
            return .{ .error_ = err };
        };

        // Run test
        test_fn(self) catch |err| {
            if (err == error.AssertionFailed) {
                const msg = if (self.failures.items.len > 0)
                    self.failures.items[self.failures.items.len - 1]
                else
                    "Assertion failed";
                return .{ .fail = msg };
            }
            return .{ .error_ = err };
        };

        // tearDown
        self.tearDown() catch |err| {
            return .{ .error_ = err };
        };

        if (self.skipped) {
            return .{ .skip = self.skip_reason orelse "skipped" };
        }

        return .pass;
    }
};

/// Skip decorator equivalent
pub fn skipTest(reason: []const u8) error{SkipTest}!void {
    _ = reason;
    return error.SkipTest;
}

/// Skip if condition
pub fn skipIf(condition: bool, reason: []const u8) error{SkipTest}!void {
    if (condition) {
        return skipTest(reason);
    }
}

/// Skip unless condition
pub fn skipUnless(condition: bool, reason: []const u8) error{SkipTest}!void {
    if (!condition) {
        return skipTest(reason);
    }
}

/// Expected failure decorator equivalent
pub fn expectedFailure(test_fn: anytype) @TypeOf(test_fn) {
    return test_fn;
}
