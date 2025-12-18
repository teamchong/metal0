/// Python heapq module - Heap queue algorithm (priority queue)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "heappush", genHeappush },
    .{ "heappop", genHeappop },
    .{ "heapify", genHeapify },
    .{ "heapreplace", genHeapreplace },
    .{ "heappushpop", genHeappushpop },
    .{ "nlargest", genNlargest },
    .{ "nsmallest", genNsmallest },
    .{ "merge", h.wrap("", ".items", "&[_]i64{}") },
});

fn genHeappush(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("{}"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_hpush: {{ var _heap = ", .{id}); try self.genExpr(args[0]);
    try self.emit("; const _item = "); try self.genExpr(args[1]);
    try self.emitFmt("; _heap.append(__global_allocator, _item) catch unreachable; var _i = _heap.items.len - 1; while (_i > 0) {{ const _parent = (_i - 1) / 2; if (_heap.items[_i] >= _heap.items[_parent]) break; const tmp = _heap.items[_i]; _heap.items[_i] = _heap.items[_parent]; _heap.items[_parent] = tmp; _i = _parent; }} break :__m{d}_hpush; }})", .{id});
}

fn genHeappop(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("undefined"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_hpop: {{ var _heap = ", .{id}); try self.genExpr(args[0]);
    try self.emitFmt("; const _h = if (@typeInfo(@TypeOf(_heap)) == .@\"struct\" and @hasField(@TypeOf(_heap), \"items\")) _heap.items else &_heap; if (_h.len == 0) break :__m{d}_hpop @as(@TypeOf(_h[0]), undefined); const _result = _h[0]; break :__m{d}_hpop _result; }})", .{ id, id });
}

fn genHeapify(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("{}"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_hfy: {{ var _heap = ", .{id}); try self.genExpr(args[0]);
    try self.emitFmt("; const _h = if (@typeInfo(@TypeOf(_heap)) == .@\"struct\" and @hasField(@TypeOf(_heap), \"items\")) _heap.items else &_heap; if (_h.len <= 1) break :__m{d}_hfy; var _start = (_h.len - 2) / 2; while (true) {{ var _i = _start; while (true) {{ var _smallest = _i; const _left = 2 * _i + 1; const _right = 2 * _i + 2; if (_left < _h.len and _h[_left] < _h[_smallest]) _smallest = _left; if (_right < _h.len and _h[_right] < _h[_smallest]) _smallest = _right; if (_smallest == _i) break; const tmp = _h[_i]; _h[_i] = _h[_smallest]; _h[_smallest] = tmp; _i = _smallest; }} if (_start == 0) break; _start -= 1; }} break :__m{d}_hfy; }})", .{ id, id });
}

fn genHeapreplace(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("undefined"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_hrep: {{ var _heap = ", .{id}); try self.genExpr(args[0]);
    try self.emit("; const _item = "); try self.genExpr(args[1]);
    try self.emitFmt("; if (_heap.items.len == 0) break :__m{d}_hrep _item; const _result = _heap.items[0]; _heap.items[0] = _item; break :__m{d}_hrep _result; }})", .{ id, id });
}

fn genHeappushpop(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("undefined"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_hpp: {{ var _heap = ", .{id}); try self.genExpr(args[0]);
    try self.emit("; const _item = "); try self.genExpr(args[1]);
    try self.emitFmt("; if (_heap.items.len == 0 or _item <= _heap.items[0]) break :__m{d}_hpp _item; const _result = _heap.items[0]; _heap.items[0] = _item; break :__m{d}_hpp _result; }})", .{ id, id });
}

fn genNlargest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("&[_]i64{}"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_nlrg: {{ const _n: usize = @intCast(", .{id}); try self.genExpr(args[0]);
    try self.emit("); const _items = "); try self.genExpr(args[1]);
    try self.emitFmt(".items; var _sorted = __global_allocator.alloc(@TypeOf(_items[0]), _items.len) catch break :__m{d}_nlrg &[_]@TypeOf(_items[0]){{}}; @memcpy(_sorted, _items); std.mem.sort(@TypeOf(_items[0]), _sorted, {{}}, struct {{ fn cmp(_: void, a: anytype, b: anytype) bool {{ return a > b; }} }}.cmp); break :__m{d}_nlrg _sorted[0..@min(_n, _sorted.len)]; }})", .{ id, id });
}

fn genNsmallest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("&[_]i64{}"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_nsm: {{ const _n: usize = @intCast(", .{id}); try self.genExpr(args[0]);
    try self.emit("); const _items = "); try self.genExpr(args[1]);
    try self.emitFmt(".items; var _sorted = __global_allocator.alloc(@TypeOf(_items[0]), _items.len) catch break :__m{d}_nsm &[_]@TypeOf(_items[0]){{}}; @memcpy(_sorted, _items); std.mem.sort(@TypeOf(_items[0]), _sorted, {{}}, struct {{ fn cmp(_: void, a: anytype, b: anytype) bool {{ return a < b; }} }}.cmp); break :__m{d}_nsm _sorted[0..@min(_n, _sorted.len)]; }})", .{ id, id });
}
