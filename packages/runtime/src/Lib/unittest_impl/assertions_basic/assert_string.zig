/// metal0 unittest assertions - string and float assertions
const std = @import("std");
const runner = @import("../../unittest/runner.zig");
const runtime = @import("../../../runtime.zig");
const PyValue = runtime.PyValue;

/// Assertion: assertStartsWith(text, prefix) - string must start with prefix
pub fn assertStartsWith(text: []const u8, prefix: []const u8) !void {
    if (!std.mem.startsWith(u8, text, prefix)) {
        std.debug.print("AssertionError: '{s}' does not start with '{s}'\n", .{ text, prefix });
        if (runner.global_result) |result| {
            result.addFail("assertStartsWith failed") catch {};
        }
        return error.AssertionFailed;
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertNotStartsWith(text, prefix) - string must not start with prefix
pub fn assertNotStartsWith(text: []const u8, prefix: []const u8) !void {
    if (std.mem.startsWith(u8, text, prefix)) {
        std.debug.print("AssertionError: '{s}' starts with '{s}'\n", .{ text, prefix });
        if (runner.global_result) |result| {
            result.addFail("assertNotStartsWith failed") catch {};
        }
        return error.AssertionFailed;
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertEndsWith(text, suffix) - string must end with suffix
pub fn assertEndsWith(text: []const u8, suffix: []const u8) !void {
    if (!std.mem.endsWith(u8, text, suffix)) {
        std.debug.print("AssertionError: '{s}' does not end with '{s}'\n", .{ text, suffix });
        if (runner.global_result) |result| {
            result.addFail("assertEndsWith failed") catch {};
        }
        return error.AssertionFailed;
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertAlmostEqual(a, b) - floats must be equal within 7 decimal places
pub fn assertAlmostEqual(a: anytype, b: anytype) !void {
    const diff = @abs(a - b);
    const tolerance: f64 = 0.0000001;

    if (diff >= tolerance) {
        std.debug.print("AssertionError: {d} !~= {d} (diff={d})\n", .{ a, b, diff });
        if (runner.global_result) |result| {
            result.addFail("assertAlmostEqual failed") catch {};
        }
        return error.AssertionFailed;
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertNotAlmostEqual(a, b) - floats must NOT be equal within 7 decimal places
pub fn assertNotAlmostEqual(a: anytype, b: anytype) !void {
    const diff = @abs(a - b);
    const tolerance: f64 = 0.0000001;

    if (diff < tolerance) {
        std.debug.print("AssertionError: {d} ~= {d} (expected not almost equal)\n", .{ a, b });
        if (runner.global_result) |result| {
            result.addFail("assertNotAlmostEqual failed") catch {};
        }
        return error.AssertionFailed;
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertFloatsAreIdentical(a, b) - floats must be identical (same value and same sign for zeros)
pub fn assertFloatsAreIdentical(a: f64, b: f64) !void {
    const a_bits = @as(u64, @bitCast(a));
    const b_bits = @as(u64, @bitCast(b));

    if (a_bits != b_bits) {
        std.debug.print("AssertionError: {d} is not identical to {d}\n", .{ a, b });
        if (runner.global_result) |result| {
            result.addFail("assertFloatsAreIdentical failed") catch {};
        }
        return error.AssertionFailed;
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

// =============================================================================
// PyValue-based assertions - NO ANYTYPE to avoid monomorphization explosion
// =============================================================================

/// Concrete PyValue equality check - no anytype, no monomorphization
pub fn pyValueEql(a: PyValue, b: PyValue) bool {
    return switch (a) {
        .int => |av| switch (b) {
            .int => |bv| av == bv,
            else => false,
        },
        .float => |av| switch (b) {
            .float => |bv| av == bv or (@as(u64, @bitCast(av)) == @as(u64, @bitCast(bv))),
            else => false,
        },
        .bool => |av| switch (b) {
            .bool => |bv| av == bv,
            else => false,
        },
        .string => |av| switch (b) {
            .string => |bv| std.mem.eql(u8, av, bv),
            else => false,
        },
        .none => b == .none,
        .list => |av| switch (b) {
            .list => |bv| blk: {
                if (av.len != bv.len) break :blk false;
                for (av, bv) |ae, be| {
                    if (!pyValueEql(ae, be)) break :blk false;
                }
                break :blk true;
            },
            else => false,
        },
        .tuple => |av| switch (b) {
            .tuple => |bv| blk: {
                if (av.len != bv.len) break :blk false;
                for (av, bv) |ae, be| {
                    if (!pyValueEql(ae, be)) break :blk false;
                }
                break :blk true;
            },
            else => false,
        },
        else => false,
    };
}

/// assertEqual using PyValue - converts both args to PyValue then compares
pub fn assertEqualPyValue(a: PyValue, b: PyValue) !void {
    if (pyValueEql(a, b)) {
        if (runner.global_result) |result| {
            result.addPass();
        }
    } else {
        std.debug.print("AssertionError: {any} != {any}\n", .{ a, b });
        if (runner.global_result) |result| {
            result.addFail("assertEqual failed") catch {};
        }
        return error.AssertionFailed;
    }
}

/// Convert any value to PyValue - small wrapper for codegen
pub fn toPyValue(value: anytype) PyValue {
    return PyValue.from(value);
}
