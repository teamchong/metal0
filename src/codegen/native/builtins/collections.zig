/// Collection builtins: sum(), all(), any(), sorted(), reversed(), enumerate(), zip()
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;

/// Check if an expression produces a Zig block expression that can't have field access directly
fn producesBlockExpression(expr: ast.Node) bool {
    return switch (expr) {
        .subscript => true,
        .list => true,
        .dict => true,
        .set => true,
        .listcomp => true,
        .dictcomp => true,
        .genexp => true,
        .if_expr => true,
        .call => true,
        else => false,
    };
}

/// Generate code for range(stop) or range(start, stop) or range(start, stop, step)
/// Returns an iterable range object (PyObject list)
pub fn genRange(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("(try runtime.builtins.range(__global_allocator, 0, 0, 1))");
        return;
    }

    // Generate runtime.builtins.range(allocator, start, stop, step)
    // Wrap each arg in @as(i64, @intCast(...)) to handle usize loop variables
    try self.emit("(try runtime.builtins.range(__global_allocator, ");
    if (args.len == 1) {
        // range(stop) -> range(0, stop, 1)
        try self.emit("0, @as(i64, @intCast(");
        try self.genExpr(args[0]);
        try self.emit(")), 1");
    } else if (args.len == 2) {
        // range(start, stop) -> range(start, stop, 1)
        try self.emit("@as(i64, @intCast(");
        try self.genExpr(args[0]);
        try self.emit(")), @as(i64, @intCast(");
        try self.genExpr(args[1]);
        try self.emit(")), 1");
    } else {
        // range(start, stop, step)
        try self.emit("@as(i64, @intCast(");
        try self.genExpr(args[0]);
        try self.emit(")), @as(i64, @intCast(");
        try self.genExpr(args[1]);
        try self.emit(")), @as(i64, @intCast(");
        try self.genExpr(args[2]);
        try self.emit("))");
    }
    try self.emit("))");
}

/// Generate code for enumerate(iterable)
/// Returns: iterator with (index, value) tuples
/// Note: enumerate() is ONLY supported in for-loop context by statements.zig
/// Standalone usage not supported in native codegen
pub fn genEnumerate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // enumerate() only works in for-loops: for i, item in enumerate(items)
    // Standalone enumerate() not supported
    try self.emit("@compileError(\"enumerate() only supported in for-loops: for i, item in enumerate(...)\")");
}

/// Generate code for zip(iter1, iter2, ...)
/// Returns: iterator of tuples
/// Note: zip() is best handled in for-loop context by statements.zig
/// Standalone usage not supported in native codegen
pub fn genZip(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // zip() is only supported in for-loops, not as a standalone expression
    try self.emit("@compileError(\"zip() only supported in for-loops: for x, y in zip(list1, list2)\")");
}

/// Generate code for sum(iterable)
/// Returns sum of all elements
pub fn genSum(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: blk: {
    //   var total: i64 = 0;
    //   for (items.items) |item| { total += item; }  // .items for ArrayList
    //   break :blk total;
    // }

    // Check if iterating over array variable (no .items) vs ArrayList
    const is_array_var = blk: {
        if (args[0] == .name) {
            const var_name = args[0].name.id;
            break :blk self.isArrayVar(var_name);
        }
        break :blk false;
    };

    const needs_wrap = producesBlockExpression(args[0]);

    try self.emit("blk: {\n");
    // If block expression, create temp variable first
    if (needs_wrap) {
        try self.emit("const __iterable = ");
        try self.genExpr(args[0]);
        try self.emit(";\n");
    }
    try self.emit("var total: i64 = 0;\n");
    try self.emit("for (");
    if (needs_wrap) {
        try self.emit("__iterable.items");
    } else {
        try self.genExpr(args[0]);
        // ArrayList needs .items for iteration, arrays don't
        if (!is_array_var) {
            try self.emit(".items");
        }
    }
    try self.emit(") |item| { total += item; }\n");
    try self.emit("break :blk total;\n");
    try self.emit("}");
}

/// Generate code for all(iterable)
/// Returns true if all elements are truthy
pub fn genAll(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: blk: {
    //   for (items.items) |item| {  // .items for ArrayList
    //     if (item == 0) break :blk false;
    //   }
    //   break :blk true;
    // }

    const needs_wrap = producesBlockExpression(args[0]);

    try self.emit("blk: {\n");
    // If block expression, create temp variable first
    if (needs_wrap) {
        try self.emit("const __iterable = ");
        try self.genExpr(args[0]);
        try self.emit(";\n");
    }
    try self.emit("for (");
    if (needs_wrap) {
        try self.emit("__iterable.items");
    } else {
        try self.genExpr(args[0]);
        try self.emit(".items");
    }
    try self.emit(") |item| {\n");
    try self.emit("if (item == 0) break :blk false;\n");
    try self.emit("}\n");
    try self.emit("break :blk true;\n");
    try self.emit("}");
}

/// Generate code for any(iterable)
/// Returns true if any element is truthy
pub fn genAny(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: blk: {
    //   for (items.items) |item| {  // .items for ArrayList
    //     if (item != 0) break :blk true;
    //   }
    //   break :blk false;
    // }

    const needs_wrap = producesBlockExpression(args[0]);

    try self.emit("blk: {\n");
    // If block expression, create temp variable first
    if (needs_wrap) {
        try self.emit("const __iterable = ");
        try self.genExpr(args[0]);
        try self.emit(";\n");
    }
    try self.emit("for (");
    if (needs_wrap) {
        try self.emit("__iterable.items");
    } else {
        try self.genExpr(args[0]);
        try self.emit(".items");
    }
    try self.emit(") |item| {\n");
    try self.emit("if (item != 0) break :blk true;\n");
    try self.emit("}\n");
    try self.emit("break :blk false;\n");
    try self.emit("}");
}

/// Generate code for sorted(iterable)
/// Returns sorted copy
pub fn genSorted(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: blk: {
    //   var copy = try allocator.dupe(i64, items);
    //   std.mem.sort(i64, copy, {}, comptime std.sort.asc(i64));
    //   break :blk copy;
    // }

    try self.emit("blk: {\n");
    try self.emit("const copy = try allocator.dupe(i64, ");
    try self.genExpr(args[0]);
    try self.emit(");\n");
    try self.emit("std.mem.sort(i64, copy, {}, comptime std.sort.asc(i64));\n");
    try self.emit("break :blk copy;\n");
    try self.emit("}");
}

/// Generate code for reversed(iterable)
/// Returns reversed copy of list
pub fn genReversed(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: blk: {
    //   var copy = try allocator.dupe(i64, items);
    //   std.mem.reverse(i64, copy);
    //   break :blk copy;
    // }

    try self.emit("blk: {\n");
    try self.emit("const copy = try allocator.dupe(i64, ");
    try self.genExpr(args[0]);
    try self.emit(");\n");
    try self.emit("std.mem.reverse(i64, copy);\n");
    try self.emit("break :blk copy;\n");
    try self.emit("}");
}

/// Generate code for map(func, iterable)
/// Applies function to each element
/// NOT SUPPORTED: Requires first-class functions/lambdas which need runtime function pointers
/// For AOT compilation, use explicit loops instead:
///   result = []
///   for x in items:
///       result.append(func(x))
pub fn genMap(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // map() requires passing functions as values (function pointers)
    // This needs either:
    // 1. Function pointers (complex in Zig, needs comptime or anytype)
    // 2. Lambda support (would need closure generation)
    // For now, users should use explicit for loops
    try self.emit("@compileError(\"map() not supported - use explicit for loop instead\")");
}

/// Generate code for filter(func, iterable)
/// Filters elements by predicate
/// NOT SUPPORTED: Requires first-class functions/lambdas which need runtime function pointers
/// For AOT compilation, use explicit loops with conditions instead:
///   result = []
///   for x in items:
///       if condition(x):
///           result.append(x)
pub fn genFilter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // filter() requires passing functions as values (function pointers)
    // This needs either:
    // 1. Function pointers (complex in Zig, needs comptime or anytype)
    // 2. Lambda support (would need closure generation)
    // For now, users should use explicit for loops with if conditions
    try self.emit("@compileError(\"filter() not supported - use explicit for loop with if instead\")");
}

/// Generate code for iter(iterable)
/// Returns an iterator over the iterable
pub fn genIter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) {
        try self.emit("@as(?*anyopaque, null)");
        return;
    }

    // For now, just pass through the iterable
    // Python's iter() returns an iterator object, but since we iterate directly
    // over iterables, we can just return the iterable itself
    try self.genExpr(args[0]);
}

/// Generate code for next(iterator, [default])
/// Returns the next item from the iterator
pub fn genNext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) {
        try self.emit("@as(?*anyopaque, null)");
        return;
    }

    // For custom iterator objects with __next__ method
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;
    if (arg_type == .class_instance) {
        try self.genExpr(args[0]);
        try self.emit(".__next__()");
        return;
    }

    // For ArrayLists and other built-in iterables, use runtime function
    try self.emit("runtime.builtins.next(");
    try self.genExpr(args[0]);
    try self.emit(")");
}

// Built-in functions implementation status:
// ✅ Implemented: sum, all, any, sorted, reversed, iter, next
// ❌ Not supported (need function pointers): map, filter
// ❌ Not supported (need for-loop integration): enumerate, zip
//
// Future improvements:
// - Add enumerate/zip support in for-loop codegen (statements.zig)
// - Consider comptime function pointer support for map/filter
