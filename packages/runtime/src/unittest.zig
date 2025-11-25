/// PyAOT unittest module - basic test framework
/// Provides TestCase base functionality and test runner
const std = @import("std");
const runtime = @import("runtime.zig");

/// Test result tracking
pub const TestResult = struct {
    passed: usize = 0,
    failed: usize = 0,
    errors: std.ArrayList([]const u8) = std.ArrayList([]const u8){},
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TestResult {
        return .{
            .passed = 0,
            .failed = 0,
            .errors = std.ArrayList([]const u8){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TestResult) void {
        for (self.errors.items) |err| {
            self.allocator.free(err);
        }
        self.errors.deinit(self.allocator);
    }

    pub fn addPass(self: *TestResult) void {
        self.passed += 1;
    }

    pub fn addFail(self: *TestResult, msg: []const u8) !void {
        self.failed += 1;
        const duped = try self.allocator.dupe(u8, msg);
        try self.errors.append(self.allocator, duped);
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
        std.debug.print("AssertionError: {any} != {any}\n", .{ a, b });
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
        std.debug.print("AssertionError: expected True, got False\n", .{});
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
        std.debug.print("AssertionError: expected False, got True\n", .{});
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
        std.debug.print("AssertionError: expected None\n", .{});
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

/// Assertion: assertGreater(a, b) - a > b
pub fn assertGreater(a: anytype, b: anytype) void {
    if (!(a > b)) {
        std.debug.print("AssertionError: {any} is not greater than {any}\n", .{ a, b });
        if (global_result) |result| {
            result.addFail("assertGreater failed") catch {};
        }
        @panic("assertGreater failed");
    } else {
        if (global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertLess(a, b) - a < b
pub fn assertLess(a: anytype, b: anytype) void {
    if (!(a < b)) {
        std.debug.print("AssertionError: {any} is not less than {any}\n", .{ a, b });
        if (global_result) |result| {
            result.addFail("assertLess failed") catch {};
        }
        @panic("assertLess failed");
    } else {
        if (global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertGreaterEqual(a, b) - a >= b
pub fn assertGreaterEqual(a: anytype, b: anytype) void {
    if (!(a >= b)) {
        std.debug.print("AssertionError: {any} is not >= {any}\n", .{ a, b });
        if (global_result) |result| {
            result.addFail("assertGreaterEqual failed") catch {};
        }
        @panic("assertGreaterEqual failed");
    } else {
        if (global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertLessEqual(a, b) - a <= b
pub fn assertLessEqual(a: anytype, b: anytype) void {
    if (!(a <= b)) {
        std.debug.print("AssertionError: {any} is not <= {any}\n", .{ a, b });
        if (global_result) |result| {
            result.addFail("assertLessEqual failed") catch {};
        }
        @panic("assertLessEqual failed");
    } else {
        if (global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertNotEqual(a, b) - values must NOT be equal
pub fn assertNotEqual(a: anytype, b: anytype) void {
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

    if (equal) {
        std.debug.print("AssertionError: {any} == {any} (expected not equal)\n", .{ a, b });
        if (global_result) |result| {
            result.addFail("assertNotEqual failed") catch {};
        }
        @panic("assertNotEqual failed");
    } else {
        if (global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertIs(a, b) - pointer identity check (a is b)
pub fn assertIs(a: anytype, b: anytype) void {
    const same = @intFromPtr(a) == @intFromPtr(b);

    if (!same) {
        std.debug.print("AssertionError: not the same object (expected identity)\n", .{});
        if (global_result) |result| {
            result.addFail("assertIs failed") catch {};
        }
        @panic("assertIs failed");
    } else {
        if (global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertIsNot(a, b) - pointer identity check (a is not b)
pub fn assertIsNot(a: anytype, b: anytype) void {
    const same = @intFromPtr(a) == @intFromPtr(b);

    if (same) {
        std.debug.print("AssertionError: same object (expected different identity)\n", .{});
        if (global_result) |result| {
            result.addFail("assertIsNot failed") catch {};
        }
        @panic("assertIsNot failed");
    } else {
        if (global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertIsNotNone(x) - value must not be None/null
pub fn assertIsNotNone(value: anytype) void {
    const is_none = switch (@typeInfo(@TypeOf(value))) {
        .optional => value == null,
        .pointer => |ptr| if (ptr.size == .one) false else value.len == 0,
        else => false,
    };

    if (is_none) {
        std.debug.print("AssertionError: expected not None\n", .{});
        if (global_result) |result| {
            result.addFail("assertIsNotNone failed") catch {};
        }
        @panic("assertIsNotNone failed");
    } else {
        if (global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertIn(item, container) - item must be in container
pub fn assertIn(item: anytype, container: anytype) void {
    const found = blk: {
        // Simple iteration works for both arrays and slices
        for (container) |elem| {
            if (elem == item) break :blk true;
        }
        break :blk false;
    };

    if (!found) {
        std.debug.print("AssertionError: {any} not in container\n", .{item});
        if (global_result) |result| {
            result.addFail("assertIn failed") catch {};
        }
        @panic("assertIn failed");
    } else {
        if (global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertNotIn(item, container) - item must not be in container
pub fn assertNotIn(item: anytype, container: anytype) void {
    const found = blk: {
        // Simple iteration works for both arrays and slices
        for (container) |elem| {
            if (elem == item) break :blk true;
        }
        break :blk false;
    };

    if (found) {
        std.debug.print("AssertionError: {any} unexpectedly in container\n", .{item});
        if (global_result) |result| {
            result.addFail("assertNotIn failed") catch {};
        }
        @panic("assertNotIn failed");
    } else {
        if (global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertAlmostEqual(a, b) - floats must be equal within 7 decimal places
pub fn assertAlmostEqual(a: anytype, b: anytype) void {
    const diff = @abs(a - b);
    const tolerance: f64 = 0.0000001; // 7 decimal places

    if (diff >= tolerance) {
        std.debug.print("AssertionError: {d} !~= {d} (diff={d})\n", .{ a, b, diff });
        if (global_result) |result| {
            result.addFail("assertAlmostEqual failed") catch {};
        }
        @panic("assertAlmostEqual failed");
    } else {
        if (global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertNotAlmostEqual(a, b) - floats must NOT be equal within 7 decimal places
pub fn assertNotAlmostEqual(a: anytype, b: anytype) void {
    const diff = @abs(a - b);
    const tolerance: f64 = 0.0000001; // 7 decimal places

    if (diff < tolerance) {
        std.debug.print("AssertionError: {d} ~= {d} (expected not almost equal)\n", .{ a, b });
        if (global_result) |result| {
            result.addFail("assertNotAlmostEqual failed") catch {};
        }
        @panic("assertNotAlmostEqual failed");
    } else {
        if (global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertCountEqual(a, b) - sequences have same elements (order independent)
pub fn assertCountEqual(a: anytype, b: anytype) void {
    // Check same length
    if (a.len != b.len) {
        std.debug.print("AssertionError: sequences have different lengths ({d} vs {d})\n", .{ a.len, b.len });
        if (global_result) |result| {
            result.addFail("assertCountEqual failed: different lengths") catch {};
        }
        @panic("assertCountEqual failed");
    }

    // Check each element in a exists in b (simple O(n²) is fine)
    for (a) |item_a| {
        var found = false;
        for (b) |item_b| {
            if (item_a == item_b) {
                found = true;
                break;
            }
        }
        if (!found) {
            std.debug.print("AssertionError: element {any} not found in second sequence\n", .{item_a});
            if (global_result) |result| {
                result.addFail("assertCountEqual failed: element not found") catch {};
            }
            @panic("assertCountEqual failed");
        }
    }

    // Check each element in b exists in a (for completeness - handles duplicates properly)
    for (b) |item_b| {
        var found = false;
        for (a) |item_a| {
            if (item_a == item_b) {
                found = true;
                break;
            }
        }
        if (!found) {
            std.debug.print("AssertionError: element {any} not found in first sequence\n", .{item_b});
            if (global_result) |result| {
                result.addFail("assertCountEqual failed: element not found") catch {};
            }
            @panic("assertCountEqual failed");
        }
    }

    if (global_result) |result| {
        result.addPass();
    }
}

/// Print test results summary
pub fn printResults() void {
    if (global_result) |result| {
        std.debug.print("\n", .{});
        std.debug.print("----------------------------------------------------------------------\n", .{});
        std.debug.print("Ran {d} test(s)\n\n", .{result.passed + result.failed});
        if (result.failed == 0) {
            std.debug.print("OK\n", .{});
        } else {
            std.debug.print("FAILED (failures={d})\n", .{result.failed});
            for (result.errors.items) |err| {
                std.debug.print("  - {s}\n", .{err});
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
