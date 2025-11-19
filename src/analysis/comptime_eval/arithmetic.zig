/// Arithmetic operations for compile-time evaluation
const std = @import("std");
const core = @import("core.zig");
const ComptimeValue = core.ComptimeValue;

pub fn evalAdd(allocator: std.mem.Allocator, left: ComptimeValue, right: ComptimeValue) ?ComptimeValue {
    return switch (left) {
        .int => |l| switch (right) {
            .int => |r| blk: {
                const result = @addWithOverflow(l, r);
                if (result[1] != 0) break :blk null;
                break :blk ComptimeValue{ .int = result[0] };
            },
            .float => |r| ComptimeValue{ .float = @as(f64, @floatFromInt(l)) + r },
            else => null,
        },
        .float => |l| switch (right) {
            .int => |r| ComptimeValue{ .float = l + @as(f64, @floatFromInt(r)) },
            .float => |r| ComptimeValue{ .float = l + r },
            else => null,
        },
        .string => |l| switch (right) {
            .string => |r| blk: {
                const result = std.mem.concat(allocator, u8, &[_][]const u8{ l, r }) catch return null;
                break :blk ComptimeValue{ .string = result };
            },
            else => null,
        },
        else => null,
    };
}

pub fn evalSub(_: std.mem.Allocator, left: ComptimeValue, right: ComptimeValue) ?ComptimeValue {
    return switch (left) {
        .int => |l| switch (right) {
            .int => |r| blk: {
                const result = @subWithOverflow(l, r);
                if (result[1] != 0) break :blk null;
                break :blk ComptimeValue{ .int = result[0] };
            },
            .float => |r| ComptimeValue{ .float = @as(f64, @floatFromInt(l)) - r },
            else => null,
        },
        .float => |l| switch (right) {
            .int => |r| ComptimeValue{ .float = l - @as(f64, @floatFromInt(r)) },
            .float => |r| ComptimeValue{ .float = l - r },
            else => null,
        },
        else => null,
    };
}

pub fn evalMul(allocator: std.mem.Allocator, left: ComptimeValue, right: ComptimeValue) ?ComptimeValue {
    return switch (left) {
        .int => |l| switch (right) {
            .int => |r| blk: {
                const result = @mulWithOverflow(l, r);
                if (result[1] != 0) break :blk null;
                break :blk ComptimeValue{ .int = result[0] };
            },
            .float => |r| ComptimeValue{ .float = @as(f64, @floatFromInt(l)) * r },
            else => null,
        },
        .float => |l| switch (right) {
            .int => |r| ComptimeValue{ .float = l * @as(f64, @floatFromInt(r)) },
            .float => |r| ComptimeValue{ .float = l * r },
            else => null,
        },
        .string => |l| switch (right) {
            .int => |r| blk: {
                if (r < 0 or r > 10000) break :blk null;
                if (r == 0) break :blk ComptimeValue{ .string = "" };
                const result = allocator.alloc(u8, l.len * @as(usize, @intCast(r))) catch return null;
                var i: usize = 0;
                while (i < r) : (i += 1) {
                    @memcpy(result[i * l.len .. (i + 1) * l.len], l);
                }
                break :blk ComptimeValue{ .string = result };
            },
            else => null,
        },
        else => null,
    };
}

pub fn evalDiv(_: std.mem.Allocator, left: ComptimeValue, right: ComptimeValue) ?ComptimeValue {
    return switch (left) {
        .int => |l| switch (right) {
            .int => |r| blk: {
                if (r == 0) break :blk null;
                break :blk ComptimeValue{ .float = @as(f64, @floatFromInt(l)) / @as(f64, @floatFromInt(r)) };
            },
            .float => |r| blk: {
                if (r == 0.0) break :blk null;
                break :blk ComptimeValue{ .float = @as(f64, @floatFromInt(l)) / r };
            },
            else => null,
        },
        .float => |l| switch (right) {
            .int => |r| blk: {
                if (r == 0) break :blk null;
                break :blk ComptimeValue{ .float = l / @as(f64, @floatFromInt(r)) };
            },
            .float => |r| blk: {
                if (r == 0.0) break :blk null;
                break :blk ComptimeValue{ .float = l / r };
            },
            else => null,
        },
        else => null,
    };
}

pub fn evalFloorDiv(_: std.mem.Allocator, left: ComptimeValue, right: ComptimeValue) ?ComptimeValue {
    return switch (left) {
        .int => |l| switch (right) {
            .int => |r| blk: {
                if (r == 0) break :blk null;
                break :blk ComptimeValue{ .int = @divFloor(l, r) };
            },
            .float => |r| blk: {
                if (r == 0.0) break :blk null;
                break :blk ComptimeValue{ .float = @floor(@as(f64, @floatFromInt(l)) / r) };
            },
            else => null,
        },
        .float => |l| switch (right) {
            .int => |r| blk: {
                if (r == 0) break :blk null;
                break :blk ComptimeValue{ .float = @floor(l / @as(f64, @floatFromInt(r))) };
            },
            .float => |r| blk: {
                if (r == 0.0) break :blk null;
                break :blk ComptimeValue{ .float = @floor(l / r) };
            },
            else => null,
        },
        else => null,
    };
}

pub fn evalMod(_: std.mem.Allocator, left: ComptimeValue, right: ComptimeValue) ?ComptimeValue {
    return switch (left) {
        .int => |l| switch (right) {
            .int => |r| blk: {
                if (r == 0) break :blk null;
                break :blk ComptimeValue{ .int = @mod(l, r) };
            },
            else => null,
        },
        else => null,
    };
}

pub fn evalPow(_: std.mem.Allocator, left: ComptimeValue, right: ComptimeValue) ?ComptimeValue {
    return switch (left) {
        .int => |l| switch (right) {
            .int => |r| blk: {
                if (r < 0 or r > 100) break :blk null;
                var result: i64 = 1;
                var i: i64 = 0;
                while (i < r) : (i += 1) {
                    const mul_result = @mulWithOverflow(result, l);
                    if (mul_result[1] != 0) break :blk null;
                    result = mul_result[0];
                }
                break :blk ComptimeValue{ .int = result };
            },
            .float => |r| ComptimeValue{ .float = std.math.pow(f64, @as(f64, @floatFromInt(l)), r) },
            else => null,
        },
        .float => |l| switch (right) {
            .int => |r| ComptimeValue{ .float = std.math.pow(f64, l, @as(f64, @floatFromInt(r))) },
            .float => |r| ComptimeValue{ .float = std.math.pow(f64, l, r) },
            else => null,
        },
        else => null,
    };
}

pub fn evalBitAnd(_: std.mem.Allocator, left: ComptimeValue, right: ComptimeValue) ?ComptimeValue {
    return switch (left) {
        .int => |l| switch (right) {
            .int => |r| ComptimeValue{ .int = l & r },
            else => null,
        },
        else => null,
    };
}

pub fn evalBitOr(_: std.mem.Allocator, left: ComptimeValue, right: ComptimeValue) ?ComptimeValue {
    return switch (left) {
        .int => |l| switch (right) {
            .int => |r| ComptimeValue{ .int = l | r },
            else => null,
        },
        else => null,
    };
}

pub fn evalBitXor(_: std.mem.Allocator, left: ComptimeValue, right: ComptimeValue) ?ComptimeValue {
    return switch (left) {
        .int => |l| switch (right) {
            .int => |r| ComptimeValue{ .int = l ^ r },
            else => null,
        },
        else => null,
    };
}
