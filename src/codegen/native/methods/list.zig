/// List methods - .append(), .pop(), .extend(), .remove(), etc.
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const producesBlockExpression = @import("../expressions.zig").producesBlockExpression;
const container_traits = @import("../../../analysis/traits/container_traits.zig");

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

/// Check if object expression needs a temp variable (list literal, comprehension, etc.)
/// Returns true for expressions that don't have persistent storage.
/// Used by methods that call ArrayList functions requiring allocator argument.
fn needsTempVariable(obj: ast.Node) bool {
    return switch (obj) {
        .name => false,         // Variable - already has storage
        .attribute => false,    // Attribute access - already has storage
        .subscript => false,    // Subscript - already has storage
        else => true,           // List literals, comprehensions, calls - need temp
    };
}

/// Check if a list expression is uncertain (needs PyValue operations)
/// Two-Flow: routes uncertain lists to runtime helpers
fn isListUncertain(self: *NativeCodegen, obj: ast.Node) bool {
    if (obj == .name) {
        const name = obj.name.id;
        // Check scoped vars first (for loop variables, function params)
        // then fall back to global var_types
        const var_type = self.type_inferrer.getScopedVar(name) orelse
            self.type_inferrer.var_types.get(name);
        if (var_type) |vt| {
            switch (vt) {
                .pyvalue, .unknown => return true,
                else => {},
            }
        }
        // Variable not in type map - it's likely a local with inferred type
        // Don't assume uncertain - let Zig compiler catch type mismatches
        return false;
    }
    return false;
}

/// Generate code for list.append(item)
/// NOTE: Zig arrays are fixed size, need ArrayList for dynamic appending
/// Two-Flow: Certain lists use ArrayList.append, uncertain lists use runtime helpers
pub fn genAppend(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // list.append() requires exactly 1 argument
    if (args.len != 1) {
        return error.UnsupportedSyntax;
    }

    // Two-Flow: Check if list is uncertain (PyValue.list is *ArrayListUnmanaged - mutable)
    // For uncertain lists, we need runtime helpers that can handle type dynamically
    if (isListUncertain(self, obj)) {
        // Route to PyValue-First API that compiles ONCE (no monomorphization)
        try self.emit("try runtime.pyListAppendPV(__global_allocator, &");
        try emitObjExpr(self, obj);
        try self.emit(", runtime.PyValue.from(");
        try self.genExpr(args[0]);
        try self.emit("))");
        return;
    }

    // Check if list expects PyValue or PyObject elements
    const list_type = self.type_inferrer.inferExpr(obj) catch .unknown;

    // Check element type of list
    const elem_is_pyvalue = blk: {
        if (container_traits.isList(list_type)) {
            const elem_type = list_type.list.*;
            break :blk (@as(std.meta.Tag(@TypeOf(elem_type)), elem_type) == .pyvalue);
        }
        break :blk false;
    };

    // Check if list expects PyCallable elements (for callable lists like [bytes, str, lambda: ...])
    const elem_is_callable = blk: {
        if (container_traits.isList(list_type)) {
            const elem_type = list_type.list.*;
            const type_traits = @import("../../../analysis/traits/type_traits.zig");
            break :blk type_traits.isCallable(elem_type);
        }
        break :blk false;
    };

    // Check if the item being appended is a lambda expression or a lambda variable
    const item_is_lambda = (args[0] == .lambda) or
        (args[0] == .name and self.lambda_vars.contains(args[0].name.id));

    // Check if obj needs temp variable (list literal, comprehension, etc.)
    if (needsTempVariable(obj)) {
        // Use temp variable pattern for list literals
        try self.emit("{ var __list_temp = ");
        try self.genExpr(obj);
        try self.emit("; try __list_temp.append(__global_allocator, ");

        if (elem_is_pyvalue) {
            try self.emit("try runtime.PyValue.fromAlloc(__global_allocator, ");
            try self.genExpr(args[0]);
            try self.emit(")");
        } else if (elem_is_callable and item_is_lambda) {
            self.callable_context_param_type = "[]const u8";
            defer self.callable_context_param_type = null;
            try self.emit("callable_blk: { const __callable_temp = ");
            try self.genExpr(args[0]);
            try self.emit("; break :callable_blk runtime.builtins.PyCallable.fromAny(@TypeOf(__callable_temp), __callable_temp); }");
        } else {
            try self.genExpr(args[0]);
        }

        try self.emit("); }");
    } else {
        // Existing code for variables/attributes/subscripts
        try self.emit("try ");
        try emitObjExpr(self, obj);
        try self.emit(".append(__global_allocator, ");

        if (elem_is_pyvalue) {
            try self.emit("try runtime.PyValue.fromAlloc(__global_allocator, ");
            try self.genExpr(args[0]);
            try self.emit(")");
        } else if (elem_is_callable and item_is_lambda) {
            self.callable_context_param_type = "[]const u8";
            defer self.callable_context_param_type = null;
            try self.emit("callable_blk: { const __callable_temp = ");
            try self.genExpr(args[0]);
            try self.emit("; break :callable_blk runtime.builtins.PyCallable.fromAny(@TypeOf(__callable_temp), __callable_temp); }");
        } else {
            try self.genExpr(args[0]);
        }

        try self.emit(")");
    }
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
/// Two-Flow: Certain lists use ArrayList.appendSlice, uncertain lists use runtime helpers
pub fn genExtend(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // list.extend() requires exactly 1 argument
    if (args.len != 1) return error.UnsupportedSyntax;

    // Two-Flow: Check if list is uncertain
    if (isListUncertain(self, obj)) {
        // Route to PyValue-First API that compiles ONCE (no monomorphization)
        try self.emit("try runtime.pyListExtendPV(__global_allocator, &");
        try emitObjExpr(self, obj);
        try self.emit(", runtime.PyValue.from(");
        try self.genExpr(args[0]);
        try self.emit("))");
        return;
    }

    const arg = args[0];

    // Check if obj needs temp variable (list literal, comprehension, etc.)
    const obj_needs_temp = needsTempVariable(obj);

    // Check if argument is a list literal - use & slice syntax
    if (arg == .list) {
        if (obj_needs_temp) {
            try self.emit("{ var __list_temp = ");
            try self.genExpr(obj);
            try self.emit("; try __list_temp.appendSlice(__global_allocator, &");
            try self.genExpr(arg);
            try self.emit("); }");
        } else {
            try self.emit("try ");
            try emitObjExpr(self, obj);
            try self.emit(".appendSlice(__global_allocator, &");
            try self.genExpr(arg);
            try self.emit(")");
        }
    } else if (producesBlockExpression(arg)) {
        // Block expression (list comprehension, call, etc.) - need temp for arg
        if (obj_needs_temp) {
            // Both obj and arg need temp variables
            try self.emit("{ var __list_temp = ");
            try self.genExpr(obj);
            try self.emit("; const __arg_temp = ");
            try self.genExpr(arg);
            try self.emit("; try __list_temp.appendSlice(__global_allocator, __arg_temp.items); }");
        } else {
            // Only arg needs temp (existing code)
            try self.emit("{ const __list_temp = ");
            try self.genExpr(arg);
            try self.emit("; try ");
            try emitObjExpr(self, obj);
            try self.emit(".appendSlice(__global_allocator, __list_temp.items); }");
        }
    } else {
        // Check if argument might have __iter__ instead of .items
        const might_have_iter = blk: {
            // Check if it's a class instance call like BadLen()
            if (arg == .call and arg.call.func.* == .name) {
                const func_name = arg.call.func.name.id;
                // Class constructors start with uppercase
                if (func_name.len > 0 and func_name[0] >= 'A' and func_name[0] <= 'Z') {
                    break :blk true;
                }
            }
            // Check if it's a variable that's a class instance
            else if (arg == .name) {
                const var_name = arg.name.id;
                if (self.getVarType(var_name)) |vt| {
                    const type_traits = @import("../../../analysis/traits/type_traits.zig");
                    if (type_traits.isClassInstance(vt)) {
                        break :blk true;
                    }
                }
            }
            break :blk false;
        };

        if (might_have_iter) {
            // Use runtime helper for custom iterables
            // Note: Cannot use temp variable for obj here (can't take address of temporary)
            if (obj_needs_temp) {
                return error.UnsupportedSyntax; // Rare edge case: [].extend(CustomIterable())
            }
            try self.emit("try runtime.listExtendIterable(__global_allocator, &");
            try emitObjExpr(self, obj);
            try self.emit(", ");
            try self.genExpr(arg);
            try self.emit(")");
        } else {
            // Assume ArrayList variable - use .items
            if (obj_needs_temp) {
                try self.emit("{ var __list_temp = ");
                try self.genExpr(obj);
                try self.emit("; try __list_temp.appendSlice(__global_allocator, ");
                try self.genExpr(arg);
                try self.emit(".items); }");
            } else {
                try self.emit("try ");
                try emitObjExpr(self, obj);
                try self.emit(".appendSlice(__global_allocator, ");
                try self.genExpr(arg);
                try self.emit(".items)");
            }
        }
    }
}

/// Generate code for list.insert(index, item)
/// Inserts item at index
/// Two-Flow: Certain lists use ArrayList.insert, uncertain lists use runtime helpers
pub fn genInsert(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // list.insert() requires exactly 2 arguments
    if (args.len != 2) return error.UnsupportedSyntax;

    // Two-Flow: Check if list is uncertain
    if (isListUncertain(self, obj)) {
        // Route to PyValue-First API that compiles ONCE (no monomorphization)
        try self.emit("try runtime.pyListInsertPV(__global_allocator, &");
        try emitObjExpr(self, obj);
        try self.emit(", ");
        try self.genExpr(args[0]);
        try self.emit(", runtime.PyValue.from(");
        try self.genExpr(args[1]);
        try self.emit("))");
        return;
    }

    // Check if obj needs temp variable (list literal, comprehension, etc.)
    if (needsTempVariable(obj)) {
        try self.emit("{ var __list_temp = ");
        try self.genExpr(obj);
        try self.emit("; try __list_temp.insert(__global_allocator, @intCast(");
        try self.genExpr(args[0]);
        try self.emit("), ");
        try self.genExpr(args[1]);
        try self.emit("); }");
    } else {
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
}

/// Generate code for list.remove(item)
/// Removes first occurrence of item
pub fn genRemove(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // list.remove() requires exactly 1 argument
    if (args.len != 1) return error.UnsupportedSyntax;

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

    if (container_traits.isDict(obj_type) or is_dict_var) {
        // std.AutoHashMap.clone() and std.HashMap.clone() take no arguments
        // (they use the allocator stored internally)
        if (needsTempVariable(obj)) {
            try self.emit("blk: { const __list_temp = ");
            try self.genExpr(obj);
            try self.emit("; break :blk try __list_temp.clone(); }");
        } else {
            try self.emit("try ");
            try emitObjExpr(self, obj);
            try self.emit(".clone()");
        }
    } else {
        // ArrayList.clone() requires allocator argument
        if (needsTempVariable(obj)) {
            try self.emit("blk: { const __list_temp = ");
            try self.genExpr(obj);
            try self.emit("; break :blk try __list_temp.clone(__global_allocator); }");
        } else {
            try self.emit("try ");
            try emitObjExpr(self, obj);
            try self.emit(".clone(__global_allocator)");
        }
    }
}

/// Generate code for list.index(item)
/// Returns index of first occurrence, throws if not found
pub fn genIndex(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // list.index() requires exactly 1 argument
    if (args.len != 1) return error.UnsupportedSyntax;

    // Infer element type from the search item
    const item_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;
    var type_buf = std.ArrayList(u8){};
    defer type_buf.deinit(self.allocator);
    item_type.toZigType(self.allocator, &type_buf) catch {};
    const elem_type = if (type_buf.items.len > 0) type_buf.items else "i64";

    // Generate: @as(i64, @intCast(std.mem.indexOfScalar(T, list.items, item).?))
    // The .? asserts item exists (crashes if not found, like Python)
    try self.emit("@as(i64, @intCast(std.mem.indexOfScalar(");
    try self.emit(elem_type);
    try self.emit(", ");
    try self.genExpr(obj);
    try self.emit(".items, ");
    try self.genExpr(args[0]);
    try self.emit(").?))");
}

/// Generate code for list.count(item)
/// Returns number of occurrences of item
pub fn genCount(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // list.count() requires exactly 1 argument
    if (args.len != 1) return error.UnsupportedSyntax;

    // Infer element type from the search item
    const item_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;
    var type_buf = std.ArrayList(u8){};
    defer type_buf.deinit(self.allocator);
    item_type.toZigType(self.allocator, &type_buf) catch {};
    const elem_type = if (type_buf.items.len > 0) type_buf.items else "i64";

    // Generate: @as(i64, @intCast(runtime.pyCount(T, (list).items, item)))
    // Uses runtime.pyCount which handles NaN identity for floats
    // Parentheses around list are needed for list literal blocks
    try self.emit("@as(i64, @intCast(runtime.pyCount(");
    try self.emit(elem_type);
    try self.emit(", (");
    try self.genExpr(obj);
    try self.emit(").items, ");
    try self.genExpr(args[0]);
    try self.emit(")))");
}

/// Generate code for deque.appendleft(item)
/// Inserts item at the beginning (index 0)
pub fn genAppendleft(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // deque.appendleft() requires exactly 1 argument
    if (args.len != 1) return error.UnsupportedSyntax;

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
    // deque.extendleft() requires exactly 1 argument
    if (args.len != 1) return error.UnsupportedSyntax;

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
