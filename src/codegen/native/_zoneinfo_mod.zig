/// Python _zoneinfo module - Internal zoneinfo support (C accelerator)
const std = @import("std");
const h = @import("mod_helper.zig");

const genZoneInfo = h.wrap("blk: { const key = ", "; break :blk .{ .key = key }; }", ".{ .key = \"UTC\" }");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "zone_info", genZoneInfo }, .{ "from_file", h.c(".{ .key = \"UTC\" }") }, .{ "no_cache", genZoneInfo }, .{ "clear_cache", h.c("{}") },
    .{ "key", h.c("\"UTC\"") }, .{ "utcoffset", h.c("null") }, .{ "tzname", h.c("\"UTC\"") }, .{ "dst", h.c("null") },
    .{ "t_z_p_a_t_h", h.c("&[_][]const u8{ \"/usr/share/zoneinfo\", \"/usr/lib/zoneinfo\", \"/usr/share/lib/zoneinfo\", \"/etc/zoneinfo\" }") },
    .{ "reset_tzpath", h.c("{}") }, .{ "available_timezones", h.c("&[_][]const u8{ \"UTC\", \"GMT\" }") },
    .{ "zone_info_not_found_error", h.err("ZoneInfoNotFoundError") }, .{ "invalid_t_z_path_warning", h.err("InvalidTZPathWarning") },
});
