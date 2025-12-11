/// Time struct - represents datetime.time

const std = @import("std");
const runtime = @import("../../runtime.zig");

/// Time struct - represents datetime.time
pub const Time = struct {
    hour: u8,
    minute: u8,
    second: u8,
    microsecond: u32,
    /// fold attribute - disambiguates wall times during DST transitions
    fold: u1 = 0,

    /// Convert to string: HH:MM:SS.ffffff
    pub fn toString(self: Time, allocator: std.mem.Allocator) ![]const u8 {
        if (self.microsecond > 0) {
            return std.fmt.allocPrint(allocator, "{d:0>2}:{d:0>2}:{d:0>2}.{d:0>6}", .{
                self.hour, self.minute, self.second, self.microsecond,
            });
        }
        return std.fmt.allocPrint(allocator, "{d:0>2}:{d:0>2}:{d:0>2}", .{
            self.hour, self.minute, self.second,
        });
    }

    /// Parse from ISO format string "HH:MM:SS" or "HH:MM:SS.ffffff"
    pub fn parseIsoformat(s: []const u8) !Time {
        if (s.len < 8) return error.InvalidFormat;
        const hour = std.fmt.parseInt(u8, s[0..2], 10) catch return error.InvalidFormat;
        const minute = std.fmt.parseInt(u8, s[3..5], 10) catch return error.InvalidFormat;
        const second = std.fmt.parseInt(u8, s[6..8], 10) catch return error.InvalidFormat;
        var microsecond: u32 = 0;
        if (s.len > 9 and s[8] == '.') {
            const usec_str = s[9..@min(15, s.len)];
            microsecond = std.fmt.parseInt(u32, usec_str, 10) catch 0;
            // Pad to 6 digits
            var mult: u32 = 1;
            var i: usize = usec_str.len;
            while (i < 6) : (i += 1) mult *= 10;
            microsecond *= mult;
        }
        return Time{ .hour = hour, .minute = minute, .second = second, .microsecond = microsecond };
    }
};

/// Extend Time with additional CPython-compatible methods
pub const TimeExt = struct {
    /// replace(hour, minute, second, microsecond) - return time with some fields replaced
    pub fn replace(t: Time, hour: ?u8, minute: ?u8, second: ?u8, microsecond: ?u32) Time {
        return Time{
            .hour = hour orelse t.hour,
            .minute = minute orelse t.minute,
            .second = second orelse t.second,
            .microsecond = microsecond orelse t.microsecond,
        };
    }

    /// isoformat() - return ISO format string
    pub fn isoformat(t: Time, allocator: std.mem.Allocator) ![]const u8 {
        return t.toString(allocator);
    }
};

// =============================================================================
// Public API for codegen
// =============================================================================

/// datetime.time(hour, minute, second, microsecond=0) - returns Time struct
pub fn time(hour: i64, minute: i64, second: i64) Time {
    return Time{
        .hour = @intCast(hour),
        .minute = @intCast(minute),
        .second = @intCast(second),
        .microsecond = 0,
    };
}

/// datetime.time with microseconds
pub fn timeFull(hour: i64, minute: i64, second: i64, microsecond: i64) Time {
    return Time{
        .hour = @intCast(hour),
        .minute = @intCast(minute),
        .second = @intCast(second),
        .microsecond = @intCast(microsecond),
    };
}
