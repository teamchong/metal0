/// Python itertools module - chain, cycle, repeat, count, zip_longest, etc.
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;
const producesBlockExpression = @import("expressions.zig").producesBlockExpression;
const container_traits = @import("../../analysis/traits/container_traits.zig");

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn needsItems(self: *NativeCodegen, arg: ast.Node) bool {
    const t = self.type_inferrer.inferExpr(arg) catch return false;
    return container_traits.isList(t) or t == .deque;
}

fn predFilter(self: *NativeCodegen, args: []ast.Node, comptime hint: []const u8, comptime body: []const u8) CodegenError!void {
    if (args.len < 2) { try emitConst(self, "std.ArrayListUnmanaged(i64){}"); return; }
    try self.withInlineBlock(hint, args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, " const _pred = "); try c.genExpr(a[0]);
            try emitConst(c, "; const _iter = ");
            try emitIter(c, a[1]);
            try emitConst(c, "; var _result = std.ArrayListUnmanaged(@TypeOf(_iter[0])){}; " ++ body);
            {
                const b = try c.getBuilder();
                try b.writeFmt(" break :{s} _result; ", .{label});
                const output = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output);
            }
        }
    }.emit);
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
    try emitConst(self, "runtime.iterSlice(");
    try self.genExpr(arg);
    try emitConst(self, ")");
}

/// Generate a native Zig slice for range(start, stop, step)
fn emitNativeRange(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Generate a comptime-friendly range: &[_]i64{start..stop} or runtime ArrayList
    // For simplicity, generate a block that builds an ArrayList
    try emitConst(self, "(");
    try self.withInlineBlock("range", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, " var __rs = std.ArrayListUnmanaged(i64){}; ");
            if (a.len == 0) {
                const b = try c.getBuilder();
                try b.writeFmt("break :{s} __rs.items; ", .{label});
                const output = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output);
                return;
            }

            // Determine start, stop, step
            if (a.len == 1) {
                // range(stop): 0..stop, step=1
                try emitConst(c, "var __i: i64 = 0; while (__i < ");
                try c.genExpr(a[0]);
                try emitConst(c, ") : (__i += 1) { __rs.append(__global_allocator, __i) catch continue; }");
            } else if (a.len >= 2) {
                // range(start, stop) or range(start, stop, step)
                try emitConst(c, "var __i: i64 = ");
                try c.genExpr(a[0]);
                try emitConst(c, "; const __stop: i64 = ");
                try c.genExpr(a[1]);
                try emitConst(c, "; const __step: i64 = ");
                if (a.len >= 3) {
                    try c.genExpr(a[2]);
                } else {
                    try emitConst(c, "1");
                }
                try emitConst(c, "; while (if (__step > 0) __i < __stop else __i > __stop) : (__i += __step) { __rs.append(__global_allocator, __i) catch continue; }");
            }
            {
                const b = try c.getBuilder();
                try b.writeFmt(" break :{s} __rs.items; ", .{label});
                const output = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output);
            }
        }
    }.emit);
    try emitConst(self, ")");
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
    if (args.len == 0) { try emitConst(self, "std.ArrayListUnmanaged(i64){}"); return; }
    try self.withInlineBlock("chain", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, " var _result = std.ArrayListUnmanaged(i64){}; ");
            for (a) |arg| { try emitConst(c, "for ("); try emitIter(c, arg); try emitConst(c, ") |item| { _result.append(__global_allocator, item) catch continue; } "); }
            const b = try c.getBuilder();
            try b.writeFmt("break :{s} _result; ", .{label});
            const output = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output);
        }
    }.emit);
}

pub fn genRepeat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // repeat() with no arguments raises TypeError - generate error for assertRaises
    if (args.len == 0) {
        try emitConst(self, "return error.TypeError");
        return;
    }
    try self.withInlineBlock("repeat", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, " var _result = std.ArrayListUnmanaged(i64){}; ");
            if (a.len > 1) {
                try emitConst(c, "var _i: usize = 0; while (_i < @as(usize, @intCast("); try c.genExpr(a[1]);
                try emitConst(c, "))) : (_i += 1) { _result.append(__global_allocator, "); try c.genExpr(a[0]); try emitConst(c, ") catch continue; }");
            } else { try emitConst(c, "_result.append(__global_allocator, "); try c.genExpr(a[0]); try emitConst(c, ") catch unreachable;"); }
            const b = try c.getBuilder();
            try b.writeFmt(" break :{s} _result; ", .{label});
            const output = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output);
        }
    }.emit);
}

pub fn genCount(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.withInlineBlock("count", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, " const _start = ");
            if (a.len >= 1) try c.genExpr(a[0]) else try emitConst(c, "@as(i64, 0)");
            try emitConst(c, "; const _step = ");
            if (a.len >= 2) try c.genExpr(a[1]) else try emitConst(c, "@as(i64, 1)");
            {
                const b = try c.getBuilder();
                try b.writeFmt("; break :{s} .{{ .start = _start, .step = _step }}; ", .{label});
                const output = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output);
            }
        }
    }.emit);
}

pub fn genIslice(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try emitConst(self, "std.ArrayListUnmanaged(i64){}");
        return;
    }
    try self.withInlineBlock("islice", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, " const _iter = ");
            try emitIter(c, a[0]);
            try emitConst(c, "; const _stop = @as(usize, @intCast(");
            try c.genExpr(a[1]);
            {
                const b = try c.getBuilder();
                try b.writeFmt(")); var _result = std.ArrayListUnmanaged(@TypeOf(_iter[0])){{}}; for (_iter[0..@min(_stop, _iter.len)]) |item| {{ _result.append(__global_allocator, item) catch continue; }} break :{s} _result; ", .{label});
                const output = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output);
            }
        }
    }.emit);
}

pub fn genZipLongest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try emitConst(self, "std.ArrayListUnmanaged(struct { @\"0\": i64 }){}"); return; }
    if (args.len >= 2) {
        try self.withInlineBlock("zip_longest", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, " const _a = "); try c.genExpr(a[0]);
                try emitConst(c, "; const _b = "); try c.genExpr(a[1]);
                {
                    const b = try c.getBuilder();
                    try b.writeFmt("; const _len = @max(_a.items.len, _b.items.len); var _result = std.ArrayListUnmanaged(struct {{ @\"0\": i64, @\"1\": i64 }}){{}}; for (0.._len) |i| {{ const _va = if (i < _a.items.len) _a.items[i] else 0; const _vb = if (i < _b.items.len) _b.items[i] else 0; _result.append(__global_allocator, .{{ .@\"0\" = _va, .@\"1\" = _vb }}) catch continue; }} break :{s} _result; ", .{label});
                    const output = b.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output);
                }
            }
        }.emit);
    } else try self.genExpr(args[0]);
}

fn genAccumulate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try emitConst(self, "std.ArrayListUnmanaged(i64){}"); return; }
    try self.withInlineBlock("accumulate", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, " const _iter = "); try emitIter(c, a[0]);
            try emitConst(c, "; var _result = std.ArrayListUnmanaged(@TypeOf(_iter[0])){}; var _acc: @TypeOf(_iter[0]) = _iter[0]; _result.append(__global_allocator, _acc) catch unreachable; for (_iter[1..]) |item| { _acc = ");
            if (a.len > 1) { try c.genExpr(a[1]); try emitConst(c, "(_acc, item)"); } else try emitConst(c, "_acc + item");
            {
                const b = try c.getBuilder();
                try b.writeFmt("; _result.append(__global_allocator, _acc) catch continue; }} break :{s} _result; ", .{label});
                const output = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output);
            }
        }
    }.emit);
}

fn genStarmap(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try emitConst(self, "std.ArrayListUnmanaged(i64){}"); return; }
    try self.withInlineBlock("starmap", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, " const _func = "); try c.genExpr(a[0]);
            try emitConst(c, "; const _iter = "); try emitIter(c, a[1]);
            {
                const b = try c.getBuilder();
                try b.writeFmt("; var _result = std.ArrayListUnmanaged(@TypeOf(_func(_iter[0].@\"0\", _iter[0].@\"1\"))){{}}; for (_iter) |item| {{ _result.append(__global_allocator, _func(item.@\"0\", item.@\"1\")) catch continue; }} break :{s} _result; ", .{label});
                const output = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output);
            }
        }
    }.emit);
}

fn genCompress(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try emitConst(self, "std.ArrayListUnmanaged(i64){}"); return; }
    // Use runtime helper to avoid comptime explosion
    try self.withInlineBlock("compress", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, " const _data = "); try emitIter(c, a[0]);
            try emitConst(c, "; const _selectors = "); try emitIter(c, a[1]);
            {
                const b = try c.getBuilder();
                try b.writeFmt("; break :{s} (try runtime.itertools_ops.compress(@TypeOf(_data[0]), __global_allocator, _data, _selectors)).items; ", .{label});
                const output = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output);
            }
        }
    }.emit);
}

fn genTee(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try emitConst(self, ".{ std.ArrayListUnmanaged(i64){}, std.ArrayListUnmanaged(i64){} }"); return; }
    try emitConst(self, ".{ "); try self.genExpr(args[0]); try emitConst(self, ", "); try self.genExpr(args[0]); try emitConst(self, " }");
}

fn genPairwise(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try emitConst(self, "std.ArrayListUnmanaged(struct { @\"0\": i64, @\"1\": i64 }){}"); return; }
    // Use runtime helper to avoid comptime explosion
    try self.withInlineBlock("pairwise", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, " const _iter = "); try emitIter(c, a[0]);
            {
                const b = try c.getBuilder();
                try b.writeFmt("; break :{s} (try runtime.itertools_ops.pairwise(@TypeOf(_iter[0]), __global_allocator, _iter)).items; ", .{label});
                const output = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output);
            }
        }
    }.emit);
}

/// itertools.cycle(iterable) - cycle through iterable indefinitely (returns slice for bounded use)
fn genCycle(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try emitConst(self, "std.ArrayListUnmanaged(i64){}"); return; }
    // Return the iterable directly (caller expected to handle cycling in loop)
    try emitIter(self, args[0]);
}

/// itertools.enumerate(iterable, start=0) - already handled in for_special.zig, just return iterable here
fn genEnumerate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try emitConst(self, "std.ArrayListUnmanaged(i64){}"); return; }
    try emitIter(self, args[0]);
}

/// itertools.product(*iterables, repeat=1) - Cartesian product
/// Handles 1, 2, or 3 iterables
pub fn genProduct(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try emitConst(self, "std.ArrayListUnmanaged(struct { @\"0\": i64 }){}"); return; }
    if (args.len == 1) {
        // Single iterable: wrap each element in a tuple
        try self.withInlineBlock("product", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "\n const _a = "); try emitIter(c, a[0]);
                try emitConst(c, ";\n var _result = std.ArrayListUnmanaged(struct { @\"0\": @TypeOf(_a[0]) }){};\n ");
                try emitConst(c, "for (_a) |item| { _result.append(__global_allocator, .{ .@\"0\" = item }) catch continue; }\n ");
                {
                    const b = try c.getBuilder();
                    try b.writeFmt("break :{s} _result;\n ", .{label});
                    const output = b.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output);
                }
            }
        }.emit);
        return;
    }
    if (args.len == 2) {
        // Two iterables: Cartesian product
        try self.withInlineBlock("product", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "\n const _a = "); try emitIter(c, a[0]);
                try emitConst(c, ";\n const _b = "); try emitIter(c, a[1]);
                try emitConst(c, ";\n var _result = std.ArrayListUnmanaged(struct { @\"0\": @TypeOf(_a[0]), @\"1\": @TypeOf(_b[0]) }){};\n ");
                try emitConst(c, "for (_a) |a| { for (_b) |b| { _result.append(__global_allocator, .{ .@\"0\" = a, .@\"1\" = b }) catch continue; } }\n ");
                {
                    const b = try c.getBuilder();
                    try b.writeFmt("break :{s} _result;\n ", .{label});
                    const output = b.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output);
                }
            }
        }.emit);
        return;
    }
    // Three or more iterables: nested Cartesian product
    try self.withInlineBlock("product", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "\n const _a = "); try emitIter(c, a[0]);
            try emitConst(c, ";\n const _b = "); try emitIter(c, a[1]);
            try emitConst(c, ";\n const _c = "); try emitIter(c, a[2]);
            try emitConst(c, ";\n var _result = std.ArrayListUnmanaged(struct { @\"0\": @TypeOf(_a[0]), @\"1\": @TypeOf(_b[0]), @\"2\": @TypeOf(_c[0]) }){};\n ");
            try emitConst(c, "for (_a) |a| { for (_b) |b| { for (_c) |c| { _result.append(__global_allocator, .{ .@\"0\" = a, .@\"1\" = b, .@\"2\" = c }) catch continue; } } }\n ");
            {
                const b = try c.getBuilder();
                try b.writeFmt("break :{s} _result;\n ", .{label});
                const output = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output);
            }
        }
    }.emit);
}

/// Generate product with repeat=N where N is known at compile time
/// This generates N nested loops
pub fn genProductWithRepeat(self: *NativeCodegen, iter: ast.Node, repeat: i64) CodegenError!void {
    if (repeat <= 0) { try emitConst(self, "std.ArrayListUnmanaged(struct {}){}"); return; }
    if (repeat == 1) {
        // Single iteration - wrap each in tuple
        // Use builder pattern directly for this case
        const b = try self.getBuilder();
        const id = self.nextNameId();
        const label = try std.fmt.allocPrint(self.arena.allocator(), "__m{d}_product_repeat", .{id});
        try b.writeFmt("({s}: {{ ", .{label});
        const output1 = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output1);

        try emitConst(self, "\n const _a = "); try emitIter(self, iter);
        try emitConst(self, ";\n var _result = std.ArrayListUnmanaged(struct { @\"0\": @TypeOf(_a[0]) }){};\n ");
        try emitConst(self, "for (_a) |item| { _result.append(__global_allocator, .{ .@\"0\" = item }) catch continue; }\n ");
        {
            const b2 = try self.getBuilder();
            try b2.writeFmt("break :{s} _result;\n }})", .{label});
            const output2 = b2.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output2);
        }
        return;
    }

    // Generate N nested loops for repeat=N
    // For complex case with dynamic loops, use builder directly
    const b = try self.getBuilder();
    const id = self.nextNameId();
    const label = try std.fmt.allocPrint(self.arena.allocator(), "__m{d}_product_repeat", .{id});
    try b.writeFmt("({s}: {{ ", .{label});
    const output1 = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output1);

    try emitConst(self, "\n const _iter = ");
    try emitIter(self, iter);
    try emitConst(self, ";\n");

    // Generate struct type with N fields
    try emitConst(self, "var _result = std.ArrayListUnmanaged(struct { ");
    var i: i64 = 0;
    while (i < repeat) : (i += 1) {
        if (i > 0) try emitConst(self, ", ");
        const b2 = try self.getBuilder();
        try b2.writeFmt("@\"{d}\": @TypeOf(_iter[0])", .{i});
        const output2 = b2.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output2);
    }
    try emitConst(self, " }){};\n");

    // Generate N nested for loops
    i = 0;
    while (i < repeat) : (i += 1) {
        const b3 = try self.getBuilder();
        try b3.writeFmt("for (_iter) |_v{d}| {{ ", .{i});
        const output3 = b3.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output3);
    }

    // Append tuple
    try emitConst(self, "_result.append(__global_allocator, .{ ");
    i = 0;
    while (i < repeat) : (i += 1) {
        if (i > 0) try emitConst(self, ", ");
        const b4 = try self.getBuilder();
        try b4.writeFmt(".@\"{d}\" = _v{d}", .{ i, i });
        const output4 = b4.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output4);
    }
    try emitConst(self, " }) catch {{}}; ");

    // Close loops
    i = 0;
    while (i < repeat) : (i += 1) {
        try emitConst(self, "} ");
    }

    {
        const b5 = try self.getBuilder();
        try b5.writeFmt("\nbreak :{s} _result;\n }})", .{label});
        const output5 = b5.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output5);
    }
}

/// itertools.permutations(iterable, r=None) - r-length permutations
fn genPermutations(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try emitConst(self, "std.ArrayListUnmanaged(struct { @\"0\": i64, @\"1\": i64 }){}"); return; }
    // Generate 2-permutations (most common case)
    try self.withInlineBlock("perms", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, " const _iter = "); try emitIter(c, a[0]);
            try emitConst(c, "; var _result = std.ArrayListUnmanaged(struct { @\"0\": @TypeOf(_iter[0]), @\"1\": @TypeOf(_iter[0]) }){}; ");
            try emitConst(c, "for (_iter, 0..) |a, i| { for (_iter, 0..) |b, j| { if (i != j) _result.append(__global_allocator, .{ .@\"0\" = a, .@\"1\" = b }) catch continue; } } ");
            {
                const b = try c.getBuilder();
                try b.writeFmt("break :{s} _result; ", .{label});
                const output = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output);
            }
        }
    }.emit);
}

/// itertools.combinations(iterable, r) - r-length combinations
fn genCombinations(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try emitConst(self, "std.ArrayListUnmanaged(struct { @\"0\": i64, @\"1\": i64 }){}"); return; }
    // Use runtime helper to avoid comptime explosion
    try self.withInlineBlock("combs", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, " const _iter = "); try emitIter(c, a[0]);
            {
                const b = try c.getBuilder();
                try b.writeFmt("; break :{s} (try runtime.itertools_ops.combinations(@TypeOf(_iter[0]), __global_allocator, _iter)).items; ", .{label});
                const output = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output);
            }
        }
    }.emit);
}

/// itertools.combinations_with_replacement(iterable, r) - r-length combinations with replacement
fn genCombinationsWithReplacement(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try emitConst(self, "std.ArrayListUnmanaged(struct { @\"0\": i64, @\"1\": i64 }){}"); return; }
    // Use runtime helper to avoid comptime explosion
    try self.withInlineBlock("combswr", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, " const _iter = "); try emitIter(c, a[0]);
            {
                const b = try c.getBuilder();
                try b.writeFmt("; break :{s} (try runtime.itertools_ops.combinationsWithReplacement(@TypeOf(_iter[0]), __global_allocator, _iter)).items; ", .{label});
                const output = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output);
            }
        }
    }.emit);
}

/// itertools.groupby(iterable, key=None) - group consecutive equal elements
fn genGroupby(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try emitConst(self, "std.ArrayListUnmanaged(struct { key: i64, group: std.ArrayListUnmanaged(i64) }){}"); return; }
    // Use runtime helper to avoid comptime explosion
    try self.withInlineBlock("groupby", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, " const _iter = "); try emitIter(c, a[0]);
            {
                const b = try c.getBuilder();
                try b.writeFmt("; break :{s} (try runtime.itertools_ops.groupby(@TypeOf(_iter[0]), __global_allocator, _iter)).items; ", .{label});
                const output = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output);
            }
        }
    }.emit);
}

/// itertools.batched(iterable, n) - batch iterable into tuples of size n
fn genBatched(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try emitConst(self, "std.ArrayListUnmanaged(std.ArrayListUnmanaged(i64)){}"); return; }
    // Use runtime helper to avoid comptime explosion
    try self.withInlineBlock("batched", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, " const _iter = "); try emitIter(c, a[0]);
            try emitConst(c, "; const _n = @as(usize, @intCast("); try c.genExpr(a[1]);
            {
                const b = try c.getBuilder();
                try b.writeFmt(")); break :{s} (try runtime.itertools_ops.batched(@TypeOf(_iter[0]), __global_allocator, _iter, _n)).items; ", .{label});
                const output = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output);
            }
        }
    }.emit);
}
