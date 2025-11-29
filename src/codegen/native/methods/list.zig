/// List methods - .append(), .pop(), .extend(), .remove(), etc.
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
        .listcomp => true,
        .dictcomp => true,
        .genexp => true,
        .if_expr => true,
        .call => true,
        else => false,
    };
}

/// Helper to emit object expression, wrapping in parens if it's a block expression
fn emitObjExpr(self: *NativeCodegen, obj: ast.Node) CodegenError!void {
    if (producesBlockExpression(obj)) {
        try self.emit("(");
        try self.genExpr(obj);
        try self.emit(")");
    } else {
        try self.genExpr(obj);
    }
}

/// Generate code for list.append(item)
/// NOTE: Zig arrays are fixed size, need ArrayList for dynamic appending
pub fn genAppend(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        return;
    }

    // Generate: try list.append(__global_allocator, item)
    try self.emit("try ");
    try emitObjExpr(self, obj);
    try self.emit(".append(__global_allocator, ");
    try self.genExpr(args[0]);
    try self.emit(")");
}

/// Generate code for list.pop()
/// Removes and returns last item (or item at index if provided)
pub fn genPop(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // If index provided: list.orderedRemove(index)
    if (args.len > 0) {
        // Generate: list.orderedRemove(@intCast(index))
        try self.genExpr(obj);
        try self.emit(".orderedRemove(@intCast(");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        // Generate: list.pop().? to unwrap the optional
        try self.genExpr(obj);
        try self.emit(".pop().?");
    }
}

/// Generate code for list.extend(other)
/// Appends all items from other list
pub fn genExtend(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    const arg = args[0];

    // Check if argument is a list literal - use & slice syntax
    if (arg == .list) {
        // Generate: try list.appendSlice(__global_allocator, &[_]T{...})
        try self.emit("try ");
        try emitObjExpr(self, obj);
        try self.emit(".appendSlice(__global_allocator, &");
        try self.genExpr(arg);
        try self.emit(")");
    } else if (producesBlockExpression(arg)) {
        // Block expression (list comprehension, call, etc.) - wrap in temp variable
        // Use a plain block (not labeled) since we're just creating a scope for the temp variable
        // Generate: { const __temp = expr; try list.appendSlice(__global_allocator, __temp.items); }
        try self.emit("{ const __list_temp = ");
        try self.genExpr(arg);
        try self.emit("; try ");
        try emitObjExpr(self, obj);
        try self.emit(".appendSlice(__global_allocator, __list_temp.items); }");
    } else {
        // Assume ArrayList variable - use .items
        // Generate: try list.appendSlice(__global_allocator, other.items)
        try self.emit("try ");
        try emitObjExpr(self, obj);
        try self.emit(".appendSlice(__global_allocator, ");
        try self.genExpr(arg);
        try self.emit(".items)");
    }
}

/// Generate code for list.insert(index, item)
/// Inserts item at index
pub fn genInsert(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 2) return;

    // Generate: try list.insert(__global_allocator, index, item)
    try self.emit("try ");
    try emitObjExpr(self, obj);
    try self.emit(".insert(__global_allocator, ");
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

    // Generate: try list.clone(__global_allocator)
    try self.emit("try ");
    try emitObjExpr(self, obj);
    try self.emit(".clone(__global_allocator)");
}

/// Generate code for list.index(item)
/// Returns index of first occurrence, throws if not found
pub fn genIndex(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: @as(i64, @intCast(std.mem.indexOfScalar(T, list.items, item).?))
    // The .? asserts item exists (crashes if not found, like Python)
    try self.emit("@as(i64, @intCast(std.mem.indexOfScalar(");
    // TODO: Need to infer element type
    try self.emit("i64, "); // Assume i64 for now
    try self.genExpr(obj);
    try self.emit(".items, ");
    try self.genExpr(args[0]);
    try self.emit(").?))");
}

/// Generate code for list.count(item)
/// Returns number of occurrences of item
pub fn genCount(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: @as(i64, @intCast(std.mem.count(T, list.items, &[_]T{item})))
    try self.emit("@as(i64, @intCast(std.mem.count(i64, ");
    try self.genExpr(obj);
    try self.emit(".items, &[_]i64{");
    try self.genExpr(args[0]);
    try self.emit("})))");
}

/// Generate code for deque.appendleft(item)
/// Inserts item at the beginning (index 0)
pub fn genAppendleft(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: try deque.insert(__global_allocator, 0, item)
    try self.emit("try ");
    try emitObjExpr(self, obj);
    try self.emit(".insert(__global_allocator, 0, ");
    try self.genExpr(args[0]);
    try self.emit(")");
}

/// Generate code for deque.popleft()
/// Removes and returns the first item
pub fn genPopleft(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Generate: deque.orderedRemove(0)
    try self.genExpr(obj);
    try self.emit(".orderedRemove(0)");
}

/// Generate code for deque.extendleft(iterable)
/// Extends deque from the left (items are reversed)
pub fn genExtendleft(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    const arg = args[0];

    // Check if argument is a list literal - use & slice syntax
    if (arg == .list) {
        // Array literals: iterate directly with &
        try self.emit("{ for (&");
        try self.genExpr(arg);
        try self.emit(") |__ext_item| { try ");
        try self.genExpr(obj);
        try self.emit(".insert(__global_allocator, 0, __ext_item); } }");
    } else {
        // ArrayList variable: use .items
        try self.emit("{ const __ext_temp = ");
        try self.genExpr(arg);
        try self.emit(".items; for (__ext_temp) |__ext_item| { try ");
        try self.genExpr(obj);
        try self.emit(".insert(__global_allocator, 0, __ext_item); } }");
    }
}

/// Generate code for deque.rotate(n)
/// Rotates deque n steps to the right (negative = left)
pub fn genRotate(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // Generate: std.mem.rotate(T, deque.items, n)
    // Note: std.mem.rotate rotates left, so we need to negate for Python's right rotation
    try self.emit("std.mem.rotate(@TypeOf(");
    try self.genExpr(obj);
    try self.emit(".items[0]), ");
    try self.genExpr(obj);
    try self.emit(".items, @as(usize, @intCast(");
    try self.genExpr(obj);
    try self.emit(".items.len)) -% @as(usize, @intCast(");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("1");
    }
    try self.emit(")))");
}
