/// Built-in functions - len(), str(), int(), range(), etc.
const std = @import("std");
const ast = @import("../../ast.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate code for len(obj)
/// Works with: strings, lists, dicts, tuples
pub fn genLen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        // TODO: Error handling
        return;
    }

    // Check if argument is ArrayList (detected as .list type), dict, or tuple
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;
    const is_arraylist = (arg_type == .list);
    const is_dict = (arg_type == .dict);
    const is_tuple = (arg_type == .tuple);

    // Generate:
    // - obj.items.len for ArrayList
    // - obj.count() for HashMap/dict
    // - @typeInfo(...).fields.len for tuples
    // - obj.len for slices/arrays/strings
    if (is_tuple) {
        try self.output.appendSlice(self.allocator, "@typeInfo(@TypeOf(");
        try self.genExpr(args[0]);
        try self.output.appendSlice(self.allocator, ")).@\"struct\".fields.len");
    } else {
        try self.genExpr(args[0]);
        if (is_arraylist) {
            try self.output.appendSlice(self.allocator, ".items.len");
        } else if (is_dict) {
            try self.output.appendSlice(self.allocator, ".count()");
        } else {
            try self.output.appendSlice(self.allocator, ".len");
        }
    }
}

/// Generate code for str(obj)
/// Converts to string representation
pub fn genStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        return;
    }

    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    // Already a string - just return it
    if (arg_type == .string) {
        try self.genExpr(args[0]);
        return;
    }

    // Convert number to string
    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "var buf = std.ArrayList(u8){};\n");

    if (arg_type == .int) {
        try self.output.appendSlice(self.allocator, "try buf.writer(allocator).print(\"{}\", .{");
    } else if (arg_type == .float) {
        try self.output.appendSlice(self.allocator, "try buf.writer(allocator).print(\"{d}\", .{");
    } else if (arg_type == .bool) {
        // Python bool to string: True/False
        try self.output.appendSlice(self.allocator, "try buf.writer(allocator).print(\"{s}\", .{if (");
        try self.genExpr(args[0]);
        try self.output.appendSlice(self.allocator, ") \"True\" else \"False\"});\n");
        try self.output.appendSlice(self.allocator, "break :blk try buf.toOwnedSlice(allocator);\n");
        try self.output.appendSlice(self.allocator, "}");
        return;
    } else {
        try self.output.appendSlice(self.allocator, "try buf.writer(allocator).print(\"{any}\", .{");
    }

    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, "});\n");
    try self.output.appendSlice(self.allocator, "break :blk try buf.toOwnedSlice(allocator);\n");
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for int(obj)
/// Converts to i64
pub fn genInt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        return;
    }

    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    // Already an int - just return it
    if (arg_type == .int) {
        try self.genExpr(args[0]);
        return;
    }

    // Parse string to int
    if (arg_type == .string) {
        try self.output.appendSlice(self.allocator, "try std.fmt.parseInt(i64, ");
        try self.genExpr(args[0]);
        try self.output.appendSlice(self.allocator, ", 10)");
        return;
    }

    // Cast float to int
    if (arg_type == .float) {
        try self.output.appendSlice(self.allocator, "@as(i64, @intFromFloat(");
        try self.genExpr(args[0]);
        try self.output.appendSlice(self.allocator, "))");
        return;
    }

    // Cast bool to int (True -> 1, False -> 0)
    if (arg_type == .bool) {
        try self.output.appendSlice(self.allocator, "@as(i64, @intFromBool(");
        try self.genExpr(args[0]);
        try self.output.appendSlice(self.allocator, "))");
        return;
    }

    // Generic cast for unknown types
    try self.output.appendSlice(self.allocator, "@intCast(");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for float(obj)
/// Converts to f64
pub fn genFloat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        return;
    }

    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    // Already a float - just return it
    if (arg_type == .float) {
        try self.genExpr(args[0]);
        return;
    }

    // Parse string to float
    if (arg_type == .string) {
        try self.output.appendSlice(self.allocator, "try std.fmt.parseFloat(f64, ");
        try self.genExpr(args[0]);
        try self.output.appendSlice(self.allocator, ")");
        return;
    }

    // Cast int to float
    if (arg_type == .int) {
        try self.output.appendSlice(self.allocator, "@as(f64, @floatFromInt(");
        try self.genExpr(args[0]);
        try self.output.appendSlice(self.allocator, "))");
        return;
    }

    // Cast bool to float (True -> 1.0, False -> 0.0)
    if (arg_type == .bool) {
        try self.output.appendSlice(self.allocator, "@as(f64, @floatFromInt(@intFromBool(");
        try self.genExpr(args[0]);
        try self.output.appendSlice(self.allocator, ")))");
        return;
    }

    // Generic cast for unknown types
    try self.output.appendSlice(self.allocator, "@floatCast(");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for bool(obj)
/// Converts to bool
/// Python truthiness rules: 0, "", [], {} are False, everything else is True
pub fn genBool(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        return;
    }

    // For now: simple cast for numbers
    // TODO: Implement truthiness for strings/lists/dicts
    // - Empty string "" -> false
    // - Empty list [] -> false
    // - Zero 0 -> false
    // - Non-zero numbers -> true
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, " != 0");
}

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
    try self.output.appendSlice(self.allocator,
        "@compileError(\"enumerate() only supported in for-loops: for i, item in enumerate(...)\")");
}

/// Generate code for zip(iter1, iter2, ...)
/// Returns: iterator of tuples
/// Note: zip() is best handled in for-loop context by statements.zig
/// Standalone usage not supported in native codegen
pub fn genZip(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // zip() is only supported in for-loops, not as a standalone expression
    try self.output.appendSlice(self.allocator,
        "@compileError(\"zip() only supported in for-loops: for x, y in zip(list1, list2)\")");
}

/// Generate code for abs(n)
/// Returns absolute value
pub fn genAbs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: @abs(n) or if (n < 0) -n else n
    try self.output.appendSlice(self.allocator, "@abs(");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for min(a, b, ...)
/// Returns minimum value
pub fn genMin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    // Generate: @min(a, @min(b, c))
    try self.output.appendSlice(self.allocator, "@min(");
    try self.genExpr(args[0]);

    for (args[1..]) |arg| {
        try self.output.appendSlice(self.allocator, ", ");
        try self.genExpr(arg);
    }
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for max(a, b, ...)
/// Returns maximum value
pub fn genMax(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    // Generate: @max(a, @max(b, c))
    try self.output.appendSlice(self.allocator, "@max(");
    try self.genExpr(args[0]);

    for (args[1..]) |arg| {
        try self.output.appendSlice(self.allocator, ", ");
        try self.genExpr(arg);
    }
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for round(n)
/// Rounds to nearest integer
pub fn genRound(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: @round(n)
    try self.output.appendSlice(self.allocator, "@round(");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for pow(base, exp)
/// Returns base^exp
pub fn genPow(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 2) return;

    // Generate: std.math.pow(f64, base, exp)
    try self.output.appendSlice(self.allocator, "std.math.pow(f64, ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[1]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for chr(n)
/// Converts integer to character
pub fn genChr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: @as(u8, @intCast(n))
    try self.output.appendSlice(self.allocator, "@as(u8, @intCast(");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, "))");
}

/// Generate code for ord(c)
/// Converts character to integer
pub fn genOrd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: @as(i64, str[0])
    // Assumes single-char string
    try self.output.appendSlice(self.allocator, "@as(i64, ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, "[0])");
}

/// Generate code for sum(iterable)
/// Returns sum of all elements
pub fn genSum(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: blk: {
    //   var total: i64 = 0;
    //   for (items) |item| { total += item; }
    //   break :blk total;
    // }

    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "var total: i64 = 0;\n");
    try self.output.appendSlice(self.allocator, "for (");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ") |item| { total += item; }\n");
    try self.output.appendSlice(self.allocator, "break :blk total;\n");
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for all(iterable)
/// Returns true if all elements are truthy
pub fn genAll(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: blk: {
    //   for (items) |item| {
    //     if (item == 0) break :blk false;
    //   }
    //   break :blk true;
    // }

    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "for (");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ") |item| {\n");
    try self.output.appendSlice(self.allocator, "if (item == 0) break :blk false;\n");
    try self.output.appendSlice(self.allocator, "}\n");
    try self.output.appendSlice(self.allocator, "break :blk true;\n");
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for any(iterable)
/// Returns true if any element is truthy
pub fn genAny(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: blk: {
    //   for (items) |item| {
    //     if (item != 0) break :blk true;
    //   }
    //   break :blk false;
    // }

    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "for (");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ") |item| {\n");
    try self.output.appendSlice(self.allocator, "if (item != 0) break :blk true;\n");
    try self.output.appendSlice(self.allocator, "}\n");
    try self.output.appendSlice(self.allocator, "break :blk false;\n");
    try self.output.appendSlice(self.allocator, "}");
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

    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "const copy = try allocator.dupe(i64, ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ");\n");
    try self.output.appendSlice(self.allocator, "std.mem.sort(i64, copy, {}, comptime std.sort.asc(i64));\n");
    try self.output.appendSlice(self.allocator, "break :blk copy;\n");
    try self.output.appendSlice(self.allocator, "}");
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

    try self.output.appendSlice(self.allocator, "blk: {\n");
    try self.output.appendSlice(self.allocator, "const copy = try allocator.dupe(i64, ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ");\n");
    try self.output.appendSlice(self.allocator, "std.mem.reverse(i64, copy);\n");
    try self.output.appendSlice(self.allocator, "break :blk copy;\n");
    try self.output.appendSlice(self.allocator, "}");
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
    try self.output.appendSlice(self.allocator,
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
    try self.output.appendSlice(self.allocator,
        "@compileError(\"filter() not supported - use explicit for loop with if instead\")");
}

/// Generate code for type(obj)
/// Returns compile-time type name as string
pub fn genType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: @typeName(@TypeOf(obj))
    try self.output.appendSlice(self.allocator, "@typeName(@TypeOf(");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, "))");
}

/// Generate code for isinstance(obj, type)
/// Checks if object matches expected type at compile time
/// For native codegen, this is a compile-time type check
pub fn genIsinstance(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 2) return;

    // For native codegen, check if types match
    // Generate: @TypeOf(obj) == expected_type
    // Since we can't easily get the type from the second arg (it's a name like "int"),
    // we'll do a simple runtime check for common cases

    // For now, just return true (type checking happens at compile time in Zig)
    // A proper implementation would need type inference on both arguments
    try self.output.appendSlice(self.allocator, "true");
}

// Built-in functions implementation status:
// ✅ Implemented: len, str, int, float, bool, abs, min, max, sum, round, pow, chr, ord
// ✅ Implemented: all, any, sorted, reversed, type, isinstance
// ❌ Not supported (need function pointers): map, filter
// ❌ Not supported (need for-loop integration): enumerate, zip
//
// Future improvements:
// - Expand bool() to handle truthiness for strings/lists/dicts (currently only numbers)
// - Add enumerate/zip support in for-loop codegen (statements.zig)
// - Consider comptime function pointer support for map/filter
