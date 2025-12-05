/// Python itertools module - chain, cycle, repeat, count, zip_longest, etc.
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;
const producesBlockExpression = @import("expressions.zig").producesBlockExpression;

fn needsItems(self: *NativeCodegen, arg: ast.Node) bool {
    const t = self.type_inferrer.inferExpr(arg) catch return false;
    return t == .list or t == .deque;
}

fn predFilter(self: *NativeCodegen, args: []ast.Node, comptime label: []const u8, comptime body: []const u8) CodegenError!void {
    if (args.len < 2) { try self.emit("std.ArrayList(i64){}"); return; }
    try self.emit(label ++ "_blk: { const _pred = "); try self.genExpr(args[0]);
    try self.emit("; const _iter = ");
    // Use emitIter to handle block expressions properly
    try emitIter(self, args[1]);
    try self.emit("; var _result = std.ArrayList(@TypeOf(_iter[0])){}; " ++ body ++ " break :" ++ label ++ "_blk _result; }");
}
fn emitIter(self: *NativeCodegen, arg: ast.Node) CodegenError!void {
    // Check if this is a range() call - generate native Zig range instead of PyObject
    if (arg == .call) {
        const call = arg.call;
        if (call.func.* == .name and std.mem.eql(u8, call.func.name.id, "range")) {
            try emitNativeRange(self, call.args);
            return;
        }
    }

    // Use runtime.iterSlice universally - it handles:
    // - ArrayList (extracts .items)
    // - PyValue (extracts .list or .tuple slice)
    // - Regular slices (returns as-is)
    // This is safer than trying to detect specific types
    try self.emit("runtime.iterSlice(");
    try self.genExpr(arg);
    try self.emit(")");
}

/// Generate a native Zig slice for range(start, stop, step)
fn emitNativeRange(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Generate a comptime-friendly range: &[_]i64{start..stop} or runtime ArrayList
    // For simplicity, generate a block that builds an ArrayList
    try self.emit("(range_slice_blk: { var __rs = std.ArrayList(i64){}; ");
    if (args.len == 0) {
        try self.emit("break :range_slice_blk __rs.items; })");
        return;
    }

    // Determine start, stop, step
    if (args.len == 1) {
        // range(stop): 0..stop, step=1
        try self.emit("var __i: i64 = 0; while (__i < ");
        try self.genExpr(args[0]);
        try self.emit(") : (__i += 1) { __rs.append(__global_allocator, __i) catch continue; }");
    } else if (args.len >= 2) {
        // range(start, stop) or range(start, stop, step)
        try self.emit("var __i: i64 = ");
        try self.genExpr(args[0]);
        try self.emit("; const __stop: i64 = ");
        try self.genExpr(args[1]);
        try self.emit("; const __step: i64 = ");
        if (args.len >= 3) {
            try self.genExpr(args[2]);
        } else {
            try self.emit("1");
        }
        try self.emit("; while (if (__step > 0) __i < __stop else __i > __stop) : (__i += __step) { __rs.append(__global_allocator, __i) catch continue; }");
    }
    try self.emit(" break :range_slice_blk __rs.items; })");
}

const pt = h.pass("std.ArrayList(i64){}");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "chain", genChain }, .{ "repeat", genRepeat }, .{ "count", genCount },
    .{ "cycle", genCycle }, .{ "islice", genIslice }, .{ "enumerate", genEnumerate },
    .{ "zip_longest", genZipLongest }, .{ "product", genProduct }, .{ "permutations", genPermutations },
    .{ "combinations", genCombinations }, .{ "groupby", genGroupby },
    .{ "takewhile", genTakewhile }, .{ "dropwhile", genDropwhile }, .{ "filterfalse", genFilterfalse },
    .{ "accumulate", genAccumulate }, .{ "starmap", genStarmap }, .{ "compress", genCompress },
    .{ "tee", genTee }, .{ "pairwise", genPairwise },
    .{ "batched", genBatched }, .{ "combinations_with_replacement", genCombinationsWithReplacement },
});

fn genTakewhile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try predFilter(self, args, "takewhile", "for (_iter) |item| { if (!_pred(item)) break; _result.append(__global_allocator, item) catch continue; }");
}
fn genDropwhile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try predFilter(self, args, "dropwhile", "var _dropping = true; for (_iter) |item| { if (_dropping and _pred(item)) continue; _dropping = false; _result.append(__global_allocator, item) catch continue; }");
}
fn genFilterfalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try predFilter(self, args, "filterfalse", "for (_iter) |item| { if (!_pred(item)) _result.append(__global_allocator, item) catch continue; }");
}

pub fn genChain(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("std.ArrayList(i64){}"); return; }
    try self.emit("chain_blk: { var _result = std.ArrayList(i64){}; ");
    for (args) |arg| { try self.emit("for ("); try emitIter(self, arg); try self.emit(") |item| { _result.append(__global_allocator, item) catch continue; } "); }
    try self.emit("break :chain_blk _result; }");
}

pub fn genRepeat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("repeat_blk: { var _result = std.ArrayList(i64){}; ");
    if (args.len > 1) {
        try self.emit("var _i: usize = 0; while (_i < @as(usize, @intCast("); try self.genExpr(args[1]);
        try self.emit("))) : (_i += 1) { _result.append(__global_allocator, "); try self.genExpr(args[0]); try self.emit(") catch continue; }");
    } else { try self.emit("_result.append(__global_allocator, "); try self.genExpr(args[0]); try self.emit(") catch {};"); }
    try self.emit(" break :repeat_blk _result; }");
}

pub fn genCount(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("count_blk: { const _start = ");
    if (args.len >= 1) try self.genExpr(args[0]) else try self.emit("@as(i64, 0)");
    try self.emit("; const _step = ");
    if (args.len >= 2) try self.genExpr(args[1]) else try self.emit("@as(i64, 1)");
    try self.emit("; break :count_blk .{ .start = _start, .step = _step }; }");
}

pub fn genIslice(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("std.ArrayList(i64){}");
        return;
    }
    try self.emit("islice_blk: { const _iter = ");
    try emitIter(self, args[0]);
    try self.emit("; const _stop = @as(usize, @intCast(");
    try self.genExpr(args[1]);
    try self.emit(")); var _result = std.ArrayList(@TypeOf(_iter[0])){}; for (_iter[0..@min(_stop, _iter.len)]) |item| { _result.append(__global_allocator, item) catch continue; } break :islice_blk _result; }");
}

pub fn genZipLongest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("std.ArrayList(struct { @\"0\": i64 }){}"); return; }
    if (args.len >= 2) {
        try self.emit("zip_longest_blk: { const _a = "); try self.genExpr(args[0]);
        try self.emit("; const _b = "); try self.genExpr(args[1]);
        try self.emit("; const _len = @max(_a.items.len, _b.items.len); var _result = std.ArrayList(struct { @\"0\": i64, @\"1\": i64 }){}; for (0.._len) |i| { const _va = if (i < _a.items.len) _a.items[i] else 0; const _vb = if (i < _b.items.len) _b.items[i] else 0; _result.append(__global_allocator, .{ .@\"0\" = _va, .@\"1\" = _vb }) catch continue; } break :zip_longest_blk _result; }");
    } else try self.genExpr(args[0]);
}

fn genAccumulate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("std.ArrayList(i64){}"); return; }
    try self.emit("accumulate_blk: { const _iter = "); try emitIter(self, args[0]);
    try self.emit("; var _result = std.ArrayList(@TypeOf(_iter[0])){}; var _acc: @TypeOf(_iter[0]) = _iter[0]; _result.append(__global_allocator, _acc) catch {}; for (_iter[1..]) |item| { _acc = ");
    if (args.len > 1) { try self.genExpr(args[1]); try self.emit("(_acc, item)"); } else try self.emit("_acc + item");
    try self.emit("; _result.append(__global_allocator, _acc) catch continue; } break :accumulate_blk _result; }");
}

fn genStarmap(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("std.ArrayList(i64){}"); return; }
    try self.emit("starmap_blk: { const _func = "); try self.genExpr(args[0]);
    try self.emit("; const _iter = "); try emitIter(self, args[1]);
    try self.emit("; var _result = std.ArrayList(@TypeOf(_func(_iter[0].@\"0\", _iter[0].@\"1\"))){}; for (_iter) |item| { _result.append(__global_allocator, _func(item.@\"0\", item.@\"1\")) catch continue; } break :starmap_blk _result; }");
}

fn genCompress(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("std.ArrayList(i64){}"); return; }
    try self.emit("compress_blk: { const _data = "); try emitIter(self, args[0]);
    try self.emit("; const _selectors = "); try emitIter(self, args[1]);
    try self.emit("; var _result = std.ArrayList(@TypeOf(_data[0])){}; const _len = @min(_data.len, _selectors.len); for (0.._len) |i| { if (_selectors[i] != 0) _result.append(__global_allocator, _data[i]) catch continue; } break :compress_blk _result; }");
}

fn genTee(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit(".{ std.ArrayList(i64){}, std.ArrayList(i64){} }"); return; }
    try self.emit(".{ "); try self.genExpr(args[0]); try self.emit(", "); try self.genExpr(args[0]); try self.emit(" }");
}

fn genPairwise(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("std.ArrayList(struct { @\"0\": i64, @\"1\": i64 }){}"); return; }
    try self.emit("pairwise_blk: { const _iter = "); try emitIter(self, args[0]);
    try self.emit("; var _result = std.ArrayList(struct { @\"0\": @TypeOf(_iter[0]), @\"1\": @TypeOf(_iter[0]) }){}; if (_iter.len > 1) { for (0.._iter.len - 1) |i| { _result.append(__global_allocator, .{ .@\"0\" = _iter[i], .@\"1\" = _iter[i + 1] }) catch continue; } } break :pairwise_blk _result; }");
}

/// itertools.cycle(iterable) - cycle through iterable indefinitely (returns slice for bounded use)
fn genCycle(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("std.ArrayList(i64){}"); return; }
    // Return the iterable directly (caller expected to handle cycling in loop)
    try emitIter(self, args[0]);
}

/// itertools.enumerate(iterable, start=0) - already handled in for_special.zig, just return iterable here
fn genEnumerate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("std.ArrayList(i64){}"); return; }
    try emitIter(self, args[0]);
}

/// itertools.product(*iterables, repeat=1) - Cartesian product
fn genProduct(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("std.ArrayList(struct { @\"0\": i64 }){}"); return; }
    if (args.len == 1) {
        // Single iterable: wrap each element in a tuple
        try self.emit("product1_blk: {\n const _a = "); try emitIter(self, args[0]);
        try self.emit(";\n var _result = std.ArrayList(struct { @\"0\": @TypeOf(_a[0]) }){};\n ");
        try self.emit("for (_a) |item| { _result.append(__global_allocator, .{ .@\"0\" = item }) catch continue; }\n ");
        try self.emit("break :product1_blk _result;\n }");
        return;
    }
    // Two iterables: Cartesian product
    try self.emit("product2_blk: {\n const _a = "); try emitIter(self, args[0]);
    try self.emit(";\n const _b = "); try emitIter(self, args[1]);
    try self.emit(";\n var _result = std.ArrayList(struct { @\"0\": @TypeOf(_a[0]), @\"1\": @TypeOf(_b[0]) }){};\n ");
    try self.emit("for (_a) |a| { for (_b) |b| { _result.append(__global_allocator, .{ .@\"0\" = a, .@\"1\" = b }) catch continue; } }\n ");
    try self.emit("break :product2_blk _result;\n }");
}

/// itertools.permutations(iterable, r=None) - r-length permutations
fn genPermutations(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("std.ArrayList(struct { @\"0\": i64, @\"1\": i64 }){}"); return; }
    // Generate 2-permutations (most common case)
    try self.emit("perms_blk: { const _iter = "); try emitIter(self, args[0]);
    try self.emit("; var _result = std.ArrayList(struct { @\"0\": @TypeOf(_iter[0]), @\"1\": @TypeOf(_iter[0]) }){}; ");
    try self.emit("for (_iter, 0..) |a, i| { for (_iter, 0..) |b, j| { if (i != j) _result.append(__global_allocator, .{ .@\"0\" = a, .@\"1\" = b }) catch continue; } } ");
    try self.emit("break :perms_blk _result; }");
}

/// itertools.combinations(iterable, r) - r-length combinations
fn genCombinations(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("std.ArrayList(struct { @\"0\": i64, @\"1\": i64 }){}"); return; }
    // Generate 2-combinations (most common case)
    try self.emit("combs_blk: { const _iter = "); try emitIter(self, args[0]);
    try self.emit("; var _result = std.ArrayList(struct { @\"0\": @TypeOf(_iter[0]), @\"1\": @TypeOf(_iter[0]) }){}; ");
    try self.emit("for (_iter[0.._iter.len -| 1], 0..) |a, i| { for (_iter[i + 1..]) |b| { _result.append(__global_allocator, .{ .@\"0\" = a, .@\"1\" = b }) catch continue; } } ");
    try self.emit("break :combs_blk _result; }");
}

/// itertools.combinations_with_replacement(iterable, r) - r-length combinations with replacement
fn genCombinationsWithReplacement(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("std.ArrayList(struct { @\"0\": i64, @\"1\": i64 }){}"); return; }
    try self.emit("combswr_blk: { const _iter = "); try emitIter(self, args[0]);
    try self.emit("; var _result = std.ArrayList(struct { @\"0\": @TypeOf(_iter[0]), @\"1\": @TypeOf(_iter[0]) }){}; ");
    try self.emit("for (_iter, 0..) |a, i| { for (_iter[i..]) |b| { _result.append(__global_allocator, .{ .@\"0\" = a, .@\"1\" = b }) catch continue; } } ");
    try self.emit("break :combswr_blk _result; }");
}

/// itertools.groupby(iterable, key=None) - group consecutive equal elements
fn genGroupby(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("std.ArrayList(struct { key: i64, group: std.ArrayList(i64) }){}"); return; }
    try self.emit("groupby_blk: { const _iter = "); try emitIter(self, args[0]);
    try self.emit("; var _result = std.ArrayList(struct { key: @TypeOf(_iter[0]), group: std.ArrayList(@TypeOf(_iter[0])) }){}; ");
    try self.emit("if (_iter.len > 0) { var _cur_key = _iter[0]; var _cur_group = std.ArrayList(@TypeOf(_iter[0])){}; ");
    try self.emit("for (_iter) |item| { if (item == _cur_key) { _cur_group.append(__global_allocator, item) catch continue; } ");
    try self.emit("else { _result.append(__global_allocator, .{ .key = _cur_key, .group = _cur_group }) catch {}; _cur_key = item; _cur_group = std.ArrayList(@TypeOf(_iter[0])){}; _cur_group.append(__global_allocator, item) catch {}; } } ");
    try self.emit("_result.append(__global_allocator, .{ .key = _cur_key, .group = _cur_group }) catch {}; } ");
    try self.emit("break :groupby_blk _result; }");
}

/// itertools.batched(iterable, n) - batch iterable into tuples of size n
fn genBatched(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("std.ArrayList(std.ArrayList(i64)){}"); return; }
    try self.emit("batched_blk: { const _iter = "); try emitIter(self, args[0]);
    try self.emit("; const _n = @as(usize, @intCast("); try self.genExpr(args[1]);
    try self.emit(")); var _result = std.ArrayList(std.ArrayList(@TypeOf(_iter[0]))){}; ");
    try self.emit("var _i: usize = 0; while (_i < _iter.len) : (_i += _n) { var _batch = std.ArrayList(@TypeOf(_iter[0])){}; ");
    try self.emit("const _end = @min(_i + _n, _iter.len); for (_iter[_i.._end]) |item| { _batch.append(__global_allocator, item) catch continue; } ");
    try self.emit("_result.append(__global_allocator, _batch) catch continue; } ");
    try self.emit("break :batched_blk _result; }");
}
