/// Sleep Functions
/// Thread sleep utilities with various time units

const std = @import("std");
const conversion = @import("conversion.zig");

/// Sleep for given nanoseconds
pub fn sleepNanos(nanos: i64) void {
    if (nanos <= 0) return;
    std.time.sleep(@intCast(nanos));
}

/// Sleep for given seconds (float)
pub fn sleepSeconds(seconds: f64) void {
    if (seconds <= 0) return;
    const nanos = conversion.secondsToNanos(seconds) catch return;
    sleepNanos(nanos);
}

/// Sleep for given milliseconds
pub fn sleepMillis(millis: i64) void {
    if (millis <= 0) return;
    const nanos = conversion.millisToNanos(millis) catch return;
    sleepNanos(nanos);
}
