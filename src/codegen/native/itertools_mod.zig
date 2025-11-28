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
        try self.emitIndent();
        try self.emit("for (");
        try self.genExpr(arg);
        try self.emit(".items) |item| { _result.append(allocator, item) catch continue; }\n");
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
        try self.emit("))) : (_i += 1) { _result.append(allocator, ");
        try self.genExpr(args[0]);
        try self.emit(") catch continue; }\n");
    } else {
        // Without times, just return single element (can't do infinite)
        try self.emit("_result.append(allocator, ");
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
    try self.emit("_result.append(allocator, item) catch continue;\n");
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
        try self.emit("_result.append(allocator, .{ .@\"0\" = _va, .@\"1\" = _vb }) catch continue;\n");
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
