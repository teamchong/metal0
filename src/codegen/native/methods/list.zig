/// List methods - .append(), .pop(), .extend(), .remove(), etc.
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const producesBlockExpression = @import("../expressions.zig").producesBlockExpression;

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

    // Check if list expects PyValue or PyObject elements
    const list_type = self.type_inferrer.inferExpr(obj) catch .unknown;

    // Check element type of list
    const elem_is_pyvalue = blk: {
        if (list_type == .list) {
            const elem_type = list_type.list.*;
            break :blk (@as(std.meta.Tag(@TypeOf(elem_type)), elem_type) == .pyvalue);
        }
        break :blk false;
    };

    // Check if list expects PyCallable elements (for callable lists like [bytes, str, lambda: ...])
    const elem_is_callable = blk: {
        if (list_type == .list) {
            const elem_type = list_type.list.*;
            break :blk (@as(std.meta.Tag(@TypeOf(elem_type)), elem_type) == .callable);
        }
        break :blk false;
    };

    // Check if the item being appended is a lambda expression or a lambda variable
    const item_is_lambda = (args[0] == .lambda) or
        (args[0] == .name and self.lambda_vars.contains(args[0].name.id));

    // Generate: try list.append(__global_allocator, item)
    try self.emit("try ");
    try emitObjExpr(self, obj);
    try self.emit(".append(__global_allocator, ");

    if (elem_is_pyvalue) {
        // Wrap element in PyValue for heterogeneous lists
        try self.emit("try runtime.PyValue.fromAlloc(__global_allocator, ");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else if (elem_is_callable and item_is_lambda) {
        // Wrap lambda in PyCallable for callable lists
        // Set callable context so lambda generates with []const u8 param and return type
        self.callable_context_param_type = "[]const u8";
        defer self.callable_context_param_type = null;
        // Use a block to store lambda in const, then reference it for both @TypeOf and value
        // This avoids generating two different anonymous struct types
        try self.emit("callable_blk: { const __callable_temp = ");
        try self.genExpr(args[0]);
        try self.emit("; break :callable_blk runtime.builtins.PyCallable.fromAny(@TypeOf(__callable_temp), __callable_temp); }");
    } else {
        // For string lists or unknown lists, just append the raw value
        // Zig will catch type mismatches at compile time
        try self.genExpr(args[0]);
    }

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

    // Generate: try list.insert(__global_allocator, @intCast(index), item)
    // Need @intCast because index may be i64 from floor division, but insert needs usize
    try self.emit("try ");
    try emitObjExpr(self, obj);
    try self.emit(".insert(__global_allocator, @intCast(");
    try self.genExpr(args[0]);
    try self.emit("), ");
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

    // Check if obj is a complex expression that might generate a block
    const needs_temp = switch (obj) {
        .name => false,
        .attribute => false,
        .subscript => false,
        else => true, // List literals, comprehensions, etc.
    };

    if (needs_temp) {
        // Generate: { var __list_temp = expr; std.mem.reverse(i64, __list_temp.items); }
        try self.emit("{ var __list_temp = ");
        try self.genExpr(obj);
        try self.emit("; std.mem.reverse(i64, __list_temp.items); }");
    } else {
        // Generate: std.mem.reverse(T, list.items)
        try self.emit("std.mem.reverse(i64, ");
        try self.genExpr(obj);
        try self.emit(".items)");
    }
}

/// Generate code for list.sort()
/// Sorts list in place
pub fn genSort(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Check if obj is a complex expression that might generate a block
    const needs_temp = switch (obj) {
        .name => false,
        .attribute => false,
        .subscript => false,
        else => true, // List literals, comprehensions, etc.
    };

    if (needs_temp) {
        // Generate: { var __list_temp = expr; std.mem.sort(i64, __list_temp.items, {}, comptime std.sort.asc(i64)); }
        try self.emit("{ var __list_temp = ");
        try self.genExpr(obj);
        try self.emit("; std.mem.sort(i64, __list_temp.items, {}, comptime std.sort.asc(i64)); }");
    } else {
        // Generate: std.mem.sort(i64, list.items, {}, comptime std.sort.asc(i64))
        try self.emit("std.mem.sort(i64, ");
        try self.genExpr(obj);
        try self.emit(".items, {}, comptime std.sort.asc(i64))");
    }
}

/// Generate code for list.clear()
/// Removes all items
pub fn genClear(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Generate: list.clearRetainingCapacity()
    try self.genExpr(obj);
    try self.emit(".clearRetainingCapacity()");
}

/// Generate code for list.copy() / dict.copy()
/// Returns a shallow copy
pub fn genCopy(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Check object type to determine clone signature
    const obj_type = self.type_inferrer.inferExpr(obj) catch .unknown;

    // Also check if this is a dict variable (from our dict_vars tracking)
    const is_dict_var = if (obj == .name) self.dict_vars.contains(obj.name.id) else false;

    if (obj_type == .dict or is_dict_var) {
        // std.AutoHashMap.clone() and std.HashMap.clone() take no arguments
        // (they use the allocator stored internally)
        try self.emit("try ");
        try emitObjExpr(self, obj);
        try self.emit(".clone()");
    } else {
        // ArrayList.clone() requires allocator argument
        try self.emit("try ");
        try emitObjExpr(self, obj);
        try self.emit(".clone(__global_allocator)");
    }
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

    // Infer element type from the search item
    const item_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;
    var type_buf = std.ArrayList(u8){};
    defer type_buf.deinit(self.allocator);
    item_type.toZigType(self.allocator, &type_buf) catch {};
    const elem_type = if (type_buf.items.len > 0) type_buf.items else "i64";

    // Generate: @as(i64, @intCast(std.mem.count(T, (list).items, &[_]T{item})))
    // Parentheses around list are needed for list literal blocks
    try self.emit("@as(i64, @intCast(std.mem.count(");
    try self.emit(elem_type);
    try self.emit(", (");
    try self.genExpr(obj);
    try self.emit(").items, &[_]");
    try self.emit(elem_type);
    try self.emit("{");
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
