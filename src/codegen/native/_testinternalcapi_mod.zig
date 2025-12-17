const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "get_configs", h.c(".{}") },
    .{ "get_recursion_depth", h.c("@as(i64, 1000)") },

    // Time functions for test_time.py - use comptime for platform-specific values
    .{ "SIZEOF_TIME_T", h.c(blk: {
        const builtin = @import("builtin");
        // time_t size varies by platform: 32-bit on 32-bit systems, 64-bit elsewhere
        break :blk if (builtin.os.tag == .windows)
            "@as(i64, 8)" // Windows: always 64-bit time_t
        else if (builtin.cpu.arch == .x86 or builtin.cpu.arch == .arm)
            "@as(i64, 4)" // 32-bit Unix: 32-bit time_t
        else
            "@as(i64, 8)"; // 64-bit Unix: 64-bit time_t
    }) },
    .{ "_PyTime_FromSeconds", h.discardBlk("ts", "@as(i64, 0)", "@as(i64, 0)") },
    .{ "_PyTime_FromSecondsObject", h.discardBlk("tso", "@as(i64, 0)", "@as(i64, 0)") },
    .{ "_PyTime_AsTimeval", h.discardBlk("ttv", ".{ .tv_sec = @as(i64, 0), .tv_usec = @as(i64, 0) }", ".{ .tv_sec = @as(i64, 0), .tv_usec = @as(i64, 0) }") },
    .{ "_PyTime_AsTimespec", h.discardBlk("tts", ".{ .tv_sec = @as(i64, 0), .tv_nsec = @as(i64, 0) }", ".{ .tv_sec = @as(i64, 0), .tv_nsec = @as(i64, 0) }") },
    .{ "_PyTime_AsTimeval_clamp", h.discardBlk("ttvc", ".{ .tv_sec = @as(i64, 0), .tv_usec = @as(i64, 0) }", ".{ .tv_sec = @as(i64, 0), .tv_usec = @as(i64, 0) }") },
    .{ "_PyTime_AsTimespec_clamp", h.discardBlk("ttsc", ".{ .tv_sec = @as(i64, 0), .tv_nsec = @as(i64, 0) }", ".{ .tv_sec = @as(i64, 0), .tv_nsec = @as(i64, 0) }") },
    .{ "_PyTime_AsMilliseconds", h.discardBlk("tms", "@as(i64, 0)", "@as(i64, 0)") },
    .{ "_PyTime_AsMicroseconds", h.discardBlk("tus", "@as(i64, 0)", "@as(i64, 0)") },
    .{ "_PyTime_ObjectToTime_t", h.discardBlk("ott", "@as(i64, 0)", "@as(i64, 0)") },
    .{ "_PyTime_ObjectToTimeval", h.discardBlk("otv", ".{ .tv_sec = @as(i64, 0), .tv_usec = @as(i64, 0) }", ".{ .tv_sec = @as(i64, 0), .tv_usec = @as(i64, 0) }") },
    .{ "_PyTime_ObjectToTimespec", h.discardBlk("ots", ".{ .tv_sec = @as(i64, 0), .tv_nsec = @as(i64, 0) }", ".{ .tv_sec = @as(i64, 0), .tv_nsec = @as(i64, 0) }") },
});
