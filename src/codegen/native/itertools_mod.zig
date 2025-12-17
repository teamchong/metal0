/// Python itertools module - chain, cycle, repeat, count, zip_longest, etc.
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;
const producesBlockExpression = @import("expressions.zig").producesBlockExpression;
const container_traits = @import("../../analysis/traits/container_traits.zig");

fn needsItems(self: *NativeCodegen, arg: ast.Node) bool {
    const t = self.type_inferrer.inferExpr(arg) catch return false;
    return container_traits.isList(t) or t == .deque;
}

fn predFilter(self: *NativeCodegen, args: []ast.Node, comptime hint: []const u8, comptime body: []const u8) CodegenError!void {
    if (args.len < 2) { try self.emit("std.ArrayListUnmanaged(i64){}"); return; }
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_" ++ hint ++ ": {{ const _pred = ", .{id}); try self.genExpr(args[0]);
    try self.emit("; const _iter = ");
    // Use emitIter to handle block expressions properly
    try emitIter(self, args[1]);
    try self.emit("; var _result = std.ArrayListUnmanaged(@TypeOf(_iter[0])){}; " ++ body);
    try self.emitFmt(" break :__m{d}_" ++ hint ++ " _result; }}", .{id});
}
pub fn emitIter(self: *NativeCodegen, arg: ast.Node) CodegenError!void {
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
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_range: {{ var __rs = std.ArrayListUnmanaged(i64){{}}; ", .{id});
    if (args.len == 0) {
        try self.emitFmt("break :__m{d}_range __rs.items; }})", .{id});
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
    try self.emitFmt(" break :__m{d}_range __rs.items; }})", .{id});
}

const pt = h.pass("std.ArrayListUnmanaged(i64){}");

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
    if (args.len == 0) { try self.emit("std.ArrayListUnmanaged(i64){}"); return; }
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_chain: {{ var _result = std.ArrayListUnmanaged(i64){{}}; ", .{id});
    for (args) |arg| { try self.emit("for ("); try emitIter(self, arg); try self.emit(") |item| { _result.append(__global_allocator, item) catch continue; } "); }
    try self.emitFmt("break :__m{d}_chain _result; }}", .{id});
}

pub fn genRepeat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // repeat() with no arguments raises TypeError - generate error for assertRaises
    if (args.len == 0) {
        try self.emit("return error.TypeError");
        return;
    }
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_repeat: {{ var _result = std.ArrayListUnmanaged(i64){{}}; ", .{id});
    if (args.len > 1) {
        try self.emit("var _i: usize = 0; while (_i < @as(usize, @intCast("); try self.genExpr(args[1]);
        try self.emit("))) : (_i += 1) { _result.append(__global_allocator, "); try self.genExpr(args[0]); try self.emit(") catch continue; }");
    } else { try self.emit("_result.append(__global_allocator, "); try self.genExpr(args[0]); try self.emit(") catch unreachable;"); }
    try self.emitFmt(" break :__m{d}_repeat _result; }}", .{id});
}

pub fn genCount(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_count: {{ const _start = ", .{id});
    if (args.len >= 1) try self.genExpr(args[0]) else try self.emit("@as(i64, 0)");
    try self.emit("; const _step = ");
    if (args.len >= 2) try self.genExpr(args[1]) else try self.emit("@as(i64, 1)");
    try self.emitFmt("; break :__m{d}_count .{{ .start = _start, .step = _step }}; }}", .{id});
}

pub fn genIslice(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("std.ArrayListUnmanaged(i64){}");
        return;
    }
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_islice: {{ const _iter = ", .{id});
    try emitIter(self, args[0]);
    try self.emit("; const _stop = @as(usize, @intCast(");
    try self.genExpr(args[1]);
    try self.emitFmt(")); var _result = std.ArrayListUnmanaged(@TypeOf(_iter[0])){{}}; for (_iter[0..@min(_stop, _iter.len)]) |item| {{ _result.append(__global_allocator, item) catch continue; }} break :__m{d}_islice _result; }}", .{id});
}

pub fn genZipLongest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("std.ArrayListUnmanaged(struct { @\"0\": i64 }){}"); return; }
    if (args.len >= 2) {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_zip_longest: {{ const _a = ", .{id}); try self.genExpr(args[0]);
        try self.emit("; const _b = "); try self.genExpr(args[1]);
        try self.emitFmt("; const _len = @max(_a.items.len, _b.items.len); var _result = std.ArrayListUnmanaged(struct {{ @\"0\": i64, @\"1\": i64 }}){{}}; for (0.._len) |i| {{ const _va = if (i < _a.items.len) _a.items[i] else 0; const _vb = if (i < _b.items.len) _b.items[i] else 0; _result.append(__global_allocator, .{{ .@\"0\" = _va, .@\"1\" = _vb }}) catch continue; }} break :__m{d}_zip_longest _result; }}", .{id});
    } else try self.genExpr(args[0]);
}

fn genAccumulate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("std.ArrayListUnmanaged(i64){}"); return; }
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_accumulate: {{ const _iter = ", .{id}); try emitIter(self, args[0]);
    try self.emit("; var _result = std.ArrayListUnmanaged(@TypeOf(_iter[0])){}; var _acc: @TypeOf(_iter[0]) = _iter[0]; _result.append(__global_allocator, _acc) catch unreachable; for (_iter[1..]) |item| { _acc = ");
    if (args.len > 1) { try self.genExpr(args[1]); try self.emit("(_acc, item)"); } else try self.emit("_acc + item");
    try self.emitFmt("; _result.append(__global_allocator, _acc) catch continue; }} break :__m{d}_accumulate _result; }}", .{id});
}

fn genStarmap(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("std.ArrayListUnmanaged(i64){}"); return; }
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_starmap: {{ const _func = ", .{id}); try self.genExpr(args[0]);
    try self.emit("; const _iter = "); try emitIter(self, args[1]);
    try self.emitFmt("; var _result = std.ArrayListUnmanaged(@TypeOf(_func(_iter[0].@\"0\", _iter[0].@\"1\"))){{}}; for (_iter) |item| {{ _result.append(__global_allocator, _func(item.@\"0\", item.@\"1\")) catch continue; }} break :__m{d}_starmap _result; }}", .{id});
}

fn genCompress(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("std.ArrayListUnmanaged(i64){}"); return; }
    // Use runtime helper to avoid comptime explosion
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_compress: {{ const _data = ", .{id}); try emitIter(self, args[0]);
    try self.emit("; const _selectors = "); try emitIter(self, args[1]);
    try self.emitFmt("; break :__m{d}_compress (try runtime.itertools_ops.compress(@TypeOf(_data[0]), __global_allocator, _data, _selectors)).items; }}", .{id});
}

fn genTee(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit(".{ std.ArrayListUnmanaged(i64){}, std.ArrayListUnmanaged(i64){} }"); return; }
    try self.emit(".{ "); try self.genExpr(args[0]); try self.emit(", "); try self.genExpr(args[0]); try self.emit(" }");
}

fn genPairwise(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("std.ArrayListUnmanaged(struct { @\"0\": i64, @\"1\": i64 }){}"); return; }
    // Use runtime helper to avoid comptime explosion
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_pairwise: {{ const _iter = ", .{id}); try emitIter(self, args[0]);
    try self.emitFmt("; break :__m{d}_pairwise (try runtime.itertools_ops.pairwise(@TypeOf(_iter[0]), __global_allocator, _iter)).items; }}", .{id});
}

/// itertools.cycle(iterable) - cycle through iterable indefinitely (returns slice for bounded use)
fn genCycle(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("std.ArrayListUnmanaged(i64){}"); return; }
    // Return the iterable directly (caller expected to handle cycling in loop)
    try emitIter(self, args[0]);
}

/// itertools.enumerate(iterable, start=0) - already handled in for_special.zig, just return iterable here
fn genEnumerate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("std.ArrayListUnmanaged(i64){}"); return; }
    try emitIter(self, args[0]);
}

/// itertools.product(*iterables, repeat=1) - Cartesian product
/// Handles 1, 2, or 3 iterables
pub fn genProduct(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("std.ArrayListUnmanaged(struct { @\"0\": i64 }){}"); return; }
    const id = self.nextNameId();
    if (args.len == 1) {
        // Single iterable: wrap each element in a tuple
        try self.emitFmt("__m{d}_product: {{\n const _a = ", .{id}); try emitIter(self, args[0]);
        try self.emit(";\n var _result = std.ArrayListUnmanaged(struct { @\"0\": @TypeOf(_a[0]) }){};\n ");
        try self.emit("for (_a) |item| { _result.append(__global_allocator, .{ .@\"0\" = item }) catch continue; }\n ");
        try self.emitFmt("break :__m{d}_product _result;\n }}", .{id});
        return;
    }
    if (args.len == 2) {
        // Two iterables: Cartesian product
        try self.emitFmt("__m{d}_product: {{\n const _a = ", .{id}); try emitIter(self, args[0]);
        try self.emit(";\n const _b = "); try emitIter(self, args[1]);
        try self.emit(";\n var _result = std.ArrayListUnmanaged(struct { @\"0\": @TypeOf(_a[0]), @\"1\": @TypeOf(_b[0]) }){};\n ");
        try self.emit("for (_a) |a| { for (_b) |b| { _result.append(__global_allocator, .{ .@\"0\" = a, .@\"1\" = b }) catch continue; } }\n ");
        try self.emitFmt("break :__m{d}_product _result;\n }}", .{id});
        return;
    }
    // Three or more iterables: nested Cartesian product
    try self.emitFmt("__m{d}_product: {{\n const _a = ", .{id}); try emitIter(self, args[0]);
    try self.emit(";\n const _b = "); try emitIter(self, args[1]);
    try self.emit(";\n const _c = "); try emitIter(self, args[2]);
    try self.emit(";\n var _result = std.ArrayListUnmanaged(struct { @\"0\": @TypeOf(_a[0]), @\"1\": @TypeOf(_b[0]), @\"2\": @TypeOf(_c[0]) }){};\n ");
    try self.emit("for (_a) |a| { for (_b) |b| { for (_c) |c| { _result.append(__global_allocator, .{ .@\"0\" = a, .@\"1\" = b, .@\"2\" = c }) catch continue; } } }\n ");
    try self.emitFmt("break :__m{d}_product _result;\n }}", .{id});
}

/// Generate product with repeat=N where N is known at compile time
/// This generates N nested loops
pub fn genProductWithRepeat(self: *NativeCodegen, iter: ast.Node, repeat: i64) CodegenError!void {
    if (repeat <= 0) { try self.emit("std.ArrayListUnmanaged(struct {}){}"); return; }
    const id = self.nextNameId();
    if (repeat == 1) {
        // Single iteration - wrap each in tuple
        try self.emitFmt("__m{d}_product_repeat: {{\n const _a = ", .{id}); try emitIter(self, iter);
        try self.emit(";\n var _result = std.ArrayListUnmanaged(struct { @\"0\": @TypeOf(_a[0]) }){};\n ");
        try self.emit("for (_a) |item| { _result.append(__global_allocator, .{ .@\"0\" = item }) catch continue; }\n ");
        try self.emitFmt("break :__m{d}_product_repeat _result;\n }}", .{id});
        return;
    }

    // Generate N nested loops for repeat=N
    // Start block
    try self.emitFmt("__m{d}_product_repeat: {{\n const _iter = ", .{id});
    try emitIter(self, iter);
    try self.emit(";\n");

    // Generate struct type with N fields
    try self.emit("var _result = std.ArrayListUnmanaged(struct { ");
    var i: i64 = 0;
    while (i < repeat) : (i += 1) {
        if (i > 0) try self.emit(", ");
        try self.output.writer(self.allocator).print("@\"{d}\": @TypeOf(_iter[0])", .{i});
    }
    try self.emit(" }){};\n");

    // Generate N nested for loops
    i = 0;
    while (i < repeat) : (i += 1) {
        try self.output.writer(self.allocator).print("for (_iter) |_v{d}| {{ ", .{i});
    }

    // Append tuple
    try self.emit("_result.append(__global_allocator, .{ ");
    i = 0;
    while (i < repeat) : (i += 1) {
        if (i > 0) try self.emit(", ");
        try self.output.writer(self.allocator).print(".@\"{d}\" = _v{d}", .{ i, i });
    }
    try self.emit(" }) catch {{}}; ");

    // Close loops
    i = 0;
    while (i < repeat) : (i += 1) {
        try self.emit("} ");
    }

    try self.emitFmt("\nbreak :__m{d}_product_repeat _result;\n }}", .{id});
}

/// itertools.permutations(iterable, r=None) - r-length permutations
fn genPermutations(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("std.ArrayListUnmanaged(struct { @\"0\": i64, @\"1\": i64 }){}"); return; }
    // Generate 2-permutations (most common case)
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_perms: {{ const _iter = ", .{id}); try emitIter(self, args[0]);
    try self.emit("; var _result = std.ArrayListUnmanaged(struct { @\"0\": @TypeOf(_iter[0]), @\"1\": @TypeOf(_iter[0]) }){}; ");
    try self.emit("for (_iter, 0..) |a, i| { for (_iter, 0..) |b, j| { if (i != j) _result.append(__global_allocator, .{ .@\"0\" = a, .@\"1\" = b }) catch continue; } } ");
    try self.emitFmt("break :__m{d}_perms _result; }}", .{id});
}

/// itertools.combinations(iterable, r) - r-length combinations
fn genCombinations(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("std.ArrayListUnmanaged(struct { @\"0\": i64, @\"1\": i64 }){}"); return; }
    // Use runtime helper to avoid comptime explosion
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_combs: {{ const _iter = ", .{id}); try emitIter(self, args[0]);
    try self.emitFmt("; break :__m{d}_combs (try runtime.itertools_ops.combinations(@TypeOf(_iter[0]), __global_allocator, _iter)).items; }}", .{id});
}

/// itertools.combinations_with_replacement(iterable, r) - r-length combinations with replacement
fn genCombinationsWithReplacement(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("std.ArrayListUnmanaged(struct { @\"0\": i64, @\"1\": i64 }){}"); return; }
    // Use runtime helper to avoid comptime explosion
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_combswr: {{ const _iter = ", .{id}); try emitIter(self, args[0]);
    try self.emitFmt("; break :__m{d}_combswr (try runtime.itertools_ops.combinationsWithReplacement(@TypeOf(_iter[0]), __global_allocator, _iter)).items; }}", .{id});
}

/// itertools.groupby(iterable, key=None) - group consecutive equal elements
fn genGroupby(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("std.ArrayListUnmanaged(struct { key: i64, group: std.ArrayListUnmanaged(i64) }){}"); return; }
    // Use runtime helper to avoid comptime explosion
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_groupby: {{ const _iter = ", .{id}); try emitIter(self, args[0]);
    try self.emitFmt("; break :__m{d}_groupby (try runtime.itertools_ops.groupby(@TypeOf(_iter[0]), __global_allocator, _iter)).items; }}", .{id});
}

/// itertools.batched(iterable, n) - batch iterable into tuples of size n
fn genBatched(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("std.ArrayListUnmanaged(std.ArrayListUnmanaged(i64)){}"); return; }
    // Use runtime helper to avoid comptime explosion
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_batched: {{ const _iter = ", .{id}); try emitIter(self, args[0]);
    try self.emit("; const _n = @as(usize, @intCast("); try self.genExpr(args[1]);
    try self.emitFmt(")); break :__m{d}_batched (try runtime.itertools_ops.batched(@TypeOf(_iter[0]), __global_allocator, _iter, _n)).items; }}", .{id});
}
