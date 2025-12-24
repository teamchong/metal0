/// Float rounding operations (floor, ceil, trunc, round)
const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");
const bigint = @import("bigint");
const BigInt = bigint.BigInt;
const pyint = @import("../../Objects/pyint.zig");

/// Python error types
pub const PythonError = error{
    ZeroDivisionError,
    IndexError,
    ValueError,
    TypeError,
    KeyError,
    OverflowError,
    OutOfMemory,
    Exception,
};

/// Integer result type that can be either i64 or BigInt
pub const IntResult = union(enum) {
    small: i64,
    big: BigInt,

    pub fn toFloat(self: IntResult) f64 {
        return switch (self) {
            .small => |v| @floatFromInt(v),
            .big => |b| b.toFloat(),
        };
    }

    pub fn eqlFloat(self: IntResult, f: f64) bool {
        return self.toFloat() == f;
    }

    pub fn eqlInt(self: IntResult, other: i64) bool {
        return switch (self) {
            .small => |v| v == other,
            .big => false,
        };
    }

    pub fn asI64(self: IntResult) PythonError!i64 {
        return switch (self) {
            .small => |v| v,
            .big => PythonError.OverflowError,
        };
    }

    /// Convert to UnifiedInt (i64 or *BigInt)
    /// Unlike asI64(), this never throws - big values stay as BigInt pointers
    pub fn asUnifiedInt(self: *const IntResult, allocator: std.mem.Allocator) !pyint.UnifiedInt {
        return switch (self.*) {
            .small => |v| pyint.UnifiedInt{ .small = v },
            .big => |b| blk: {
                // Need to allocate BigInt on heap for UnifiedInt
                const heap_big = try allocator.create(BigInt);
                heap_big.* = b;
                break :blk pyint.UnifiedInt{ .big = heap_big };
            },
        };
    }

    pub fn format(self: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .small => |v| try writer.print("{d}", .{v}),
            .big => |b| try writer.print("{s}", .{b.toString(allocator_helper.fast_allocator) catch "BigInt"}),
        }
    }
};

/// Union type for floor/ceil that can return either i64 or f64
pub const FloorCeilResult = union(enum) {
    int: i64,
    float: f64,

    pub fn toFloat(self: FloorCeilResult) f64 {
        return switch (self) {
            .int => |v| @floatFromInt(v),
            .float => |v| v,
        };
    }

    pub fn format(self: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .int => |v| try writer.print("{d}", .{v}),
            .float => |v| try writer.print("{d}", .{v}),
        }
    }
};

/// float.__floor__() - Returns largest integer <= value
/// Returns i64 for small values, BigInt for large values
pub fn floatFloorBig(allocator: std.mem.Allocator, value: f64) anyerror!IntResult {
    if (std.math.isNan(value)) return PythonError.ValueError;
    if (std.math.isInf(value)) return PythonError.OverflowError;
    const floored = @floor(value);
    if (floored >= @as(f64, @floatFromInt(std.math.minInt(i64))) and
        floored <= @as(f64, @floatFromInt(std.math.maxInt(i64))))
    {
        return IntResult{ .small = @intFromFloat(floored) };
    }
    return IntResult{ .big = try BigInt.fromFloat(allocator, floored) };
}

/// float.__floor__() - Returns largest integer <= value
/// Returns i64 for small values, raises error for NaN/Inf
pub fn floatFloor(_: std.mem.Allocator, value: f64) PythonError!i64 {
    if (std.math.isNan(value)) return PythonError.ValueError;
    if (std.math.isInf(value)) return PythonError.OverflowError;
    const floored = @floor(value);
    if (floored >= @as(f64, @floatFromInt(std.math.minInt(i64))) and
        floored <= @as(f64, @floatFromInt(std.math.maxInt(i64))))
    {
        return @intFromFloat(floored);
    }
    return PythonError.OverflowError;
}

/// float.__floor__() that returns either i64 or f64 for very large values
pub fn floatFloorAny(_: std.mem.Allocator, value: f64) PythonError!FloorCeilResult {
    if (std.math.isNan(value)) return PythonError.ValueError;
    if (std.math.isInf(value)) return PythonError.OverflowError;
    const floored = @floor(value);
    if (floored >= @as(f64, @floatFromInt(std.math.minInt(i64))) and
        floored <= @as(f64, @floatFromInt(std.math.maxInt(i64))))
    {
        return FloorCeilResult{ .int = @intFromFloat(floored) };
    }
    return FloorCeilResult{ .float = floored };
}

/// float.__ceil__() - Returns smallest integer >= value
/// Returns i64 for small values, BigInt for large values
pub fn floatCeilBig(allocator: std.mem.Allocator, value: f64) anyerror!IntResult {
    if (std.math.isNan(value)) return PythonError.ValueError;
    if (std.math.isInf(value)) return PythonError.OverflowError;
    const ceiled = @ceil(value);
    if (ceiled >= @as(f64, @floatFromInt(std.math.minInt(i64))) and
        ceiled <= @as(f64, @floatFromInt(std.math.maxInt(i64))))
    {
        return IntResult{ .small = @intFromFloat(ceiled) };
    }
    return IntResult{ .big = try BigInt.fromFloat(allocator, ceiled) };
}

/// float.__ceil__() - Returns smallest integer >= value
/// Returns i64 for small values, raises error for NaN/Inf
pub fn floatCeil(_: std.mem.Allocator, value: f64) PythonError!i64 {
    if (std.math.isNan(value)) return PythonError.ValueError;
    if (std.math.isInf(value)) return PythonError.OverflowError;
    const ceiled = @ceil(value);
    if (ceiled >= @as(f64, @floatFromInt(std.math.minInt(i64))) and
        ceiled <= @as(f64, @floatFromInt(std.math.maxInt(i64))))
    {
        return @intFromFloat(ceiled);
    }
    return PythonError.OverflowError;
}

/// float.__ceil__() that returns either i64 or f64 for very large values
pub fn floatCeilAny(_: std.mem.Allocator, value: f64) PythonError!FloorCeilResult {
    if (std.math.isNan(value)) return PythonError.ValueError;
    if (std.math.isInf(value)) return PythonError.OverflowError;
    const ceiled = @ceil(value);
    if (ceiled >= @as(f64, @floatFromInt(std.math.minInt(i64))) and
        ceiled <= @as(f64, @floatFromInt(std.math.maxInt(i64))))
    {
        return FloorCeilResult{ .int = @intFromFloat(ceiled) };
    }
    return FloorCeilResult{ .float = ceiled };
}

/// float.__trunc__() - Truncate towards zero
pub fn floatTrunc(_: std.mem.Allocator, value: f64) PythonError!i64 {
    if (std.math.isNan(value)) return PythonError.ValueError;
    if (std.math.isInf(value)) return PythonError.OverflowError;
    const truncated = @trunc(value);
    if (truncated >= @as(f64, @floatFromInt(std.math.minInt(i64))) and
        truncated <= @as(f64, @floatFromInt(std.math.maxInt(i64))))
    {
        return @intFromFloat(truncated);
    }
    return PythonError.OverflowError;
}

/// float.__round__() - Round to nearest using Python's banker's rounding
pub fn floatRound(_: std.mem.Allocator, value: f64) PythonError!i64 {
    if (std.math.isNan(value)) return PythonError.ValueError;
    if (std.math.isInf(value)) return PythonError.OverflowError;

    const floored = @floor(value);
    const frac = value - floored;

    var rounded: f64 = undefined;
    if (frac < 0.5) {
        rounded = floored;
    } else if (frac > 0.5) {
        rounded = floored + 1.0;
    } else {
        const floored_int: i64 = @intFromFloat(floored);
        if (@mod(floored_int, 2) == 0) {
            rounded = floored;
        } else {
            rounded = floored + 1.0;
        }
    }

    if (rounded >= @as(f64, @floatFromInt(std.math.minInt(i64))) and
        rounded <= @as(f64, @floatFromInt(std.math.maxInt(i64))))
    {
        return @intFromFloat(rounded);
    }
    return PythonError.OverflowError;
}
