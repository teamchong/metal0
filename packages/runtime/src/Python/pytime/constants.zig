/// Time Units and Constants
/// Provides standard time conversion constants and limits

const std = @import("std");

/// Nanoseconds per second
pub const NS_PER_SEC: i64 = 1_000_000_000;

/// Microseconds per second
pub const US_PER_SEC: i64 = 1_000_000;

/// Milliseconds per second
pub const MS_PER_SEC: i64 = 1_000;

/// Nanoseconds per millisecond
pub const NS_PER_MS: i64 = 1_000_000;

/// Nanoseconds per microsecond
pub const NS_PER_US: i64 = 1_000;

/// Maximum timestamp value (fits in i64 nanoseconds)
pub const TIME_MAX: i64 = std.math.maxInt(i64);

/// Minimum timestamp value
pub const TIME_MIN: i64 = std.math.minInt(i64);
