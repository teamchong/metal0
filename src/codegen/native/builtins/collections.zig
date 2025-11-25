/// Collection builtins: sum(), all(), any(), sorted(), reversed(), enumerate(), zip()
const std = @import("std");
const ast = @import("../../../ast.zig");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;

/// Note: range() is handled specially in for-loops by genRangeLoop() in main.zig
/// It's not a standalone function but a loop optimization that generates:
/// - range(n) → while (i < n)
/// - range(start, end) → while (i < end) starting from start
/// - range(start, end, step) → while (i < end) with custom increment

/// Generate code for enumerate(iterable)
/// Returns: iterator with (index, value) tuples
/// Note: enumerate() is ONLY supported in for-loop context by statements.zig
/// Standalone usage not supported in native codegen
pub fn genEnumerate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // enumerate() only works in for-loops: for i, item in enumerate(items)
    // Standalone enumerate() not supported
    try self.emit(
        "@compileError(\"enumerate() only supported in for-loops: for i, item in enumerate(...)\")");
}

/// Generate code for zip(iter1, iter2, ...)
/// Returns: iterator of tuples
/// Note: zip() is best handled in for-loop context by statements.zig
/// Standalone usage not supported in native codegen
pub fn genZip(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // zip() is only supported in for-loops, not as a standalone expression
    try self.emit(
        "@compileError(\"zip() only supported in for-loops: for x, y in zip(list1, list2)\")");
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

    try self.emit("blk: {\n");
    try self.emit("var total: i64 = 0;\n");
    try self.emit("for (");
    try self.genExpr(args[0]);
    // ArrayList needs .items for iteration, arrays don't
    if (!is_array_var) {
        try self.emit(".items");
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

    try self.emit("blk: {\n");
    try self.emit("for (");
    try self.genExpr(args[0]);
    try self.emit(".items");
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

    try self.emit("blk: {\n");
    try self.emit("for (");
    try self.genExpr(args[0]);
    try self.emit(".items");
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
    try self.emit(
        "@compileError(\"map() not supported - use explicit for loop instead\")");
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
    try self.emit(
        "@compileError(\"filter() not supported - use explicit for loop with if instead\")");
}

// Built-in functions implementation status:
// ✅ Implemented: sum, all, any, sorted, reversed
// ❌ Not supported (need function pointers): map, filter
// ❌ Not supported (need for-loop integration): enumerate, zip
//
// Future improvements:
// - Add enumerate/zip support in for-loop codegen (statements.zig)
// - Consider comptime function pointer support for map/filter
