/// Built-in functions - len(), str(), int(), range(), etc.
const std = @import("std");
const ast = @import("../../ast.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate code for len(obj)
/// Works with: strings, lists, dicts
pub fn genLen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        // TODO: Error handling
        return;
    }

    // Check if argument is ArrayList (detected as .list type)
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;
    const is_arraylist = (arg_type == .list);

    // Generate: obj.items.len for ArrayList, obj.len for slices/arrays
    try self.genExpr(args[0]);
    if (is_arraylist) {
        try self.output.appendSlice(self.allocator, ".items.len");
    } else {
        try self.output.appendSlice(self.allocator, ".len");
    }
}

/// Generate code for str(obj)
/// Converts to string representation
pub fn genStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        return;
    }

    // For now, just pass through if already a string
    // TODO: Implement conversion for int, float, bool
    try self.genExpr(args[0]);
}

/// Generate code for int(obj)
/// Converts to i64
pub fn genInt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        return;
    }

    // Generate: @intCast(obj) or std.fmt.parseInt for strings
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

    // Generate: @floatCast(obj) or std.fmt.parseFloat for strings
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
/// Currently not supported - needs Zig iterator implementation
pub fn genEnumerate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // For now: compile error placeholder
    // TODO: Needs Zig iterator support with tuple unpacking
    // Would generate something like:
    // var idx: usize = 0;
    // for (iterable) |item| {
    //     defer idx += 1;
    //     // use idx and item
    // }
    try self.output.appendSlice(self.allocator,
        "@compileError(\"enumerate() not yet supported\")");
}

/// Generate code for zip(iter1, iter2, ...)
/// Returns: iterator of tuples
/// Currently not supported - needs Zig multi-iterator implementation
pub fn genZip(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // For now: compile error placeholder
    // TODO: Needs Zig multi-iterator support with tuple packing
    // Would generate something like:
    // var i: usize = 0;
    // while (i < @min(iter1.len, iter2.len)) : (i += 1) {
    //     const tuple = .{ iter1[i], iter2[i] };
    //     // use tuple
    // }
    try self.output.appendSlice(self.allocator,
        "@compileError(\"zip() not yet supported\")");
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
    try self.output.appendSlice(self.allocator, "var copy = try allocator.dupe(i64, ");
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
    try self.output.appendSlice(self.allocator, "var copy = try allocator.dupe(i64, ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ");\n");
    try self.output.appendSlice(self.allocator, "std.mem.reverse(i64, copy);\n");
    try self.output.appendSlice(self.allocator, "break :blk copy;\n");
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for map(func, iterable)
/// Applies function to each element
pub fn genMap(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.output.appendSlice(self.allocator, "@compileError(\"map() not yet supported\")");
}

/// Generate code for filter(func, iterable)
/// Filters elements by predicate
pub fn genFilter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.output.appendSlice(self.allocator, "@compileError(\"filter() not yet supported\")");
}

/// Generate code for type(obj)
/// Returns type of object
pub fn genType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.output.appendSlice(self.allocator, "@compileError(\"type() not yet supported\")");
}

/// Generate code for isinstance(obj, type)
/// Checks if object is instance of type
pub fn genIsinstance(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.output.appendSlice(self.allocator, "@compileError(\"isinstance() not yet supported\")");
}

// TODO: Implement more built-in functions
// - Expand bool() to handle truthiness for strings/lists/dicts
