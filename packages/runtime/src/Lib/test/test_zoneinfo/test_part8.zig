//! test.test_zoneinfo.test_part8 - Timezone arithmetic and calculations
//!
//! This module handles timezone arithmetic:
//! - Adding/subtracting time across timezone boundaries
//! - Day/week/month calculations with timezones
//! - Business day calculations
//! - Period spanning DST transitions

const std = @import("std");
const testing = std.testing;
const mem = std.mem;

/// Duration in seconds with timezone awareness
pub const TZDuration = struct {
    total_seconds: i64,
    dst_adjustment: i32 = 0,

    pub const SECOND: i64 = 1;
    pub const MINUTE: i64 = 60;
    pub const HOUR: i64 = 3600;
    pub const DAY: i64 = 86400;
    pub const WEEK: i64 = 604800;

    /// Create from seconds
    pub fn fromSeconds(secs: i64) TZDuration {
        return .{ .total_seconds = secs };
    }

    /// Create from hours
    pub fn fromHours(hours: i64) TZDuration {
        return .{ .total_seconds = hours * HOUR };
    }

    /// Create from days
    pub fn fromDays(days: i64) TZDuration {
        return .{ .total_seconds = days * DAY };
    }

    /// Create from weeks
    pub fn fromWeeks(weeks: i64) TZDuration {
        return .{ .total_seconds = weeks * WEEK };
    }

    /// Get hours component
    pub fn hours(self: TZDuration) i64 {
        return @divFloor(self.total_seconds, HOUR);
    }

    /// Get minutes component (within hour)
    pub fn minutes(self: TZDuration) i64 {
        return @divFloor(@mod(self.total_seconds, HOUR), MINUTE);
    }

    /// Get seconds component (within minute)
    pub fn seconds(self: TZDuration) i64 {
        return @mod(self.total_seconds, MINUTE);
    }

    /// Get total days
    pub fn totalDays(self: TZDuration) i64 {
        return @divFloor(self.total_seconds, DAY);
    }

    /// Add durations
    pub fn add(self: TZDuration, other: TZDuration) TZDuration {
        return .{
            .total_seconds = self.total_seconds + other.total_seconds,
            .dst_adjustment = self.dst_adjustment + other.dst_adjustment,
        };
    }

    /// Subtract durations
    pub fn sub(self: TZDuration, other: TZDuration) TZDuration {
        return .{
            .total_seconds = self.total_seconds - other.total_seconds,
            .dst_adjustment = self.dst_adjustment - other.dst_adjustment,
        };
    }

    /// Negate duration
    pub fn negate(self: TZDuration) TZDuration {
        return .{
            .total_seconds = -self.total_seconds,
            .dst_adjustment = -self.dst_adjustment,
        };
    }

    /// Compare durations
    pub fn compare(self: TZDuration, other: TZDuration) std.math.Order {
        return std.math.order(self.total_seconds, other.total_seconds);
    }
};

/// Period calculator with timezone support
pub const PeriodCalculator = struct {
    /// Calculate days between two timestamps in a timezone
    pub fn daysBetween(start_ts: i64, end_ts: i64, tz_offset: i32) i64 {
        const start_local = start_ts + tz_offset;
        const end_local = end_ts + tz_offset;

        const start_day = @divFloor(start_local, 86400);
        const end_day = @divFloor(end_local, 86400);

        return end_day - start_day;
    }

    /// Calculate weeks between two timestamps
    pub fn weeksBetween(start_ts: i64, end_ts: i64, tz_offset: i32) i64 {
        return @divFloor(daysBetween(start_ts, end_ts, tz_offset), 7);
    }

    /// Calculate if same day
    pub fn isSameDay(ts1: i64, ts2: i64, tz_offset: i32) bool {
        return daysBetween(ts1, ts2, tz_offset) == 0;
    }

    /// Get start of day for a timestamp
    pub fn startOfDay(ts: i64, tz_offset: i32) i64 {
        const local = ts + tz_offset;
        const day_start_local = @divFloor(local, 86400) * 86400;
        return day_start_local - tz_offset;
    }

    /// Get end of day for a timestamp
    pub fn endOfDay(ts: i64, tz_offset: i32) i64 {
        return startOfDay(ts, tz_offset) + 86400 - 1;
    }

    /// Get start of week (Monday = 0)
    pub fn startOfWeek(ts: i64, tz_offset: i32) i64 {
        const day_start = startOfDay(ts, tz_offset);
        const local = day_start + tz_offset;
        const day_ordinal = @divFloor(local, 86400);
        const weekday = @mod(day_ordinal + 3, 7); // Thursday is 0 at epoch
        return day_start - weekday * 86400;
    }
};

/// Business day calculator
pub const BusinessDayCalculator = struct {
    /// Check if a day is a weekend (Saturday=5, Sunday=6)
    pub fn isWeekend(ts: i64, tz_offset: i32) bool {
        const local = ts + tz_offset;
        const day_ordinal = @divFloor(local, 86400);
        const weekday = @mod(day_ordinal + 3, 7); // Thursday is 0 at epoch
        return weekday >= 5;
    }

    /// Get weekday (0=Monday, 6=Sunday)
    pub fn weekday(ts: i64, tz_offset: i32) u8 {
        const local = ts + tz_offset;
        const day_ordinal = @divFloor(local, 86400);
        return @intCast(@mod(day_ordinal + 3, 7));
    }

    /// Count business days between two timestamps
    pub fn businessDaysBetween(start_ts: i64, end_ts: i64, tz_offset: i32) i64 {
        var count: i64 = 0;
        var current = PeriodCalculator.startOfDay(start_ts, tz_offset);
        const end = PeriodCalculator.startOfDay(end_ts, tz_offset);

        while (current < end) {
            if (!isWeekend(current, tz_offset)) {
                count += 1;
            }
            current += 86400;
        }

        return count;
    }

    /// Add business days to a timestamp
    pub fn addBusinessDays(ts: i64, days: i64, tz_offset: i32) i64 {
        var current = ts;
        var remaining = days;
        const step: i64 = if (days >= 0) 86400 else -86400;

        while (remaining != 0) {
            current += step;
            if (!isWeekend(current, tz_offset)) {
                if (days >= 0) remaining -= 1 else remaining += 1;
            }
        }

        return current;
    }

    /// Get next business day
    pub fn nextBusinessDay(ts: i64, tz_offset: i32) i64 {
        var current = PeriodCalculator.startOfDay(ts, tz_offset) + 86400;
        while (isWeekend(current, tz_offset)) {
            current += 86400;
        }
        return current;
    }
};

/// DST-aware time span
pub const DSTAwareSpan = struct {
    start_utc: i64,
    end_utc: i64,
    start_offset: i32,
    end_offset: i32,

    /// Check if span crosses a DST transition
    pub fn crossesDST(self: DSTAwareSpan) bool {
        return self.start_offset != self.end_offset;
    }

    /// Get duration in wall clock time
    pub fn wallClockDuration(self: DSTAwareSpan) i64 {
        const start_local = self.start_utc + self.start_offset;
        const end_local = self.end_utc + self.end_offset;
        return end_local - start_local;
    }

    /// Get actual elapsed time (UTC)
    pub fn elapsedTime(self: DSTAwareSpan) i64 {
        return self.end_utc - self.start_utc;
    }

    /// Get DST adjustment amount
    pub fn dstAdjustment(self: DSTAwareSpan) i32 {
        return self.end_offset - self.start_offset;
    }
};

/// Time of day in a timezone
pub const TimeOfDay = struct {
    hour: u8,
    minute: u8,
    second: u8,

    /// Create from seconds since midnight
    pub fn fromSeconds(secs: u32) TimeOfDay {
        return .{
            .hour = @intCast(secs / 3600),
            .minute = @intCast((secs % 3600) / 60),
            .second = @intCast(secs % 60),
        };
    }

    /// Convert to seconds since midnight
    pub fn toSeconds(self: TimeOfDay) u32 {
        return @as(u32, self.hour) * 3600 +
            @as(u32, self.minute) * 60 +
            @as(u32, self.second);
    }

    /// Get time of day from timestamp and timezone
    pub fn fromTimestamp(ts: i64, tz_offset: i32) TimeOfDay {
        const local = ts + tz_offset;
        const day_seconds: u32 = @intCast(@mod(local, 86400));
        return fromSeconds(day_seconds);
    }

    /// Check if before another time
    pub fn isBefore(self: TimeOfDay, other: TimeOfDay) bool {
        return self.toSeconds() < other.toSeconds();
    }

    /// Check if after another time
    pub fn isAfter(self: TimeOfDay, other: TimeOfDay) bool {
        return self.toSeconds() > other.toSeconds();
    }
};

/// Month arithmetic
pub const MonthCalculator = struct {
    /// Days in each month (non-leap year)
    const MONTH_DAYS = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };

    pub fn daysInMonth(year: i32, month: u8) u8 {
        if (month == 2 and isLeapYear(year)) return 29;
        return MONTH_DAYS[month - 1];
    }

    pub fn isLeapYear(year: i32) bool {
        if (@mod(year, 400) == 0) return true;
        if (@mod(year, 100) == 0) return false;
        if (@mod(year, 4) == 0) return true;
        return false;
    }

    /// Add months to a date
    pub fn addMonths(year: i32, month: u8, day: u8, months_to_add: i32) struct { year: i32, month: u8, day: u8 } {
        var new_month: i32 = @as(i32, month) + months_to_add;
        var new_year = year;

        // Handle year overflow
        while (new_month > 12) {
            new_month -= 12;
            new_year += 1;
        }
        while (new_month < 1) {
            new_month += 12;
            new_year -= 1;
        }

        // Clamp day to valid range for new month
        const max_day = daysInMonth(new_year, @intCast(new_month));
        const new_day = @min(day, max_day);

        return .{
            .year = new_year,
            .month = @intCast(new_month),
            .day = new_day,
        };
    }

    /// Difference in months between two dates
    pub fn monthsDifference(y1: i32, m1: u8, y2: i32, m2: u8) i32 {
        return (y2 - y1) * 12 + @as(i32, m2) - @as(i32, m1);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "tz_duration_from_seconds" {
    const d = TZDuration.fromSeconds(3661);
    try testing.expectEqual(@as(i64, 1), d.hours());
    try testing.expectEqual(@as(i64, 1), d.minutes());
    try testing.expectEqual(@as(i64, 1), d.seconds());
}

test "tz_duration_from_hours" {
    const d = TZDuration.fromHours(5);
    try testing.expectEqual(@as(i64, 18000), d.total_seconds);
}

test "tz_duration_from_days" {
    const d = TZDuration.fromDays(2);
    try testing.expectEqual(@as(i64, 172800), d.total_seconds);
}

test "tz_duration_from_weeks" {
    const d = TZDuration.fromWeeks(1);
    try testing.expectEqual(@as(i64, 604800), d.total_seconds);
}

test "tz_duration_total_days" {
    const d = TZDuration.fromSeconds(200000);
    try testing.expectEqual(@as(i64, 2), d.totalDays());
}

test "tz_duration_add" {
    const a = TZDuration.fromHours(2);
    const b = TZDuration.fromHours(3);
    const sum = a.add(b);
    try testing.expectEqual(@as(i64, 5), sum.hours());
}

test "tz_duration_sub" {
    const a = TZDuration.fromHours(5);
    const b = TZDuration.fromHours(2);
    const diff = a.sub(b);
    try testing.expectEqual(@as(i64, 3), diff.hours());
}

test "tz_duration_negate" {
    const d = TZDuration.fromHours(3);
    const neg = d.negate();
    try testing.expectEqual(@as(i64, -3), neg.hours());
}

test "tz_duration_compare" {
    const a = TZDuration.fromHours(2);
    const b = TZDuration.fromHours(3);
    try testing.expectEqual(std.math.Order.lt, a.compare(b));
}

test "period_calculator_days_between" {
    // Same day
    try testing.expectEqual(@as(i64, 0), PeriodCalculator.daysBetween(0, 3600, 0));
    // One day apart
    try testing.expectEqual(@as(i64, 1), PeriodCalculator.daysBetween(0, 86400, 0));
}

test "period_calculator_weeks_between" {
    try testing.expectEqual(@as(i64, 1), PeriodCalculator.weeksBetween(0, 604800, 0));
    try testing.expectEqual(@as(i64, 2), PeriodCalculator.weeksBetween(0, 1209600, 0));
}

test "period_calculator_is_same_day" {
    try testing.expect(PeriodCalculator.isSameDay(0, 3600, 0));
    try testing.expect(!PeriodCalculator.isSameDay(0, 86400, 0));
}

test "period_calculator_start_of_day" {
    const ts = 50000; // Some time during day 0
    const start = PeriodCalculator.startOfDay(ts, 0);
    try testing.expectEqual(@as(i64, 0), start);
}

test "period_calculator_end_of_day" {
    const ts = 50000;
    const end_val = PeriodCalculator.endOfDay(ts, 0);
    try testing.expectEqual(@as(i64, 86399), end_val);
}

test "business_day_calculator_is_weekend" {
    // Thursday Jan 1 1970 (epoch) - not weekend
    try testing.expect(!BusinessDayCalculator.isWeekend(0, 0));
    // Saturday Jan 3 1970
    try testing.expect(BusinessDayCalculator.isWeekend(172800, 0));
}

test "business_day_calculator_weekday" {
    // Thursday Jan 1 1970 = day 3 (0-indexed from Monday)
    try testing.expectEqual(@as(u8, 3), BusinessDayCalculator.weekday(0, 0));
}

test "business_day_calculator_business_days_between" {
    // 1 week = 5 business days
    try testing.expectEqual(@as(i64, 5), BusinessDayCalculator.businessDaysBetween(0, 604800, 0));
}

test "business_day_calculator_next_business_day" {
    // Friday Jan 2 1970, next business day should be Monday Jan 5
    const friday = 86400;
    const next = BusinessDayCalculator.nextBusinessDay(friday, 0);
    // Should skip Saturday and Sunday
    try testing.expect(!BusinessDayCalculator.isWeekend(next, 0));
}

test "dst_aware_span_no_crossing" {
    const span = DSTAwareSpan{
        .start_utc = 1000,
        .end_utc = 2000,
        .start_offset = -18000,
        .end_offset = -18000,
    };
    try testing.expect(!span.crossesDST());
    try testing.expectEqual(@as(i64, 1000), span.elapsedTime());
}

test "dst_aware_span_crossing" {
    const span = DSTAwareSpan{
        .start_utc = 1000,
        .end_utc = 2000,
        .start_offset = -18000,
        .end_offset = -14400,
    };
    try testing.expect(span.crossesDST());
    try testing.expectEqual(@as(i32, 3600), span.dstAdjustment());
}

test "dst_aware_span_wall_clock_duration" {
    const span = DSTAwareSpan{
        .start_utc = 0,
        .end_utc = 7200,
        .start_offset = -18000,
        .end_offset = -14400, // 1 hour less offset = spring forward
    };
    // Wall clock sees 3 hours (7200 + 3600)
    try testing.expectEqual(@as(i64, 10800), span.wallClockDuration());
}

test "time_of_day_from_seconds" {
    const tod = TimeOfDay.fromSeconds(52245);
    try testing.expectEqual(@as(u8, 14), tod.hour);
    try testing.expectEqual(@as(u8, 30), tod.minute);
    try testing.expectEqual(@as(u8, 45), tod.second);
}

test "time_of_day_to_seconds" {
    const tod = TimeOfDay{ .hour = 14, .minute = 30, .second = 45 };
    try testing.expectEqual(@as(u32, 52245), tod.toSeconds());
}

test "time_of_day_from_timestamp" {
    const tod = TimeOfDay.fromTimestamp(52245, 0);
    try testing.expectEqual(@as(u8, 14), tod.hour);
}

test "time_of_day_is_before" {
    const a = TimeOfDay{ .hour = 10, .minute = 0, .second = 0 };
    const b = TimeOfDay{ .hour = 14, .minute = 0, .second = 0 };
    try testing.expect(a.isBefore(b));
    try testing.expect(!b.isBefore(a));
}

test "month_calculator_days_in_month" {
    try testing.expectEqual(@as(u8, 31), MonthCalculator.daysInMonth(2023, 1));
    try testing.expectEqual(@as(u8, 28), MonthCalculator.daysInMonth(2023, 2));
    try testing.expectEqual(@as(u8, 29), MonthCalculator.daysInMonth(2024, 2));
}

test "month_calculator_add_months" {
    const result = MonthCalculator.addMonths(2023, 6, 15, 3);
    try testing.expectEqual(@as(i32, 2023), result.year);
    try testing.expectEqual(@as(u8, 9), result.month);
}

test "month_calculator_add_months_year_wrap" {
    const result = MonthCalculator.addMonths(2023, 11, 15, 3);
    try testing.expectEqual(@as(i32, 2024), result.year);
    try testing.expectEqual(@as(u8, 2), result.month);
}

test "month_calculator_add_months_day_clamp" {
    // Jan 31 + 1 month = Feb 28 (or 29)
    const result = MonthCalculator.addMonths(2023, 1, 31, 1);
    try testing.expectEqual(@as(u8, 28), result.day);
}

test "month_calculator_months_difference" {
    try testing.expectEqual(@as(i32, 0), MonthCalculator.monthsDifference(2023, 6, 2023, 6));
    try testing.expectEqual(@as(i32, 3), MonthCalculator.monthsDifference(2023, 6, 2023, 9));
    try testing.expectEqual(@as(i32, 12), MonthCalculator.monthsDifference(2023, 6, 2024, 6));
}
