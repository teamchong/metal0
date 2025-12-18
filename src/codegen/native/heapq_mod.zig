/// Python heapq module - Heap queue algorithm (priority queue)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
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
    try self.withInlineBlock("hpush", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("var _heap = "); try c.genExpr(a[0]);
            try c.emit("; const _item = "); try c.genExpr(a[1]);
            try c.emitFmt("; _heap.append(__global_allocator, _item) catch unreachable; var _i = _heap.items.len - 1; while (_i > 0) {{ const _parent = (_i - 1) / 2; if (_heap.items[_i] >= _heap.items[_parent]) break; const tmp = _heap.items[_i]; _heap.items[_i] = _heap.items[_parent]; _heap.items[_parent] = tmp; _i = _parent; }} break :{s}; ", .{label});
        }
    }.emit);
}

fn genHeappop(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("undefined"); return; }
    try self.withInlineBlock("hpop", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("var _heap = "); try c.genExpr(a[0]);
            try c.emitFmt("; const _h = if (@typeInfo(@TypeOf(_heap)) == .@\"struct\" and @hasField(@TypeOf(_heap), \"items\")) _heap.items else &_heap; if (_h.len == 0) break :{s} @as(@TypeOf(_h[0]), undefined); const _result = _h[0]; break :{s} _result; ", .{ label, label });
        }
    }.emit);
}

fn genHeapify(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("{}"); return; }
    try self.withInlineBlock("hfy", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("var _heap = "); try c.genExpr(a[0]);
            try c.emitFmt("; const _h = if (@typeInfo(@TypeOf(_heap)) == .@\"struct\" and @hasField(@TypeOf(_heap), \"items\")) _heap.items else &_heap; if (_h.len <= 1) break :{s}; var _start = (_h.len - 2) / 2; while (true) {{ var _i = _start; while (true) {{ var _smallest = _i; const _left = 2 * _i + 1; const _right = 2 * _i + 2; if (_left < _h.len and _h[_left] < _h[_smallest]) _smallest = _left; if (_right < _h.len and _h[_right] < _h[_smallest]) _smallest = _right; if (_smallest == _i) break; const tmp = _h[_i]; _h[_i] = _h[_smallest]; _h[_smallest] = tmp; _i = _smallest; }} if (_start == 0) break; _start -= 1; }} break :{s}; ", .{ label, label });
        }
    }.emit);
}

fn genHeapreplace(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("undefined"); return; }
    try self.withInlineBlock("hrep", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("var _heap = "); try c.genExpr(a[0]);
            try c.emit("; const _item = "); try c.genExpr(a[1]);
            try c.emitFmt("; if (_heap.items.len == 0) break :{s} _item; const _result = _heap.items[0]; _heap.items[0] = _item; break :{s} _result; ", .{ label, label });
        }
    }.emit);
}

fn genHeappushpop(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("undefined"); return; }
    try self.withInlineBlock("hpp", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("var _heap = "); try c.genExpr(a[0]);
            try c.emit("; const _item = "); try c.genExpr(a[1]);
            try c.emitFmt("; if (_heap.items.len == 0 or _item <= _heap.items[0]) break :{s} _item; const _result = _heap.items[0]; _heap.items[0] = _item; break :{s} _result; ", .{ label, label });
        }
    }.emit);
}

fn genNlargest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("&[_]i64{}"); return; }
    try self.withInlineBlock("nlrg", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _n: usize = @intCast("); try c.genExpr(a[0]);
            try c.emit("); const _items = "); try c.genExpr(a[1]);
            try c.emitFmt(".items; var _sorted = __global_allocator.alloc(@TypeOf(_items[0]), _items.len) catch break :{s} &[_]@TypeOf(_items[0]){{}}; @memcpy(_sorted, _items); std.mem.sort(@TypeOf(_items[0]), _sorted, {{}}, struct {{ fn cmp(_: void, a1: anytype, b1: anytype) bool {{ return a1 > b1; }} }}.cmp); break :{s} _sorted[0..@min(_n, _sorted.len)]; ", .{ label, label });
        }
    }.emit);
}

fn genNsmallest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("&[_]i64{}"); return; }
    try self.withInlineBlock("nsm", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _n: usize = @intCast("); try c.genExpr(a[0]);
            try c.emit("); const _items = "); try c.genExpr(a[1]);
            try c.emitFmt(".items; var _sorted = __global_allocator.alloc(@TypeOf(_items[0]), _items.len) catch break :{s} &[_]@TypeOf(_items[0]){{}}; @memcpy(_sorted, _items); std.mem.sort(@TypeOf(_items[0]), _sorted, {{}}, struct {{ fn cmp(_: void, a1: anytype, b1: anytype) bool {{ return a1 < b1; }} }}.cmp); break :{s} _sorted[0..@min(_n, _sorted.len)]; ", .{ label, label });
        }
    }.emit);
}
