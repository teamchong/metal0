/// Python _heapq module - C accelerator for heapq (internal)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "heappush", h.wrap2("blk: { var heap = ", "; heap.append(__global_allocator, ", ") catch {}; break :blk {}; }", "{}") },
    .{ "heappop", h.wrap("blk: { var heap = ", "; if (heap.items.len > 0) { const item = heap.items[0]; heap.items[0] = heap.items[heap.items.len - 1]; heap.items.len -= 1; break :blk item; } else { break :blk null; } }", "null") },
    .{ "heapify", h.c("{}") },
    .{ "heapreplace", h.wrap2("blk: { var heap = ", "; const old = heap.items[0]; heap.items[0] = ", "; break :blk old; }", "null") },
    .{ "heappushpop", h.wrap2("blk: { const item = ", "; var heap = ", "; if (heap.items.len > 0 and heap.items[0] < item) { const old = heap.items[0]; heap.items[0] = item; break :blk old; } break :blk item; }", "null") },
    .{ "nlargest", h.wrap2("blk: { const n = @as(usize, @intCast(", ")); const items = ", "; var result: std.ArrayList(@TypeOf(items[0])) = .{}; for (items[0..@min(n, items.len)]) |item| { result.append(__global_allocator, item) catch {}; } break :blk result.items; }", "&[_]@TypeOf(0){}") },
    .{ "nsmallest", h.wrap2("blk: { const n = @as(usize, @intCast(", ")); const items = ", "; var result: std.ArrayList(@TypeOf(items[0])) = .{}; for (items[0..@min(n, items.len)]) |item| { result.append(__global_allocator, item) catch {}; } break :blk result.items; }", "&[_]@TypeOf(0){}") },
});
