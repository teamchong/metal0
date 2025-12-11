/// Thread switching and check interval for ceval
/// Mirrors part of cpython/Python/ceval.c
const std = @import("std");

/// Check interval for signal/thread switching
var check_interval: i32 = 100;

/// Switch interval in microseconds (default 5ms)
var switch_interval: u64 = 5000;

/// Ticker for periodic checks
var ticker: i32 = 0;

/// Set check interval
pub fn setCheckInterval(interval: i32) void {
    check_interval = interval;
}

/// Get check interval
pub fn getCheckInterval() i32 {
    return check_interval;
}

/// Check ticker and handle thread switching
pub fn checkTicker() bool {
    ticker -= 1;
    if (ticker <= 0) {
        ticker = check_interval;
        return true;
    }
    return false;
}
