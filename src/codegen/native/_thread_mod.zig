/// Python _thread module - Low-level threading primitives
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "start_new_thread", h.wrap("blk: { const func = ", "; const thread = std.Thread.spawn(.{}, func, .{}) catch break :blk @as(i64, -1); break :blk @as(i64, @intFromPtr(thread)); }", "@as(i64, -1)") }, .{ "interrupt_main", h.c("{}") }, .{ "exit", h.c("return") },
    .{ "allocate_lock", h.c(".{ .mutex = std.Thread.Mutex{} }") }, .{ "get_ident", h.c("@as(i64, @intFromPtr(std.Thread.getCurrentId()))") },
    .{ "get_native_id", h.c("@as(i64, @intFromPtr(std.Thread.getCurrentId()))") },
    .{ "stack_size", h.I64(0) }, .{ "TIMEOUT_MAX", h.F64(4294967.0) },
    .{ "LockType", h.c("@TypeOf(.{ .mutex = std.Thread.Mutex{} })") },
    .{ "RLock", h.c(".{ .mutex = std.Thread.Mutex{}, .count = 0, .owner = null }") },
    .{ "error", h.err("ThreadError") },
});
