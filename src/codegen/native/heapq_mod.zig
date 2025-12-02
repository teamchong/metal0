/// Python heapq module - Heap queue algorithm (priority queue)
const std = @import("std");
const h = @import("mod_helper.zig");

const heapTypeCheck = "; const _h = if (@typeInfo(@TypeOf(_heap)) == .@\"struct\" and @hasField(@TypeOf(_heap), \"items\")) _heap.items else &_heap;";
const heappushBody = "; _heap.append(__global_allocator, _item) catch {}; var _i = _heap.items.len - 1; while (_i > 0) { const _parent = (_i - 1) / 2; if (_heap.items[_i] >= _heap.items[_parent]) break; const tmp = _heap.items[_i]; _heap.items[_i] = _heap.items[_parent]; _heap.items[_parent] = tmp; _i = _parent; } break :blk; }";
const heapifyBody = " if (_h.len <= 1) break :blk; var _start = (_h.len - 2) / 2; while (true) { var _i = _start; while (true) { var _smallest = _i; const _left = 2 * _i + 1; const _right = 2 * _i + 2; if (_left < _h.len and _h[_left] < _h[_smallest]) _smallest = _left; if (_right < _h.len and _h[_right] < _h[_smallest]) _smallest = _right; if (_smallest == _i) break; const tmp = _h[_i]; _h[_i] = _h[_smallest]; _h[_smallest] = tmp; _i = _smallest; } if (_start == 0) break; _start -= 1; } break :blk; }";
const nlargestBody = ".items; var _sorted = __global_allocator.alloc(@TypeOf(_items[0]), _items.len) catch break :blk &[_]@TypeOf(_items[0]){}; @memcpy(_sorted, _items); std.mem.sort(@TypeOf(_items[0]), _sorted, {}, struct { fn cmp(_: void, a: anytype, b: anytype) bool { return a > b; } }.cmp); break :blk _sorted[0..@min(_n, _sorted.len)]; }";
const nsmallestBody = ".items; var _sorted = __global_allocator.alloc(@TypeOf(_items[0]), _items.len) catch break :blk &[_]@TypeOf(_items[0]){}; @memcpy(_sorted, _items); std.mem.sort(@TypeOf(_items[0]), _sorted, {}, struct { fn cmp(_: void, a: anytype, b: anytype) bool { return a < b; } }.cmp); break :blk _sorted[0..@min(_n, _sorted.len)]; }";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "heappush", h.wrap2("blk: { var _heap = ", "; const _item = ", heappushBody, "{}") },
    .{ "heappop", h.wrap("blk: { var _heap = ", heapTypeCheck ++ " if (_h.len == 0) break :blk @as(@TypeOf(_h[0]), undefined); const _result = _h[0]; break :blk _result; }", "undefined") },
    .{ "heapify", h.wrap("blk: { var _heap = ", heapTypeCheck ++ heapifyBody, "{}") },
    .{ "heapreplace", h.wrap2("blk: { var _heap = ", "; const _item = ", "; if (_heap.items.len == 0) break :blk _item; const _result = _heap.items[0]; _heap.items[0] = _item; break :blk _result; }", "undefined") },
    .{ "heappushpop", h.wrap2("blk: { var _heap = ", "; const _item = ", "; if (_heap.items.len == 0 or _item <= _heap.items[0]) break :blk _item; const _result = _heap.items[0]; _heap.items[0] = _item; break :blk _result; }", "undefined") },
    .{ "nlargest", h.wrap2("blk: { const _n: usize = @intCast(", "); const _items = ", nlargestBody, "&[_]i64{}") },
    .{ "nsmallest", h.wrap2("blk: { const _n: usize = @intCast(", "); const _items = ", nsmallestBody, "&[_]i64{}") },
    .{ "merge", h.wrap("", ".items", "&[_]i64{}") },
});

