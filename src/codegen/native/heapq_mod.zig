/// Python heapq module - Heap queue algorithm (priority queue)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate heapq.heappush(heap, item) -> None
pub fn genHeappush(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("heapq_push_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var _heap = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _item = ");
    try self.genExpr(args[1]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("_heap.append(__global_allocator, _item) catch {};\n");
    try self.emitIndent();
    try self.emit("var _i = _heap.items.len - 1;\n");
    try self.emitIndent();
    try self.emit("while (_i > 0) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _parent = (_i - 1) / 2;\n");
    try self.emitIndent();
    try self.emit("if (_heap.items[_i] >= _heap.items[_parent]) break;\n");
    try self.emitIndent();
    try self.emit("const tmp = _heap.items[_i];\n");
    try self.emitIndent();
    try self.emit("_heap.items[_i] = _heap.items[_parent];\n");
    try self.emitIndent();
    try self.emit("_heap.items[_parent] = tmp;\n");
    try self.emitIndent();
    try self.emit("_i = _parent;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :heapq_push_blk;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate heapq.heappop(heap) -> item
pub fn genHeappop(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("heapq_pop_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var _heap = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("if (_heap.items.len == 0) break :heapq_pop_blk @as(@TypeOf(_heap.items[0]), undefined);\n");
    try self.emitIndent();
    try self.emit("const _result = _heap.items[0];\n");
    try self.emitIndent();
    try self.emit("_heap.items[0] = _heap.pop();\n");
    try self.emitIndent();
    try self.emit("var _i: usize = 0;\n");
    try self.emitIndent();
    try self.emit("while (true) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var _smallest = _i;\n");
    try self.emitIndent();
    try self.emit("const _left = 2 * _i + 1;\n");
    try self.emitIndent();
    try self.emit("const _right = 2 * _i + 2;\n");
    try self.emitIndent();
    try self.emit("if (_left < _heap.items.len and _heap.items[_left] < _heap.items[_smallest]) _smallest = _left;\n");
    try self.emitIndent();
    try self.emit("if (_right < _heap.items.len and _heap.items[_right] < _heap.items[_smallest]) _smallest = _right;\n");
    try self.emitIndent();
    try self.emit("if (_smallest == _i) break;\n");
    try self.emitIndent();
    try self.emit("const tmp = _heap.items[_i];\n");
    try self.emitIndent();
    try self.emit("_heap.items[_i] = _heap.items[_smallest];\n");
    try self.emitIndent();
    try self.emit("_heap.items[_smallest] = tmp;\n");
    try self.emitIndent();
    try self.emit("_i = _smallest;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :heapq_pop_blk _result;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate heapq.heapify(x) -> None
pub fn genHeapify(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("heapq_heapify_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var _heap = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("if (_heap.items.len <= 1) break :heapq_heapify_blk;\n");
    try self.emitIndent();
    try self.emit("var _start = (_heap.items.len - 2) / 2;\n");
    try self.emitIndent();
    try self.emit("while (true) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var _i = _start;\n");
    try self.emitIndent();
    try self.emit("while (true) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var _smallest = _i;\n");
    try self.emitIndent();
    try self.emit("const _left = 2 * _i + 1;\n");
    try self.emitIndent();
    try self.emit("const _right = 2 * _i + 2;\n");
    try self.emitIndent();
    try self.emit("if (_left < _heap.items.len and _heap.items[_left] < _heap.items[_smallest]) _smallest = _left;\n");
    try self.emitIndent();
    try self.emit("if (_right < _heap.items.len and _heap.items[_right] < _heap.items[_smallest]) _smallest = _right;\n");
    try self.emitIndent();
    try self.emit("if (_smallest == _i) break;\n");
    try self.emitIndent();
    try self.emit("const tmp = _heap.items[_i];\n");
    try self.emitIndent();
    try self.emit("_heap.items[_i] = _heap.items[_smallest];\n");
    try self.emitIndent();
    try self.emit("_heap.items[_smallest] = tmp;\n");
    try self.emitIndent();
    try self.emit("_i = _smallest;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("if (_start == 0) break;\n");
    try self.emitIndent();
    try self.emit("_start -= 1;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :heapq_heapify_blk;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate heapq.heapreplace(heap, item) -> old_item
pub fn genHeapreplace(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("heapq_replace_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var _heap = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _item = ");
    try self.genExpr(args[1]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("if (_heap.items.len == 0) break :heapq_replace_blk _item;\n");
    try self.emitIndent();
    try self.emit("const _result = _heap.items[0];\n");
    try self.emitIndent();
    try self.emit("_heap.items[0] = _item;\n");
    try self.emitIndent();
    try self.emit("break :heapq_replace_blk _result;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate heapq.heappushpop(heap, item) -> smallest
pub fn genHeappushpop(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("heapq_pushpop_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var _heap = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _item = ");
    try self.genExpr(args[1]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("if (_heap.items.len == 0 or _item <= _heap.items[0]) break :heapq_pushpop_blk _item;\n");
    try self.emitIndent();
    try self.emit("const _result = _heap.items[0];\n");
    try self.emitIndent();
    try self.emit("_heap.items[0] = _item;\n");
    try self.emitIndent();
    try self.emit("break :heapq_pushpop_blk _result;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate heapq.nlargest(n, iterable, key=None) -> list
pub fn genNlargest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("heapq_nlargest_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _n: usize = @intCast(");
    try self.genExpr(args[0]);
    try self.emit(");\n");
    try self.emitIndent();
    try self.emit("const _items = ");
    try self.genExpr(args[1]);
    try self.emit(".items;\n");
    try self.emitIndent();
    try self.emit("var _sorted = __global_allocator.alloc(@TypeOf(_items[0]), _items.len) catch break :heapq_nlargest_blk &[_]@TypeOf(_items[0]){};\n");
    try self.emitIndent();
    try self.emit("@memcpy(_sorted, _items);\n");
    try self.emitIndent();
    try self.emit("std.mem.sort(@TypeOf(_items[0]), _sorted, {}, struct { fn cmp(_: void, a: anytype, b: anytype) bool { return a > b; } }.cmp);\n");
    try self.emitIndent();
    try self.emit("break :heapq_nlargest_blk _sorted[0..@min(_n, _sorted.len)];\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate heapq.nsmallest(n, iterable, key=None) -> list
pub fn genNsmallest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("heapq_nsmallest_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _n: usize = @intCast(");
    try self.genExpr(args[0]);
    try self.emit(");\n");
    try self.emitIndent();
    try self.emit("const _items = ");
    try self.genExpr(args[1]);
    try self.emit(".items;\n");
    try self.emitIndent();
    try self.emit("var _sorted = __global_allocator.alloc(@TypeOf(_items[0]), _items.len) catch break :heapq_nsmallest_blk &[_]@TypeOf(_items[0]){};\n");
    try self.emitIndent();
    try self.emit("@memcpy(_sorted, _items);\n");
    try self.emitIndent();
    try self.emit("std.mem.sort(@TypeOf(_items[0]), _sorted, {}, struct { fn cmp(_: void, a: anytype, b: anytype) bool { return a < b; } }.cmp);\n");
    try self.emitIndent();
    try self.emit("break :heapq_nsmallest_blk _sorted[0..@min(_n, _sorted.len)];\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate heapq.merge(*iterables, key=None, reverse=False) -> iterator
pub fn genMerge(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Simplified: just return first iterable
    if (args.len == 0) {
        try self.emit("&[_]i64{}");
        return;
    }
    try self.genExpr(args[0]);
    try self.emit(".items");
}
