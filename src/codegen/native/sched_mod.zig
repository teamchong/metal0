/// Python sched module - Event scheduler
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "scheduler", h.c(".{ .queue = &[_]@TypeOf(.{ .time = @as(f64, 0), .priority = @as(i32, 0), .sequence = @as(i64, 0), .action = @as(?*anyopaque, null), .argument = .{}, .kwargs = .{} }){} }") },
    .{ "Event", h.c(".{ .time = @as(f64, 0), .priority = @as(i32, 0), .sequence = @as(i64, 0), .action = @as(?*anyopaque, null), .argument = .{}, .kwargs = .{} }") },
});
