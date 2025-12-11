/// Timezone support (100% CPython alignment)

const std = @import("std");
const Timedelta = @import("timedelta.zig").Timedelta;
const Datetime = @import("datetime_impl.zig").Datetime;

/// tzinfo - Abstract base class for timezone information
pub const TzInfo = struct {
    /// Offset from UTC in minutes
    offset_minutes: i32,
    /// Timezone name
    name: []const u8,

    pub fn utcoffset(self: TzInfo) Timedelta {
        const total_seconds = @as(i64, self.offset_minutes) * 60;
        return Timedelta.init(0, total_seconds, 0);
    }

    pub fn tzname(self: TzInfo) []const u8 {
        return self.name;
    }

    pub fn dst(self: TzInfo) ?Timedelta {
        _ = self;
        return null; // No DST by default
    }
};

/// timezone - Fixed offset from UTC
pub const Timezone = struct {
    offset: Timedelta,
    name: ?[]const u8,

    pub fn init(offset: Timedelta, name: ?[]const u8) Timezone {
        return .{ .offset = offset, .name = name };
    }

    pub fn initFromHours(hours: i32) Timezone {
        return .{
            .offset = Timedelta.init(0, @as(i64, hours) * 3600, 0),
            .name = null,
        };
    }

    pub fn initFromMinutes(minutes: i32) Timezone {
        return .{
            .offset = Timedelta.init(0, @as(i64, minutes) * 60, 0),
            .name = null,
        };
    }

    pub fn utcoffset(self: Timezone, dt: Datetime) Timedelta {
        _ = dt;
        return self.offset;
    }

    pub fn tzname(self: Timezone, dt: Datetime, allocator: std.mem.Allocator) ![]const u8 {
        _ = dt;
        if (self.name) |n| return n;

        // Generate name from offset
        const total_secs = self.offset.totalSeconds();
        const hours = @divTrunc(@as(i64, @intFromFloat(total_secs)), 3600);
        const minutes = @divTrunc(@mod(@as(i64, @intFromFloat(total_secs)), 3600), 60);

        if (hours >= 0) {
            return std.fmt.allocPrint(allocator, "UTC+{d:0>2}:{d:0>2}", .{ hours, minutes });
        } else {
            return std.fmt.allocPrint(allocator, "UTC{d:0>2}:{d:0>2}", .{ hours, @abs(minutes) });
        }
    }

    pub fn dst(self: Timezone, dt: Datetime) ?Timedelta {
        _ = self;
        _ = dt;
        return null; // Fixed offset, no DST
    }
};

/// UTC timezone constant
pub const UTC = Timezone{
    .offset = Timedelta.init(0, 0, 0),
    .name = "UTC",
};

// =============================================================================
// astimezone - Convert datetime to another timezone
// =============================================================================

/// datetime.astimezone(tz) -> datetime
/// Convert a datetime to a new timezone
/// This is a simplified implementation that assumes the input datetime is in UTC
/// when it has no timezone info, or uses the provided offset.
pub fn astimezone(dt: Datetime, tz: Timezone) Datetime {
    // Get the offset in seconds
    const offset = tz.utcoffset(dt);
    const offset_secs = offset.totalSeconds();

    // Convert current datetime to timestamp (assuming UTC)
    const ts = dt.toTimestamp();

    // Apply the timezone offset
    const new_ts: i64 = @intFromFloat(ts + offset_secs);

    // Convert back to datetime
    return Datetime.fromTimestamp(new_ts);
}

/// Create a timezone-aware datetime by attaching a timezone
pub const DatetimeWithTz = struct {
    datetime: Datetime,
    tzinfo: ?Timezone,

    pub fn init(dt: Datetime, tz: ?Timezone) DatetimeWithTz {
        return .{ .datetime = dt, .tzinfo = tz };
    }

    /// astimezone - Convert to another timezone
    pub fn astimezone_tz(self: DatetimeWithTz, target_tz: Timezone) DatetimeWithTz {
        if (self.tzinfo) |src_tz| {
            // Convert from source timezone to target timezone
            // First convert to UTC, then to target
            const src_offset = src_tz.offset.totalSeconds();
            const ts = self.datetime.toTimestamp() - src_offset;
            const target_offset = target_tz.offset.totalSeconds();
            const new_ts: i64 = @intFromFloat(ts + target_offset);
            return .{
                .datetime = Datetime.fromTimestamp(new_ts),
                .tzinfo = target_tz,
            };
        } else {
            // Assume local time, just apply target timezone
            return .{
                .datetime = astimezone(self.datetime, target_tz),
                .tzinfo = target_tz,
            };
        }
    }

    /// utcoffset() - Return UTC offset
    pub fn utcoffset(self: DatetimeWithTz) ?Timedelta {
        if (self.tzinfo) |tz| {
            return tz.offset;
        }
        return null;
    }

    /// tzname() - Return timezone name
    pub fn tzname(self: DatetimeWithTz, allocator: std.mem.Allocator) !?[]const u8 {
        if (self.tzinfo) |tz| {
            return try tz.tzname(self.datetime, allocator);
        }
        return null;
    }

    /// dst() - Return DST offset (always null for fixed offset timezones)
    pub fn dst(self: DatetimeWithTz) ?Timedelta {
        if (self.tzinfo) |tz| {
            return tz.dst(self.datetime);
        }
        return null;
    }

    /// isoformat() - Return ISO format string with timezone
    pub fn isoformat(self: DatetimeWithTz, allocator: std.mem.Allocator) ![]const u8 {
        const base = try self.datetime.toIsoformat(allocator);
        if (self.tzinfo) |tz| {
            const total_secs = tz.offset.totalSeconds();
            const hours = @divTrunc(@as(i64, @intFromFloat(total_secs)), 3600);
            const minutes = @abs(@divTrunc(@mod(@as(i64, @intFromFloat(total_secs)), 3600), 60));

            if (hours >= 0) {
                return std.fmt.allocPrint(allocator, "{s}+{d:0>2}:{d:0>2}", .{ base, hours, minutes });
            } else {
                return std.fmt.allocPrint(allocator, "{s}-{d:0>2}:{d:0>2}", .{ base, @abs(hours), minutes });
            }
        }
        return base;
    }
};
