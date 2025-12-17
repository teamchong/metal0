/// Python _heapq module - C accelerator for heapq (internal)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "heappush", h.wrap2Blk("hpush", "__v0.append(__global_allocator, __v1) catch unreachable;", "{}", "{}") },
    .{ "heappop", h.wrapBlk("hpop", "if (__v.items.len > 0) { const _item = __v.items[0]; __v.items[0] = __v.items[__v.items.len - 1]; __v.items.len -= 1; }", "_item", "null") },
    .{ "heapify", h.c("{}") },
    .{ "heapreplace", h.wrap2Blk("hrep", "const _old = __v0.items[0]; __v0.items[0] = __v1;", "_old", "null") },
    .{ "heappushpop", h.wrap2Blk("hpp", "if (__v1.items.len > 0 and __v1.items[0] < __v0) { const _old = __v1.items[0]; __v1.items[0] = __v0; }", "_old else __v0", "null") },
    .{ "nlargest", h.wrap2Blk("nlrg", "const _n = @as(usize, @intCast(__v0)); var _result: std.ArrayList(@TypeOf(__v1[0])) = .{}; for (__v1[0..@min(_n, __v1.len)]) |_item| { _result.append(__global_allocator, _item) catch unreachable; }", "_result.items", "&[_]@TypeOf(0){}") },
    .{ "nsmallest", h.wrap2Blk("nsm", "const _n = @as(usize, @intCast(__v0)); var _result: std.ArrayList(@TypeOf(__v1[0])) = .{}; for (__v1[0..@min(_n, __v1.len)]) |_item| { _result.append(__global_allocator, _item) catch unreachable; }", "_result.items", "&[_]@TypeOf(0){}") },
});
