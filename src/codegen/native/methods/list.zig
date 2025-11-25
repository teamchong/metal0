/// List methods - .append(), .pop(), .extend(), .remove(), etc.
const std = @import("std");
const ast = @import("../../../ast.zig");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;

/// Generate code for list.append(item)
/// NOTE: Zig arrays are fixed size, need ArrayList for dynamic appending
pub fn genAppend(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        return;
    }

    // Generate: try list.append(allocator, item)
    try self.emit("try ");
    try self.genExpr(obj);
    try self.emit(".append(allocator, ");
    try self.genExpr(args[0]);
    try self.emit(")");
}

/// Generate code for list.pop()
/// Removes and returns last item (or item at index if provided)
pub fn genPop(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // Generate: list.pop()
    try self.genExpr(obj);
    try self.emit(".pop()");

    // If index provided: list.orderedRemove(index)
    if (args.len > 0) {
        // Replace with orderedRemove for indexed pop
        self.output.items.len -= 6; // Remove ".pop()"
        try self.emit(".orderedRemove(");
        try self.genExpr(args[0]);
        try self.emit(")");
    }
}

/// Generate code for list.extend(other)
/// Appends all items from other list
pub fn genExtend(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: try list.appendSlice(allocator, other.items)
    try self.emit("try ");
    try self.genExpr(obj);
    try self.emit(".appendSlice(allocator, ");
    try self.genExpr(args[0]);
    try self.emit(".items)");
}

/// Generate code for list.insert(index, item)
/// Inserts item at index
pub fn genInsert(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 2) return;

    // Generate: try list.insert(allocator, index, item)
    try self.emit("try ");
    try self.genExpr(obj);
    try self.emit(".insert(allocator, ");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(")");
}

/// Generate code for list.remove(item)
/// Removes first occurrence of item
pub fn genRemove(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: { const idx = std.mem.indexOfScalar(T, list.items, item).?; _ = list.orderedRemove(idx); }
    try self.emit("{ const __idx = std.mem.indexOfScalar(i64, ");
    try self.genExpr(obj);
    try self.emit(".items, ");
    try self.genExpr(args[0]);
    try self.emit(").?; _ = ");
    try self.genExpr(obj);
    try self.emit(".orderedRemove(__idx); }");
}

/// Generate code for list.reverse()
/// Reverses list in place
pub fn genReverse(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Generate: std.mem.reverse(T, list.items)
    try self.emit("std.mem.reverse(i64, ");
    try self.genExpr(obj);
    try self.emit(".items)");
}

/// Generate code for list.sort()
/// Sorts list in place
pub fn genSort(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Generate: std.mem.sort(i64, list.items, {}, comptime std.sort.asc(i64))
    try self.emit("std.mem.sort(i64, ");
    try self.genExpr(obj);
    try self.emit(".items, {}, comptime std.sort.asc(i64))");
}

/// Generate code for list.clear()
/// Removes all items
pub fn genClear(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Generate: list.clearRetainingCapacity()
    try self.genExpr(obj);
    try self.emit(".clearRetainingCapacity()");
}

/// Generate code for list.copy()
/// Returns a shallow copy
pub fn genCopy(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Generate: try list.clone(allocator)
    try self.emit("try ");
    try self.genExpr(obj);
    try self.emit(".clone(allocator)");
}

/// Generate code for list.index(item)
/// Returns index of first occurrence, throws if not found
pub fn genIndex(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: std.mem.indexOfScalar(T, list.items, item).?
    // The .? asserts item exists (crashes if not found, like Python)
    try self.emit("std.mem.indexOfScalar(");
    // TODO: Need to infer element type
    try self.emit("i64, "); // Assume i64 for now
    try self.genExpr(obj);
    try self.emit(".items, ");
    try self.genExpr(args[0]);
    try self.emit(").?");
}

/// Generate code for list.count(item)
/// Returns number of occurrences of item
pub fn genCount(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: std.mem.count(T, list.items, &[_]T{item})
    try self.emit("std.mem.count(i64, ");
    try self.genExpr(obj);
    try self.emit(".items, &[_]i64{");
    try self.genExpr(args[0]);
    try self.emit("})");
}
