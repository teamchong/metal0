/// Timedelta struct - represents datetime.timedelta

const std = @import("std");
const runtime = @import("../../runtime.zig");

/// Timedelta struct - represents datetime.timedelta
pub const Timedelta = struct {
    days: i64,
    seconds: i64,
    microseconds: i64,

    /// Create timedelta from days (most common usage)
    pub fn fromDays(days: i64) Timedelta {
        return Timedelta{
            .days = days,
            .seconds = 0,
            .microseconds = 0,
        };
    }

    /// Create timedelta with all components (basic)
    pub fn init(days: i64, seconds: i64, microseconds: i64) Timedelta {
        return normalize(days, seconds, microseconds);
    }

    /// Create timedelta with all Python parameters:
    /// timedelta(days=0, seconds=0, microseconds=0, milliseconds=0, minutes=0, hours=0, weeks=0)
    /// All arguments are converted to days, seconds, microseconds internally
    pub fn create(
        days: i64,
        seconds: i64,
        microseconds: i64,
        milliseconds: i64,
        minutes: i64,
        hours: i64,
        weeks: i64,
    ) Timedelta {
        // Convert everything to the base units
        const total_days = days + weeks * 7;
        const total_seconds = seconds + minutes * 60 + hours * 3600;
        const total_microseconds = microseconds + milliseconds * 1000;

        return normalize(total_days, total_seconds, total_microseconds);
    }

    /// Create from weeks
    pub fn fromWeeks(weeks: i64) Timedelta {
        return Timedelta{ .days = weeks * 7, .seconds = 0, .microseconds = 0 };
    }

    /// Create from hours
    pub fn fromHours(hours: i64) Timedelta {
        return normalize(0, hours * 3600, 0);
    }

    /// Create from minutes
    pub fn fromMinutes(minutes: i64) Timedelta {
        return normalize(0, minutes * 60, 0);
    }

    /// Create from seconds
    pub fn fromSeconds(seconds: i64) Timedelta {
        return normalize(0, seconds, 0);
    }

    /// Create from milliseconds
    pub fn fromMilliseconds(milliseconds: i64) Timedelta {
        return normalize(0, 0, milliseconds * 1000);
    }

    /// Total seconds in the timedelta
    pub fn totalSeconds(self: Timedelta) f64 {
        const day_secs: f64 = @floatFromInt(self.days * 86400);
        const secs: f64 = @floatFromInt(self.seconds);
        const usecs: f64 = @floatFromInt(self.microseconds);
        return day_secs + secs + usecs / 1_000_000.0;
    }

    /// Add two timedeltas
    pub fn add(self: Timedelta, other: Timedelta) Timedelta {
        return normalize(
            self.days + other.days,
            self.seconds + other.seconds,
            self.microseconds + other.microseconds,
        );
    }

    /// Subtract two timedeltas
    pub fn sub(self: Timedelta, other: Timedelta) Timedelta {
        return normalize(
            self.days - other.days,
            self.seconds - other.seconds,
            self.microseconds - other.microseconds,
        );
    }

    /// Multiply timedelta by integer
    pub fn mul(self: Timedelta, factor: i64) Timedelta {
        return normalize(
            self.days * factor,
            self.seconds * factor,
            self.microseconds * factor,
        );
    }

    /// Divide timedelta by integer (floor division)
    pub fn div(self: Timedelta, divisor: i64) Timedelta {
        const total_us = self.days * 86400 * 1_000_000 + self.seconds * 1_000_000 + self.microseconds;
        const result_us = @divFloor(total_us, divisor);
        return fromMicroseconds(result_us);
    }

    /// Negate timedelta
    pub fn neg(self: Timedelta) Timedelta {
        return Timedelta{
            .days = -self.days,
            .seconds = -self.seconds,
            .microseconds = -self.microseconds,
        };
    }

    /// Absolute value of timedelta
    pub fn abs(self: Timedelta) Timedelta {
        if (self.days < 0 or (self.days == 0 and self.seconds < 0) or
            (self.days == 0 and self.seconds == 0 and self.microseconds < 0))
        {
            return self.neg();
        }
        return self;
    }

    /// Create from total microseconds
    pub fn fromMicroseconds(us: i64) Timedelta {
        var remaining = us;
        const days = @divFloor(remaining, 86400 * 1_000_000);
        remaining = @mod(remaining, 86400 * 1_000_000);
        const seconds = @divFloor(remaining, 1_000_000);
        remaining = @mod(remaining, 1_000_000);
        return Timedelta{
            .days = days,
            .seconds = seconds,
            .microseconds = remaining,
        };
    }

    /// Normalize days/seconds/microseconds to standard ranges
    fn normalize(days: i64, seconds: i64, microseconds: i64) Timedelta {
        var d = days;
        var s = seconds;
        var us = microseconds;

        // Normalize microseconds (0 <= us < 1_000_000)
        if (us >= 1_000_000 or us < 0) {
            const extra_s = @divFloor(us, 1_000_000);
            s += extra_s;
            us = @mod(us, 1_000_000);
        }

        // Normalize seconds (0 <= s < 86400)
        if (s >= 86400 or s < 0) {
            const extra_d = @divFloor(s, 86400);
            d += extra_d;
            s = @mod(s, 86400);
        }

        return Timedelta{
            .days = d,
            .seconds = s,
            .microseconds = us,
        };
    }

    /// Convert to string representation
    pub fn toString(self: Timedelta, allocator: std.mem.Allocator) ![]const u8 {
        if (self.seconds == 0 and self.microseconds == 0) {
            if (self.days == 1) {
                return std.fmt.allocPrint(allocator, "1 day, 0:00:00", .{});
            } else {
                return std.fmt.allocPrint(allocator, "{d} days, 0:00:00", .{self.days});
            }
        }

        const hours = @divTrunc(self.seconds, 3600);
        const mins = @divTrunc(@mod(self.seconds, 3600), 60);
        const secs = @mod(self.seconds, 60);

        if (self.days == 1) {
            return std.fmt.allocPrint(allocator, "1 day, {d}:{d:0>2}:{d:0>2}", .{ hours, mins, secs });
        } else if (self.days == 0) {
            return std.fmt.allocPrint(allocator, "{d}:{d:0>2}:{d:0>2}", .{ hours, mins, secs });
        } else {
            return std.fmt.allocPrint(allocator, "{d} days, {d}:{d:0>2}:{d:0>2}", .{ self.days, hours, mins, secs });
        }
    }

    /// Create PyString from timedelta
    pub fn toPyString(self: Timedelta, allocator: std.mem.Allocator) !*runtime.PyObject {
        const str = try self.toString(allocator);
        return try runtime.PyString.create(allocator, str);
    }
};

// =============================================================================
// Public API for codegen
// =============================================================================

/// datetime.timedelta(days=N) - returns Timedelta struct
pub fn timedelta(days: i64) Timedelta {
    return Timedelta.fromDays(days);
}

/// datetime.timedelta(days, seconds, microseconds) - full constructor
pub fn timedeltaFull(days: i64, seconds: i64, microseconds: i64) Timedelta {
    return Timedelta.init(days, seconds, microseconds);
}

/// datetime.timedelta(days=N) - returns PyString for codegen
pub fn timedeltaToPyString(allocator: std.mem.Allocator, days: i64) !*runtime.PyObject {
    const td = Timedelta.fromDays(days);
    return td.toPyString(allocator);
}

// =============================================================================
// Tests
// =============================================================================

test "timedelta" {
    const td = Timedelta.fromDays(7);
    try std.testing.expectEqual(@as(i64, 7), td.days);
    try std.testing.expectEqual(@as(f64, 604800.0), td.totalSeconds());
}
