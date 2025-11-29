/// Python itertools module - chain, cycle, repeat, count, zip_longest, etc.
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate itertools.chain(*iterables)
/// Chain multiple iterables together
pub fn genChain(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("std.ArrayList(i64){}");
        return;
    }

    try self.emit("chain_blk: {\n");
    self.indent();
    try self.emitIndent();
    // Zig 0.15: use {} for unmanaged ArrayList
    try self.emit("var _result = std.ArrayList(i64){};\n");

    for (args) |arg| {
        // Detect type to determine if we need .items access
        const arg_type = try self.type_inferrer.inferExpr(arg);
        const needs_items = (arg_type == .list or arg_type == .deque);

        try self.emitIndent();
        try self.emit("for (");
        try self.genExpr(arg);
        if (needs_items) {
            try self.emit(".items");
        }
        try self.emit(") |item| { _result.append(__global_allocator, item) catch continue; }\n");
    }

    try self.emitIndent();
    try self.emit("break :chain_blk _result;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate itertools.repeat(value, times?)
/// Repeat a value infinitely or n times
pub fn genRepeat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("repeat_blk: {\n");
    self.indent();
    try self.emitIndent();
    // Zig 0.15: use {} initialization for unmanaged ArrayList
    try self.emit("var _result = std.ArrayList(i64){};\n");

    try self.emitIndent();
    if (args.len > 1) {
        try self.emit("var _i: usize = 0; while (_i < @as(usize, @intCast(");
        try self.genExpr(args[1]);
        try self.emit("))) : (_i += 1) { _result.append(__global_allocator, ");
        try self.genExpr(args[0]);
        try self.emit(") catch continue; }\n");
    } else {
        // Without times, just return single element (can't do infinite)
        try self.emit("_result.append(__global_allocator, ");
        try self.genExpr(args[0]);
        try self.emit(") catch {};\n");
    }

    try self.emitIndent();
    try self.emit("break :repeat_blk _result;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate itertools.count(start=0, step=1)
/// Infinite counter - for AOT, return a range-like iterator
pub fn genCount(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("count_blk: {\n");
    self.indent();
    try self.emitIndent();
    
    if (args.len >= 1) {
        try self.emit("const _start = ");
        try self.genExpr(args[0]);
        try self.emit(";\n");
    } else {
        try self.emit("const _start: i64 = 0;\n");
    }
    
    try self.emitIndent();
    if (args.len >= 2) {
        try self.emit("const _step = ");
        try self.genExpr(args[1]);
        try self.emit(";\n");
    } else {
        try self.emit("const _step: i64 = 1;\n");
    }
    
    // Return a tuple of (start, step) that can be used as counter state
    try self.emitIndent();
    try self.emit("break :count_blk .{ .start = _start, .step = _step };\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate itertools.cycle(iterable)
/// Cycle through iterable infinitely - for AOT, just return the iterable
pub fn genCycle(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("std.ArrayList(i64){}");
        return;
    }
    // For AOT, we can't do infinite cycling, so just return the iterable
    try self.genExpr(args[0]);
}

/// Generate itertools.islice(iterable, stop) or islice(iterable, start, stop, step)
pub fn genIslice(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("std.ArrayList(i64){}");
        return;
    }

    try self.emit("islice_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _iter = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");

    try self.emitIndent();
    try self.emit("const _stop = @as(usize, @intCast(");
    try self.genExpr(args[1]);
    try self.emit("));\n");

    try self.emitIndent();
    // Zig 0.15: use {} for unmanaged ArrayList
    try self.emit("var _result = std.ArrayList(i64){};\n");
    try self.emitIndent();
    try self.emit("for (_iter.items[0..@min(_stop, _iter.items.len)]) |item| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_result.append(__global_allocator, item) catch continue;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.emit("break :islice_blk _result;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate itertools.enumerate(iterable, start=0) - alias for builtin
pub fn genEnumerate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    // enumerate is a builtin, but can also be accessed via itertools
    try self.emit("enumerate_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _iter = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("break :enumerate_blk _iter;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate itertools.zip_longest(*iterables, fillvalue=None)
pub fn genZipLongest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("std.ArrayList(struct { @\"0\": i64 }){}");
        return;
    }
    // For simplicity, just zip the first two
    if (args.len >= 2) {
        try self.emit("zip_longest_blk: {\n");
        self.indent();
        try self.emitIndent();
        try self.emit("const _a = ");
        try self.genExpr(args[0]);
        try self.emit(";\n");
        try self.emitIndent();
        try self.emit("const _b = ");
        try self.genExpr(args[1]);
        try self.emit(";\n");
        try self.emitIndent();
        try self.emit("const _len = @max(_a.items.len, _b.items.len);\n");
        try self.emitIndent();
        // Zig 0.15: use {} for unmanaged ArrayList
        try self.emit("var _result = std.ArrayList(struct { @\"0\": i64, @\"1\": i64 }){};\n");
        try self.emitIndent();
        try self.emit("for (0.._len) |i| {\n");
        self.indent();
        try self.emitIndent();
        try self.emit("const _va = if (i < _a.items.len) _a.items[i] else 0;\n");
        try self.emitIndent();
        try self.emit("const _vb = if (i < _b.items.len) _b.items[i] else 0;\n");
        try self.emitIndent();
        try self.emit("_result.append(__global_allocator, .{ .@\"0\" = _va, .@\"1\" = _vb }) catch continue;\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
        try self.emitIndent();
        try self.emit("break :zip_longest_blk _result;\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}");
    } else {
        try self.genExpr(args[0]);
    }
}

/// Generate itertools.product(*iterables, repeat=1)
pub fn genProduct(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("std.ArrayList(struct {}){}");
        return;
    }
    // For simplicity, product of single iterable with itself
    try self.genExpr(args[0]);
}

/// Generate itertools.permutations(iterable, r=None)
pub fn genPermutations(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    // Stub - return iterable as-is
    try self.genExpr(args[0]);
}

/// Generate itertools.combinations(iterable, r)
pub fn genCombinations(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    // Stub - return iterable as-is
    try self.genExpr(args[0]);
}

/// Generate itertools.groupby(iterable, key=None)
pub fn genGroupby(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    // Stub - return iterable as-is
    try self.genExpr(args[0]);
}

/// Generate itertools.takewhile(predicate, iterable)
pub fn genTakewhile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("std.ArrayList(i64){}");
        return;
    }

    const iter_type = self.type_inferrer.inferExpr(args[1]) catch .unknown;
    const needs_items = (iter_type == .list or iter_type == .deque);

    try self.emit("takewhile_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _pred = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _iter = ");
    try self.genExpr(args[1]);
    if (needs_items) try self.emit(".items");
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _result = std.ArrayList(@TypeOf(_iter[0])){};\n");
    try self.emitIndent();
    try self.emit("for (_iter) |item| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (!_pred(item)) break;\n");
    try self.emitIndent();
    try self.emit("_result.append(__global_allocator, item) catch continue;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :takewhile_blk _result;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate itertools.dropwhile(predicate, iterable)
pub fn genDropwhile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("std.ArrayList(i64){}");
        return;
    }

    const iter_type = self.type_inferrer.inferExpr(args[1]) catch .unknown;
    const needs_items = (iter_type == .list or iter_type == .deque);

    try self.emit("dropwhile_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _pred = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _iter = ");
    try self.genExpr(args[1]);
    if (needs_items) try self.emit(".items");
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _result = std.ArrayList(@TypeOf(_iter[0])){};\n");
    try self.emitIndent();
    try self.emit("var _dropping = true;\n");
    try self.emitIndent();
    try self.emit("for (_iter) |item| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (_dropping and _pred(item)) continue;\n");
    try self.emitIndent();
    try self.emit("_dropping = false;\n");
    try self.emitIndent();
    try self.emit("_result.append(__global_allocator, item) catch continue;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :dropwhile_blk _result;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate itertools.filterfalse(predicate, iterable)
pub fn genFilterfalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("std.ArrayList(i64){}");
        return;
    }

    const iter_type = self.type_inferrer.inferExpr(args[1]) catch .unknown;
    const needs_items = (iter_type == .list or iter_type == .deque);

    try self.emit("filterfalse_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _pred = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _iter = ");
    try self.genExpr(args[1]);
    if (needs_items) try self.emit(".items");
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _result = std.ArrayList(@TypeOf(_iter[0])){};\n");
    try self.emitIndent();
    try self.emit("for (_iter) |item| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (!_pred(item)) _result.append(__global_allocator, item) catch continue;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :filterfalse_blk _result;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate itertools.accumulate(iterable, func=operator.add, initial=None)
pub fn genAccumulate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) {
        try self.emit("std.ArrayList(i64){}");
        return;
    }

    const iter_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;
    const needs_items = (iter_type == .list or iter_type == .deque);

    try self.emit("accumulate_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _iter = ");
    try self.genExpr(args[0]);
    if (needs_items) try self.emit(".items");
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _result = std.ArrayList(@TypeOf(_iter[0])){};\n");
    try self.emitIndent();
    try self.emit("var _acc: @TypeOf(_iter[0]) = _iter[0];\n");
    try self.emitIndent();
    try self.emit("_result.append(__global_allocator, _acc) catch {};\n");
    try self.emitIndent();
    try self.emit("for (_iter[1..]) |item| {\n");
    self.indent();
    try self.emitIndent();
    if (args.len > 1) {
        try self.emit("_acc = ");
        try self.genExpr(args[1]);
        try self.emit("(_acc, item);\n");
    } else {
        try self.emit("_acc = _acc + item;\n");
    }
    try self.emitIndent();
    try self.emit("_result.append(__global_allocator, _acc) catch continue;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :accumulate_blk _result;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate itertools.starmap(func, iterable)
pub fn genStarmap(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("std.ArrayList(i64){}");
        return;
    }

    const iter_type = self.type_inferrer.inferExpr(args[1]) catch .unknown;
    const needs_items = (iter_type == .list or iter_type == .deque);

    try self.emit("starmap_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _func = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _iter = ");
    try self.genExpr(args[1]);
    if (needs_items) try self.emit(".items");
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _result = std.ArrayList(@TypeOf(_func(_iter[0].@\"0\", _iter[0].@\"1\"))){};\n");
    try self.emitIndent();
    try self.emit("for (_iter) |item| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_result.append(__global_allocator, _func(item.@\"0\", item.@\"1\")) catch continue;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :starmap_blk _result;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate itertools.compress(data, selectors)
pub fn genCompress(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("std.ArrayList(i64){}");
        return;
    }

    const data_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;
    const needs_items0 = (data_type == .list or data_type == .deque);
    const sel_type = self.type_inferrer.inferExpr(args[1]) catch .unknown;
    const needs_items1 = (sel_type == .list or sel_type == .deque);

    try self.emit("compress_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _data = ");
    try self.genExpr(args[0]);
    if (needs_items0) try self.emit(".items");
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _selectors = ");
    try self.genExpr(args[1]);
    if (needs_items1) try self.emit(".items");
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _result = std.ArrayList(@TypeOf(_data[0])){};\n");
    try self.emitIndent();
    try self.emit("const _len = @min(_data.len, _selectors.len);\n");
    try self.emitIndent();
    try self.emit("for (0.._len) |i| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (_selectors[i] != 0) _result.append(__global_allocator, _data[i]) catch continue;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :compress_blk _result;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate itertools.tee(iterable, n=2)
pub fn genTee(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) {
        try self.emit(".{ std.ArrayList(i64){}, std.ArrayList(i64){} }");
        return;
    }
    // Return a tuple of n copies of the iterable
    try self.emit(".{ ");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[0]);
    try self.emit(" }");
}

/// Generate itertools.pairwise(iterable)
pub fn genPairwise(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) {
        try self.emit("std.ArrayList(struct { @\"0\": i64, @\"1\": i64 }){}");
        return;
    }

    const iter_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;
    const needs_items = (iter_type == .list or iter_type == .deque);

    try self.emit("pairwise_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _iter = ");
    try self.genExpr(args[0]);
    if (needs_items) try self.emit(".items");
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _result = std.ArrayList(struct { @\"0\": @TypeOf(_iter[0]), @\"1\": @TypeOf(_iter[0]) }){};\n");
    try self.emitIndent();
    try self.emit("if (_iter.len > 1) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("for (0.._iter.len - 1) |i| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_result.append(__global_allocator, .{ .@\"0\" = _iter[i], .@\"1\" = _iter[i + 1] }) catch continue;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :pairwise_blk _result;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate itertools.batched(iterable, n)
pub fn genBatched(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("std.ArrayList([]const i64){}");
        return;
    }
    // Stub - return iterable as single batch
    try self.emit(".{ ");
    try self.genExpr(args[0]);
    try self.emit(" }");
}
