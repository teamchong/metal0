/// Python zoneinfo module - IANA time zone support
const std = @import("std");
const h = @import("mod_helper.zig");

const genZoneInfo = h.wrap(".{ .key = ", " }", ".{ .key = \"UTC\" }");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "ZoneInfo", genZoneInfo }, .{ "available_timezones", h.c("&[_][]const u8{ \"UTC\", \"America/New_York\", \"America/Los_Angeles\", \"America/Chicago\", \"Europe/London\", \"Europe/Paris\", \"Europe/Berlin\", \"Asia/Tokyo\", \"Asia/Shanghai\", \"Asia/Singapore\", \"Australia/Sydney\", \"Pacific/Auckland\" }") },
    .{ "reset_tzpath", h.c("{}") }, .{ "TZPATH", h.c("&[_][]const u8{ \"/usr/share/zoneinfo\", \"/usr/lib/zoneinfo\", \"/usr/share/lib/zoneinfo\", \"/etc/zoneinfo\" }") },
    .{ "key", h.c("\"UTC\"") }, .{ "utcoffset", h.c(".{ .days = 0, .seconds = 0, .microseconds = 0 }") },
    .{ "tzname", h.c("\"UTC\"") }, .{ "dst", h.c(".{ .days = 0, .seconds = 0, .microseconds = 0 }") },
    .{ "fromutc", h.pass(".{ .year = 1970, .month = 1, .day = 1, .hour = 0, .minute = 0, .second = 0, .microsecond = 0 }") },
    .{ "no_cache", genZoneInfo }, .{ "clear_cache", h.c("{}") },
    .{ "ZoneInfoNotFoundError", h.err("ZoneInfoNotFoundError") }, .{ "InvalidTZPathWarning", h.err("InvalidTZPathWarning") },
});
