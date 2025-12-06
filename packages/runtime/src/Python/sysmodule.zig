/// sysmodule - sys Module Implementation
/// Mirrors cpython/Python/sysmodule.c
const std = @import("std");

/// Thread-local int_max_str_digits limit (default 4300 in CPython 3.11+)
var int_max_str_digits: i64 = 4300;

pub fn init() void {}

/// Exit the program with the given status code
pub fn exit(status: anytype) noreturn {
    const code: u8 = switch (@typeInfo(@TypeOf(status))) {
        .int, .comptime_int => @intCast(@min(255, @max(0, status))),
        .optional => if (status) |s| @intCast(@min(255, @max(0, s))) else 0,
        else => 0,
    };
    std.process.exit(code);
}

/// Get the maximum number of digits for int/str conversions
pub fn get_int_max_str_digits(_: anytype) !i64 {
    return int_max_str_digits;
}

/// Set the maximum number of digits for int/str conversions
pub fn set_int_max_str_digits(_: anytype, limit: i64) !void {
    if (limit != 0 and limit < 640) {
        return error.ValueError; // CPython minimum is 640
    }
    int_max_str_digits = limit;
}
