/// Python _strptime module - Internal strptime implementation
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "_strptime_time", h.c(".{ .tm_year = 0, .tm_mon = 1, .tm_mday = 1, .tm_hour = 0, .tm_min = 0, .tm_sec = 0, .tm_wday = 0, .tm_yday = 1, .tm_isdst = -1 }") },
    .{ "_strptime_datetime", h.c(".{ .year = 1900, .month = 1, .day = 1, .hour = 0, .minute = 0, .second = 0, .microsecond = 0, .tzinfo = null }") },
    .{ "TimeRE", h.c(".{}") }, .{ "LocaleTime", h.c(".{ .lang = \"en_US\", .LC_time = null }") },
    .{ "_cache_lock", h.c(".{}") }, .{ "_TimeRE_cache", h.c(".{}") }, .{ "_CACHE_MAX_SIZE", h.U32(5) },
    .{ "_regex_cache", h.c(".{}") }, .{ "_getlang", h.c(".{ \"en_US\", \"UTF-8\" }") },
    .{ "_calc_julian_from_U_or_W", h.I32(1) }, .{ "_calc_julian_from_V", h.I32(1) },
});
