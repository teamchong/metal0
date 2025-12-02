/// Python _random module - C accelerator for random (internal)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Random", h.c(".{ .state = std.Random.DefaultPrng.init(0) }") }, .{ "random", h.c("blk: { var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); break :blk prng.random().float(f64); }") },
    .{ "seed", h.c("{}") }, .{ "getstate", h.c(".{ .version = 3, .state = &[_]u32{} ** 625, .index = 624 }") }, .{ "setstate", h.c("{}") }, .{ "getrandbits", h.wrap("blk: { const k = ", "; _ = k; var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); break :blk @as(i64, @intCast(prng.random().int(u64))); }", "@as(i64, 0)") },
});
