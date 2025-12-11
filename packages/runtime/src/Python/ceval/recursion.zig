/// Recursion limit checking for ceval
/// Mirrors part of cpython/Python/ceval.c
const std = @import("std");

/// Thread-local recursion depth
threadlocal var recursion_depth: i32 = 0;

/// Default recursion limit
var recursion_limit: i32 = 1000;

/// Enter recursive call
pub fn enterRecursiveCall(where: []const u8) !void {
    recursion_depth += 1;
    if (recursion_depth > recursion_limit) {
        recursion_depth -= 1;
        std.debug.print("RecursionError: maximum recursion depth exceeded{s}\n", .{where});
        return error.RecursionError;
    }
}

/// Leave recursive call
pub fn leaveRecursiveCall() void {
    if (recursion_depth > 0) {
        recursion_depth -= 1;
    }
}

/// Get current recursion depth
pub fn getRecursionDepth() i32 {
    return recursion_depth;
}

/// Set recursion limit
pub fn setRecursionLimit(limit: i32) !void {
    if (limit < 1) {
        return error.ValueError;
    }
    recursion_limit = limit;
}

/// Get recursion limit
pub fn getRecursionLimit() i32 {
    return recursion_limit;
}
