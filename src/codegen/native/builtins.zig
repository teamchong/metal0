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

    // Generate: obj.len
    // Works for Zig slices and arrays
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ".len");
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

// TODO: Implement more built-in functions
// - Expand bool() to handle truthiness for strings/lists/dicts
