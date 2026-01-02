//! numpy.testing stub for metal0 AOT compilation
//!
//! Provides numpy testing assertion functions compatible with numpy.testing module.
//! These wrap and extend the metal0 unittest assertions for numpy-specific semantics.

const std = @import("std");
const runtime = @import("../runtime.zig");
const equality = @import("../runtime/equality.zig");

// ============================================================================
// Core assertion functions from numpy.testing
// ============================================================================

/// assert_(condition, msg="") - Assert that condition is true
pub fn assert_(condition: anytype, msg: []const u8) !void {
    const cond_bool = switch (@TypeOf(condition)) {
        bool => condition,
        else => blk: {
            // Handle PyValue or other types
            if (@TypeOf(condition) == runtime.PyValue) {
                break :blk condition.toBool();
            }
            break :blk condition != false;
        },
    };

    if (!cond_bool) {
        if (msg.len > 0) {
            std.debug.print("AssertionError: {s}\n", .{msg});
        } else {
            std.debug.print("AssertionError: assert_ failed\n", .{});
        }
        return error.AssertionError;
    }
}

/// assert_equal(actual, expected) - Assert two values are equal
pub fn assert_equal(actual: anytype, expected: anytype) !void {
    if (!equality.pyAnyEql(actual, expected)) {
        std.debug.print("AssertionError: Items are not equal:\n", .{});
        std.debug.print(" ACTUAL: {any}\n", .{actual});
        std.debug.print(" EXPECTED: {any}\n", .{expected});
        return error.AssertionError;
    }
}

/// assert_array_equal(x, y) - Assert two arrays are equal element-wise
pub fn assert_array_equal(x: anytype, y: anytype) !void {
    const X = @TypeOf(x);
    const Y = @TypeOf(y);
    const x_info = @typeInfo(X);
    const y_info = @typeInfo(Y);

    // Handle slices
    if (x_info == .pointer and x_info.pointer.size == .slice and
        y_info == .pointer and y_info.pointer.size == .slice)
    {
        if (x.len != y.len) {
            std.debug.print("AssertionError: Arrays have different lengths: {} vs {}\n", .{ x.len, y.len });
            return error.AssertionError;
        }
        for (x, y, 0..) |xi, yi, i| {
            if (!equality.pyAnyEql(xi, yi)) {
                std.debug.print("AssertionError: Arrays differ at index {}: {} != {}\n", .{ i, xi, yi });
                return error.AssertionError;
            }
        }
        return;
    }

    // Handle ArrayLists
    if (@hasField(X, "items") and @hasField(Y, "items")) {
        const x_items = x.items;
        const y_items = y.items;
        if (x_items.len != y_items.len) {
            std.debug.print("AssertionError: Arrays have different lengths: {} vs {}\n", .{ x_items.len, y_items.len });
            return error.AssertionError;
        }
        for (x_items, y_items, 0..) |xi, yi, i| {
            if (!equality.pyAnyEql(xi, yi)) {
                std.debug.print("AssertionError: Arrays differ at index {}: {} != {}\n", .{ i, xi, yi });
                return error.AssertionError;
            }
        }
        return;
    }

    // Fall back to direct comparison
    try assert_equal(x, y);
}

/// assert_almost_equal(actual, expected, decimal=7) - Assert values are equal to given precision
pub fn assert_almost_equal(actual: anytype, expected: anytype, decimal: i32) !void {
    const tolerance = std.math.pow(f64, 10.0, @as(f64, @floatFromInt(-decimal)));

    const actual_f: f64 = switch (@TypeOf(actual)) {
        f64, f32, f16 => @floatCast(actual),
        i64, i32, i16, i8, u64, u32, u16, u8 => @floatFromInt(actual),
        comptime_int => @floatFromInt(actual),
        comptime_float => actual,
        else => blk: {
            if (@TypeOf(actual) == runtime.PyValue) {
                break :blk actual.toFloat() orelse return error.TypeError;
            }
            return error.TypeError;
        },
    };

    const expected_f: f64 = switch (@TypeOf(expected)) {
        f64, f32, f16 => @floatCast(expected),
        i64, i32, i16, i8, u64, u32, u16, u8 => @floatFromInt(expected),
        comptime_int => @floatFromInt(expected),
        comptime_float => expected,
        else => blk: {
            if (@TypeOf(expected) == runtime.PyValue) {
                break :blk expected.toFloat() orelse return error.TypeError;
            }
            return error.TypeError;
        },
    };

    if (@abs(actual_f - expected_f) > tolerance) {
        std.debug.print("AssertionError: {} != {} to {} decimal places\n", .{ actual_f, expected_f, decimal });
        return error.AssertionError;
    }
}

/// assert_allclose(actual, expected, rtol=1e-7, atol=0) - Assert values are close within tolerance
pub fn assert_allclose(actual: anytype, expected: anytype, rtol: f64, atol: f64) !void {
    const actual_f: f64 = switch (@TypeOf(actual)) {
        f64, f32, f16 => @floatCast(actual),
        i64, i32, i16, i8, u64, u32, u16, u8 => @floatFromInt(actual),
        comptime_int => @floatFromInt(actual),
        comptime_float => actual,
        else => blk: {
            if (@TypeOf(actual) == runtime.PyValue) {
                break :blk actual.toFloat() orelse return error.TypeError;
            }
            return error.TypeError;
        },
    };

    const expected_f: f64 = switch (@TypeOf(expected)) {
        f64, f32, f16 => @floatCast(expected),
        i64, i32, i16, i8, u64, u32, u16, u8 => @floatFromInt(expected),
        comptime_int => @floatFromInt(expected),
        comptime_float => expected,
        else => blk: {
            if (@TypeOf(expected) == runtime.PyValue) {
                break :blk expected.toFloat() orelse return error.TypeError;
            }
            return error.TypeError;
        },
    };

    const tolerance = atol + rtol * @abs(expected_f);
    if (@abs(actual_f - expected_f) > tolerance) {
        std.debug.print("AssertionError: {} != {} (rtol={}, atol={})\n", .{ actual_f, expected_f, rtol, atol });
        return error.AssertionError;
    }
}

/// assert_string_equal(actual, expected) - Assert two strings are equal
pub fn assert_string_equal(actual: anytype, expected: anytype) !void {
    const actual_str = switch (@TypeOf(actual)) {
        []const u8 => actual,
        else => blk: {
            if (@TypeOf(actual) == runtime.PyValue) {
                break :blk actual.toString() orelse return error.TypeError;
            }
            return error.TypeError;
        },
    };

    const expected_str = switch (@TypeOf(expected)) {
        []const u8 => expected,
        else => blk: {
            if (@TypeOf(expected) == runtime.PyValue) {
                break :blk expected.toString() orelse return error.TypeError;
            }
            return error.TypeError;
        },
    };

    if (!std.mem.eql(u8, actual_str, expected_str)) {
        std.debug.print("AssertionError: Strings are not equal:\n", .{});
        std.debug.print(" ACTUAL: \"{s}\"\n", .{actual_str});
        std.debug.print(" EXPECTED: \"{s}\"\n", .{expected_str});
        return error.AssertionError;
    }
}

/// assert_raises - context manager placeholder (actual implementation via codegen)
pub fn assert_raises(comptime ExceptionType: type) type {
    return struct {
        caught: bool = false,

        const Self = @This();

        pub fn __enter__(self: *Self) *Self {
            return self;
        }

        pub fn __exit__(self: *Self, exc_type: ?type, _: anytype, _: anytype) bool {
            if (exc_type) |et| {
                if (et == ExceptionType) {
                    self.caught = true;
                    return true;
                }
            }
            return false;
        }
    };
}

// ============================================================================
// Module-level constants
// ============================================================================

/// TestCase import from unittest (re-export)
pub const TestCase = struct {};

/// Known failure exception
pub const KnownFailureException = error{KnownFailure};

/// Skip test exception
pub const SkipTest = error{SkipTest};

/// Ignore exception context manager
pub const IgnoreException = struct {
    pub fn __enter__(self: *@This()) *@This() {
        return self;
    }

    pub fn __exit__(_: *@This(), _: ?type, _: anytype, _: anytype) bool {
        return true; // Suppress all exceptions
    }
};

// ============================================================================
// Platform detection constants
// ============================================================================

pub const IS_PYPY = false;
pub const IS_PYSTON = false;
pub const IS_MUSL = false;
pub const IS_WASM = false;
pub const IS_64BIT = @sizeOf(usize) == 8;
pub const HAS_REFCOUNT = true;
pub const HAS_LAPACK64 = false;
pub const NOGIL_BUILD = false;
pub const IS_INSTALLED = true;
pub const IS_EDITABLE = false;
