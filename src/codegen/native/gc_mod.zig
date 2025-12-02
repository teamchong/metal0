/// Python gc module - Garbage collector interface
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "enable", h.c("{}") }, .{ "disable", h.c("{}") }, .{ "isenabled", h.c("true") }, .{ "collect", h.I64(0) },
    .{ "set_debug", h.c("{}") }, .{ "get_debug", h.I32(0) },
    .{ "get_stats", h.c("&[_]struct { collections: i64, collected: i64, uncollectable: i64 }{ .{ .collections = 0, .collected = 0, .uncollectable = 0 }, .{ .collections = 0, .collected = 0, .uncollectable = 0 }, .{ .collections = 0, .collected = 0, .uncollectable = 0 } }") },
    .{ "set_threshold", h.c("{}") }, .{ "get_threshold", h.c(".{ @as(i32, 700), @as(i32, 10), @as(i32, 10) }") },
    .{ "get_count", h.c(".{ @as(i32, 0), @as(i32, 0), @as(i32, 0) }") },
    .{ "get_objects", h.c("&[_]*anyopaque{}") }, .{ "get_referrers", h.c("&[_]*anyopaque{}") }, .{ "get_referents", h.c("&[_]*anyopaque{}") },
    .{ "is_tracked", h.c("false") }, .{ "is_finalized", h.c("false") }, .{ "freeze", h.c("{}") }, .{ "unfreeze", h.c("{}") },
    .{ "get_freeze_count", h.I64(0) }, .{ "garbage", h.c("&[_]*anyopaque{}") }, .{ "callbacks", h.c("&[_]*const fn () void{}") },
    .{ "DEBUG_STATS", h.I32(1) }, .{ "DEBUG_COLLECTABLE", h.I32(2) }, .{ "DEBUG_UNCOLLECTABLE", h.I32(4) },
    .{ "DEBUG_SAVEALL", h.I32(32) }, .{ "DEBUG_LEAK", h.I32(38) },
});
