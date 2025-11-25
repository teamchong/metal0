/// PyAOT unittest module - basic test framework
/// Provides TestCase base functionality and test runner
const std = @import("std");
const runtime = @import("runtime.zig");

/// Test result tracking
pub const TestResult = struct {
    passed: usize = 0,
    failed: usize = 0,
    errors: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TestResult {
        return .{
            .passed = 0,
            .failed = 0,
            .errors = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TestResult) void {
        for (self.errors.items) |err| {
            self.allocator.free(err);
        }
        self.errors.deinit();
    }

    pub fn addPass(self: *TestResult) void {
        self.passed += 1;
    }

    pub fn addFail(self: *TestResult, msg: []const u8) !void {
        self.failed += 1;
        const duped = try self.allocator.dupe(u8, msg);
        try self.errors.append(duped);
    }
};

/// Global test result for current test run
var global_result: ?*TestResult = null;
var global_allocator: ?std.mem.Allocator = null;

/// Initialize test runner
pub fn initRunner(allocator: std.mem.Allocator) !*TestResult {
    const result = try allocator.create(TestResult);
    result.* = TestResult.init(allocator);
    global_result = result;
    global_allocator = allocator;
    return result;
}

/// Assertion: assertEqual(a, b) - values must be equal
pub fn assertEqual(a: anytype, b: anytype) void {
    const equal = switch (@typeInfo(@TypeOf(a))) {
        .int, .comptime_int => a == b,
        .float, .comptime_float => @abs(a - b) < 0.0001,
        .bool => a == b,
        .pointer => |ptr| blk: {
            if (ptr.size == .slice) {
                // String/slice comparison
                break :blk std.mem.eql(u8, a, b);
            }
            break :blk a == b;
        },
        else => a == b,
    };

    if (!equal) {
        const writer = std.io.getStdErr().writer();
        writer.print("AssertionError: {any} != {any}\n", .{ a, b }) catch {};
        if (global_result) |result| {
            result.addFail("assertEqual failed") catch {};
        }
        @panic("assertEqual failed");
    } else {
        if (global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertTrue(x) - value must be true
pub fn assertTrue(value: bool) void {
    if (!value) {
        const writer = std.io.getStdErr().writer();
        writer.print("AssertionError: expected True, got False\n", .{}) catch {};
        if (global_result) |result| {
            result.addFail("assertTrue failed") catch {};
        }
        @panic("assertTrue failed");
    } else {
        if (global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertFalse(x) - value must be false
pub fn assertFalse(value: bool) void {
    if (value) {
        const writer = std.io.getStdErr().writer();
        writer.print("AssertionError: expected False, got True\n", .{}) catch {};
        if (global_result) |result| {
            result.addFail("assertFalse failed") catch {};
        }
        @panic("assertFalse failed");
    } else {
        if (global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertIsNone(x) - value must be None/null
pub fn assertIsNone(value: anytype) void {
    const is_none = switch (@typeInfo(@TypeOf(value))) {
        .optional => value == null,
        .pointer => |ptr| if (ptr.size == .one) false else value.len == 0,
        else => false,
    };

    if (!is_none) {
        const writer = std.io.getStdErr().writer();
        writer.print("AssertionError: expected None\n", .{}) catch {};
        if (global_result) |result| {
            result.addFail("assertIsNone failed") catch {};
        }
        @panic("assertIsNone failed");
    } else {
        if (global_result) |result| {
            result.addPass();
        }
    }
}

/// Print test results summary
pub fn printResults() void {
    if (global_result) |result| {
        const writer = std.io.getStdOut().writer();
        writer.print("\n", .{}) catch {};
        writer.print("----------------------------------------------------------------------\n", .{}) catch {};
        writer.print("Ran {d} test(s)\n\n", .{result.passed + result.failed}) catch {};
        if (result.failed == 0) {
            writer.print("OK\n", .{}) catch {};
        } else {
            writer.print("FAILED (failures={d})\n", .{result.failed}) catch {};
            for (result.errors.items) |err| {
                writer.print("  - {s}\n", .{err}) catch {};
            }
        }
    }
}

/// Cleanup test runner
pub fn deinitRunner() void {
    if (global_result) |result| {
        if (global_allocator) |alloc| {
            result.deinit();
            alloc.destroy(result);
        }
    }
    global_result = null;
    global_allocator = null;
}

/// Main entry point - called by unittest.main()
/// This is a no-op stub; actual test execution is done via generated code
pub fn main(allocator: std.mem.Allocator) !void {
    _ = try initRunner(allocator);
    // Tests are run by generated code, this just initializes
}

/// Finalize and print results - called after all tests run
pub fn finalize() void {
    printResults();
    deinitRunner();
}

// Tests
test "assertEqual: integers" {
    assertEqual(@as(i64, 2 + 2), @as(i64, 4));
}

test "assertEqual: strings" {
    assertEqual("hello", "hello");
}

test "assertTrue" {
    assertTrue(true);
    assertTrue(1 == 1);
}

test "assertFalse" {
    assertFalse(false);
    assertFalse(1 == 2);
}
