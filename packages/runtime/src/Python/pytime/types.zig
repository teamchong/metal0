/// Time Types
/// Core time representations and structures

const constants = @import("constants.zig");

/// Time represented in nanoseconds (internal representation)
pub const PyTime = i64;

/// Timespec structure (seconds + nanoseconds)
pub const Timespec = struct {
    tv_sec: i64,
    tv_nsec: i64,

    pub fn toNanos(self: Timespec) i64 {
        return self.tv_sec * constants.NS_PER_SEC + self.tv_nsec;
    }

    pub fn fromNanos(nanos: i64) Timespec {
        return .{
            .tv_sec = @divFloor(nanos, constants.NS_PER_SEC),
            .tv_nsec = @mod(nanos, constants.NS_PER_SEC),
        };
    }
};

/// Timeval structure (seconds + microseconds)
pub const Timeval = struct {
    tv_sec: i64,
    tv_usec: i64,

    pub fn toNanos(self: Timeval) i64 {
        return self.tv_sec * constants.NS_PER_SEC + self.tv_usec * constants.NS_PER_US;
    }

    pub fn fromNanos(nanos: i64) Timeval {
        return .{
            .tv_sec = @divFloor(nanos, constants.NS_PER_SEC),
            .tv_usec = @divFloor(@mod(nanos, constants.NS_PER_SEC), constants.NS_PER_US),
        };
    }
};

/// Rounding mode for time conversions
pub const RoundMode = enum {
    floor, // Round towards negative infinity
    ceiling, // Round towards positive infinity
    half_even, // Round to nearest, ties to even (banker's rounding)
    up, // Round away from zero
    down, // Round towards zero
};

/// Broken down time structure
pub const BrokenDownTime = struct {
    year: i32, // Year (e.g., 2024)
    month: u4, // Month (1-12)
    day: u5, // Day of month (1-31)
    hour: u5, // Hour (0-23)
    minute: u6, // Minute (0-59)
    second: u6, // Second (0-59)
    weekday: u3, // Day of week (0=Monday, 6=Sunday)
    yearday: u9, // Day of year (1-366)
    is_dst: ?bool, // Daylight saving time flag

    /// Get ISO weekday (1=Monday, 7=Sunday)
    pub fn isoWeekday(self: BrokenDownTime) u3 {
        return self.weekday + 1;
    }
};

/// Clock info structure (matches Python's time.get_clock_info)
pub const ClockInfo = struct {
    name: []const u8,
    implementation: []const u8,
    monotonic: bool,
    adjustable: bool,
    resolution: f64, // in seconds
};
