/// Python _pydatetime module - Pure Python datetime implementation
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "date", h.wrap3("blk: { const y = ", "; const m = ", "; const d = ", "; break :blk .{ .year = y, .month = m, .day = d }; }", ".{ .year = 1970, .month = 1, .day = 1 }") },
    .{ "time", h.c(".{ .hour = 0, .minute = 0, .second = 0, .microsecond = 0, .tzinfo = null }") },
    .{ "datetime", h.wrap3("blk: { const y = ", "; const m = ", "; const d = ", "; break :blk .{ .year = y, .month = m, .day = d, .hour = 0, .minute = 0, .second = 0, .microsecond = 0, .tzinfo = null }; }", ".{ .year = 1970, .month = 1, .day = 1, .hour = 0, .minute = 0, .second = 0, .microsecond = 0, .tzinfo = null }") },
    .{ "timedelta", h.c(".{ .days = 0, .seconds = 0, .microseconds = 0 }") },
    .{ "timezone", h.c(".{ .offset = .{ .days = 0, .seconds = 0, .microseconds = 0 }, .name = null }") },
});
