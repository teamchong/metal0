//! test.test_unittest - Unit testing framework tests
const std = @import("std");

pub const TestCase = struct {
    name: []const u8,
    setUp_fn: ?*const fn (*@This()) void = null,
    tearDown_fn: ?*const fn (*@This()) void = null,
    
    failures: std.ArrayList(Failure),
    errors: std.ArrayList(Error),
    allocator: std.mem.Allocator,
    
    pub const Failure = struct { test_name: []const u8, message: []const u8 };
    pub const Error = struct { test_name: []const u8, err: anyerror };
    
    pub fn init(allocator: std.mem.Allocator, name: []const u8) @This() {
        return .{
            .allocator = allocator,
            .name = name,
            .failures = std.ArrayList(Failure).init(allocator),
            .errors = std.ArrayList(Error).init(allocator),
        };
    }
    
    pub fn deinit(self: *@This()) void {
        self.failures.deinit();
        self.errors.deinit();
    }
    
    pub fn setUp(self: *@This()) void {
        if (self.setUp_fn) |f| f(self);
    }
    
    pub fn tearDown(self: *@This()) void {
        if (self.tearDown_fn) |f| f(self);
    }
    
    pub fn assertEqual(self: *@This(), expected: anytype, actual: anytype) !void {
        if (expected != actual) {
            try self.failures.append(.{ .test_name = self.name, .message = "assertEqual failed" });
            return error.AssertionFailed;
        }
    }
    
    pub fn assertTrue(self: *@This(), value: bool) !void {
        if (!value) {
            try self.failures.append(.{ .test_name = self.name, .message = "assertTrue failed" });
            return error.AssertionFailed;
        }
    }
    
    pub fn assertFalse(self: *@This(), value: bool) !void {
        if (value) {
            try self.failures.append(.{ .test_name = self.name, .message = "assertFalse failed" });
            return error.AssertionFailed;
        }
    }
    
    pub fn wasSuccessful(self: *@This()) bool {
        return self.failures.items.len == 0 and self.errors.items.len == 0;
    }
};

pub const TestSuite = struct {
    tests: std.ArrayList(*TestCase),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator, .tests = std.ArrayList(*TestCase).init(allocator) };
    }
    
    pub fn deinit(self: *@This()) void {
        self.tests.deinit();
    }
    
    pub fn addTest(self: *@This(), test_case: *TestCase) !void {
        try self.tests.append(test_case);
    }
    
    pub fn countTests(self: *@This()) usize {
        return self.tests.items.len;
    }
};

pub const TestResult = struct {
    tests_run: usize = 0,
    failures: usize = 0,
    errors: usize = 0,
    skipped: usize = 0,
    
    pub fn wasSuccessful(self: @This()) bool {
        return self.failures == 0 and self.errors == 0;
    }
};

pub const TestRunner = struct {
    verbosity: u8 = 1,
    
    pub fn run(self: @This(), suite: *TestSuite) TestResult {
        _ = self;
        var result = TestResult{};
        for (suite.tests.items) |tc| {
            tc.setUp();
            result.tests_run += 1;
            if (!tc.wasSuccessful()) {
                result.failures += tc.failures.items.len;
                result.errors += tc.errors.items.len;
            }
            tc.tearDown();
        }
        return result;
    }
};

test "test_case_init" {
    var tc = TestCase.init(std.testing.allocator, "test_example");
    defer tc.deinit();
    try std.testing.expectEqualStrings("test_example", tc.name);
}

test "test_case_assert" {
    var tc = TestCase.init(std.testing.allocator, "test_assert");
    defer tc.deinit();
    try tc.assertEqual(@as(i32, 1), @as(i32, 1));
    try tc.assertTrue(true);
    try tc.assertFalse(false);
    try std.testing.expect(tc.wasSuccessful());
}

test "test_suite" {
    var suite = TestSuite.init(std.testing.allocator);
    defer suite.deinit();
    try std.testing.expectEqual(@as(usize, 0), suite.countTests());
}

test "test_result" {
    const result = TestResult{ .tests_run = 5, .failures = 0, .errors = 0 };
    try std.testing.expect(result.wasSuccessful());
}
