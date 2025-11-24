/// Time module - high-precision timing
const std = @import("std");
const runtime = @import("runtime.zig");

/// Get current time in seconds since epoch (float)
pub fn time() f64 {
    const ns = std.time.nanoTimestamp();
    return @as(f64, @floatFromInt(ns)) / 1_000_000_000.0;
}

/// Sleep for specified seconds
pub fn sleep(seconds: f64) void {
    const ns: u64 = @intFromFloat(seconds * 1_000_000_000.0);
    std.time.sleep(ns);
}

/// Sleep for specified seconds (PyObject version)
pub fn sleepPy(seconds_obj: *runtime.PyObject) !void {
    if (seconds_obj.type_id == .int) {
        const data: *runtime.PyInt = @ptrCast(@alignCast(seconds_obj.data));
        const seconds: f64 = @floatFromInt(data.value);
        sleep(seconds);
    } else if (seconds_obj.type_id == .float) {
        const data: *runtime.PyFloat = @ptrCast(@alignCast(seconds_obj.data));
        sleep(data.value);
    } else {
        return error.TypeError;
    }
}

/// Monotonic clock (for measuring durations)
pub fn monotonic() f64 {
    const ns = std.time.nanoTimestamp();
    return @as(f64, @floatFromInt(ns)) / 1_000_000_000.0;
}

/// Performance counter (highest resolution)
pub fn perf_counter() f64 {
    const ns = std.time.nanoTimestamp();
    return @as(f64, @floatFromInt(ns)) / 1_000_000_000.0;
}
