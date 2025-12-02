/// Python _bisect module - C accelerator for bisect (internal)
const std = @import("std");
const h = @import("mod_helper.zig");

const bisectLeftBody = "; var lo: usize = 0; var hi: usize = arr.len; while (lo < hi) { const mid = (lo + hi) / 2; if (arr[mid] < x) { lo = mid + 1; } else { hi = mid; } } break :blk @as(i64, @intCast(lo)); }";
const bisectRightBody = "; var lo: usize = 0; var hi: usize = arr.len; while (lo < hi) { const mid = (lo + hi) / 2; if (x < arr[mid]) { hi = mid; } else { lo = mid + 1; } } break :blk @as(i64, @intCast(lo)); }";
const genBisectRight = h.wrap2("blk: { const arr = ", "; const x = ", bisectRightBody, "@as(i64, 0)");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "bisect_left", h.wrap2("blk: { const arr = ", "; const x = ", bisectLeftBody, "@as(i64, 0)") },
    .{ "bisect_right", genBisectRight }, .{ "bisect", genBisectRight },
    .{ "insort_left", h.c("{}") }, .{ "insort_right", h.c("{}") }, .{ "insort", h.c("{}") },
});
