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

// TODO: Implement built-in functions
// - bool(obj) -> bool
// - range(n) / range(start, end) / range(start, end, step)
// - enumerate(iterable)
// - zip(iter1, iter2, ...)
