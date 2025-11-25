/// PyAOT unittest runner - test result tracking and lifecycle
const std = @import("std");

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
pub var global_result: ?*TestResult = null;
pub var global_allocator: ?std.mem.Allocator = null;

/// Initialize test runner
pub fn initRunner(allocator: std.mem.Allocator) !*TestResult {
    const result = try allocator.create(TestResult);
    result.* = TestResult.init(allocator);
    global_result = result;
    global_allocator = allocator;
    return result;
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
pub fn main(allocator: std.mem.Allocator) !void {
    _ = try initRunner(allocator);
}

/// Finalize and print results - called after all tests run
pub fn finalize() void {
    printResults();
    deinitRunner();
}
