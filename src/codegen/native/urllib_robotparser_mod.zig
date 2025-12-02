/// Python urllib.robotparser module - robots.txt parser
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "RobotFileParser", h.wrap("blk: { const url = ", "; break :blk .{ .url = url, .last_checked = @as(i64, 0) }; }", ".{ .url = \"\", .last_checked = @as(i64, 0) }") },
});
