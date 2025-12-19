/// List methods - .append(), .pop(), .extend(), .remove(), etc.
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const producesBlockExpression = @import("../expressions.zig").producesBlockExpression;
const container_traits = @import("../../../analysis/traits/container_traits.zig");

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}
// Helper for formatted output
fn emitFmtConst(self: *NativeCodegen, comptime fmt: []const u8, args: anytype) CodegenError!void {
    const b = try self.getBuilder();
    try b.writeFmt(fmt, args);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}


/// Helper to emit object expression, wrapping in parens if it's a block expression
fn emitObjExpr(self: *NativeCodegen, obj: ast.Node) CodegenError!void {
    if (producesBlockExpression(obj)) {
        try emitConst(self,"(");
        try self.genExpr(obj);
        try emitConst(self,")");
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
        // In defer blocks, 'try' is not allowed - use catch unreachable instead
        if (self.inside_defer) {
            try emitConst(self,"runtime.pyListAppendPV(__global_allocator, &");
            try emitObjExpr(self, obj);
            try emitConst(self,", runtime.PyValue.from(");
            try self.genExpr(args[0]);
            try emitConst(self,")) catch unreachable");
        } else {
            try emitConst(self,"try runtime.pyListAppendPV(__global_allocator, &");
            try emitObjExpr(self, obj);
            try emitConst(self,", runtime.PyValue.from(");
            try self.genExpr(args[0]);
            try emitConst(self,"))");
        }
        return;
    }

    // Check if list expects PyValue or PyObject elements
    // Type inference now handles captured variables via type_inferrer.captured_var_types
    const list_type = self.type_inferrer.inferExpr(obj) catch .unknown;

    // Check element type of list
    // Both .pyvalue and .unknown map to runtime.PyValue in Zig code (see core.zig:toZigType)
    const elem_is_pyvalue = pyvalue: {
        if (container_traits.isList(list_type)) {
            const elem_type = list_type.list.*;
            const elem_tag = @as(std.meta.Tag(@TypeOf(elem_type)), elem_type);
            break :pyvalue (elem_tag == .pyvalue or elem_tag == .unknown);
        }
        break :pyvalue false;
    };

    // Check if list expects PyCallable elements (for callable lists like [bytes, str, lambda: ...])
    const elem_is_callable = callable: {
        if (container_traits.isList(list_type)) {
            const elem_type = list_type.list.*;
            const type_traits = @import("../../../analysis/traits/type_traits.zig");
            break :callable type_traits.isCallable(elem_type);
        }
        break :callable false;
    };

    // Check if the item being appended is a lambda expression or a lambda variable
    const item_is_lambda = (args[0] == .lambda) or
        (args[0] == .name and self.lambda_vars.contains(args[0].name.id));

    // Check if obj needs temp variable (list literal, comprehension, etc.)
    if (needsTempVariable(obj)) {
        // Use temp variable pattern for list literals
        // In defer blocks, 'try' is not allowed - use catch unreachable instead
        if (self.inside_defer) {
            try emitConst(self,"{ var __list_temp = ");
            try self.genExpr(obj);
            try emitConst(self,"; __list_temp.append(__global_allocator, ");

            if (elem_is_pyvalue) {
                try emitConst(self,"runtime.PyValue.fromAlloc(__global_allocator, ");
                try self.genExpr(args[0]);
                try emitConst(self,") catch unreachable");
            } else if (elem_is_callable and item_is_lambda) {
                self.callable_context_param_type = "[]const u8";
                defer self.callable_context_param_type = null;
                // Use self.emitInlineBlockStart (not builder) to write to same output buffer
                const label2 = try self.emitInlineBlockStart("callable");
                try emitConst(self,"const __callable_temp = ");
                try self.genExpr(args[0]);
                try emitFmtConst(self, "; break :{s} runtime.builtins.PyCallable.fromAny(@TypeOf(__callable_temp), __callable_temp); ", .{label2});
                try self.emitInlineBlockEnd();
            } else {
                try self.genExpr(args[0]);
            }

            try emitConst(self,") catch unreachable; }");
        } else {
            try emitConst(self,"{ var __list_temp = ");
            try self.genExpr(obj);
            try emitConst(self,"; try __list_temp.append(__global_allocator, ");

            if (elem_is_pyvalue) {
                try emitConst(self,"try runtime.PyValue.fromAlloc(__global_allocator, ");
                try self.genExpr(args[0]);
                try emitConst(self,")");
            } else if (elem_is_callable and item_is_lambda) {
                self.callable_context_param_type = "[]const u8";
                defer self.callable_context_param_type = null;
                // Use self.emitInlineBlockStart (not builder) to write to same output buffer
                const label2 = try self.emitInlineBlockStart("callable");
                try emitConst(self,"const __callable_temp = ");
                try self.genExpr(args[0]);
                try emitFmtConst(self, "; break :{s} runtime.builtins.PyCallable.fromAny(@TypeOf(__callable_temp), __callable_temp); ", .{label2});
                try self.emitInlineBlockEnd();
            } else {
                try self.genExpr(args[0]);
            }

            try emitConst(self,"); }");
        }
    } else {
        // Existing code for variables/attributes/subscripts
        // In defer blocks, 'try' is not allowed - use catch unreachable instead
        if (self.inside_defer) {
            try emitObjExpr(self, obj);
            try emitConst(self,".append(__global_allocator, ");

            if (elem_is_pyvalue) {
                try emitConst(self,"runtime.PyValue.fromAlloc(__global_allocator, ");
                try self.genExpr(args[0]);
                try emitConst(self,") catch unreachable");
            } else if (elem_is_callable and item_is_lambda) {
                self.callable_context_param_type = "[]const u8";
                defer self.callable_context_param_type = null;
                // Use self.emitInlineBlockStart (not builder) to write to same output buffer
                const label2 = try self.emitInlineBlockStart("callable");
                try emitConst(self,"const __callable_temp = ");
                try self.genExpr(args[0]);
                try emitFmtConst(self, "; break :{s} runtime.builtins.PyCallable.fromAny(@TypeOf(__callable_temp), __callable_temp); ", .{label2});
                try self.emitInlineBlockEnd();
            } else {
                try self.genExpr(args[0]);
            }

            try emitConst(self,") catch unreachable");
        } else {
            try emitConst(self,"try ");
            try emitObjExpr(self, obj);
            try emitConst(self,".append(__global_allocator, ");

            if (elem_is_pyvalue) {
                try emitConst(self,"try runtime.PyValue.fromAlloc(__global_allocator, ");
                try self.genExpr(args[0]);
                try emitConst(self,")");
            } else if (elem_is_callable and item_is_lambda) {
                self.callable_context_param_type = "[]const u8";
                defer self.callable_context_param_type = null;
                // Use self.emitInlineBlockStart (not builder) to write to same output buffer
                const label2 = try self.emitInlineBlockStart("callable");
                try emitConst(self,"const __callable_temp = ");
                try self.genExpr(args[0]);
                try emitFmtConst(self, "; break :{s} runtime.builtins.PyCallable.fromAny(@TypeOf(__callable_temp), __callable_temp); ", .{label2});
                try self.emitInlineBlockEnd();
            } else {
                try self.genExpr(args[0]);
            }

            try emitConst(self,")");
        }
    }
}

/// Generate code for list.pop()
/// Removes and returns last item (or item at index if provided)
pub fn genPop(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // If index provided: list.orderedRemove(index)
    if (args.len > 0) {
        // Generate: list.orderedRemove(@intCast(index))
        try self.genExpr(obj);
        try emitConst(self,".orderedRemove(@intCast(");
        try self.genExpr(args[0]);
        try emitConst(self,"))");
    } else {
        // Generate: list.pop().? to unwrap the optional
        try self.genExpr(obj);
        try emitConst(self,".pop().?");
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
        try emitConst(self,"try runtime.pyListExtendPV(__global_allocator, &");
        try emitObjExpr(self, obj);
        try emitConst(self,", runtime.PyValue.from(");
        try self.genExpr(args[0]);
        try emitConst(self,"))");
        return;
    }

    const arg = args[0];

    // Check if obj needs temp variable (list literal, comprehension, etc.)
    const obj_needs_temp = needsTempVariable(obj);

    // Check if argument is a list literal - use & slice syntax
    if (arg == .list) {
        if (obj_needs_temp) {
            try emitConst(self,"{ var __list_temp = ");
            try self.genExpr(obj);
            try emitConst(self,"; try __list_temp.appendSlice(__global_allocator, &");
            try self.genExpr(arg);
            try emitConst(self,"); }");
        } else {
            try emitConst(self,"try ");
            try emitObjExpr(self, obj);
            try emitConst(self,".appendSlice(__global_allocator, &");
            try self.genExpr(arg);
            try emitConst(self,")");
        }
    } else if (producesBlockExpression(arg)) {
        // Block expression (list comprehension, call, etc.) - need temp for arg
        if (obj_needs_temp) {
            // Both obj and arg need temp variables
            try emitConst(self,"{ var __list_temp = ");
            try self.genExpr(obj);
            try emitConst(self,"; const __arg_temp = ");
            try self.genExpr(arg);
            try emitConst(self,"; try __list_temp.appendSlice(__global_allocator, __arg_temp.items); }");
        } else {
            // Only arg needs temp (existing code)
            try emitConst(self,"{ const __list_temp = ");
            try self.genExpr(arg);
            try emitConst(self,"; try ");
            try emitObjExpr(self, obj);
            try emitConst(self,".appendSlice(__global_allocator, __list_temp.items); }");
        }
    } else {
        // Check if argument might have __iter__ instead of .items
        const might_have_iter = iter: {
            // Check if it's a class instance call like BadLen()
            if (arg == .call and arg.call.func.* == .name) {
                const func_name = arg.call.func.name.id;
                // Class constructors start with uppercase
                if (func_name.len > 0 and func_name[0] >= 'A' and func_name[0] <= 'Z') {
                    break :iter true;
                }
            }
            // Check if it's a variable that's a class instance
            else if (arg == .name) {
                const var_name = arg.name.id;
                if (self.getVarType(var_name)) |vt| {
                    const type_traits = @import("../../../analysis/traits/type_traits.zig");
                    if (type_traits.isClassInstance(vt)) {
                        break :iter true;
                    }
                }
            }
            break :iter false;
        };

        if (might_have_iter) {
            // Use runtime helper for custom iterables
            if (obj_needs_temp) {
                // List literal with custom iterable: [].extend(BadLen())
                // Create a temp list variable first, then extend it
                try emitConst(self,"{ var __list_temp = ");
                try self.genExpr(obj);
                try emitConst(self,"; try runtime.listExtendIterable(__global_allocator, &__list_temp, ");
                try self.genExpr(arg);
                try emitConst(self,"); }");
            } else {
                try emitConst(self,"try runtime.listExtendIterable(__global_allocator, &");
                try emitObjExpr(self, obj);
                try emitConst(self,", ");
                try self.genExpr(arg);
                try emitConst(self,")");
            }
        } else {
            // Assume ArrayList variable - use .items
            if (obj_needs_temp) {
                try emitConst(self,"{ var __list_temp = ");
                try self.genExpr(obj);
                try emitConst(self,"; try __list_temp.appendSlice(__global_allocator, ");
                try self.genExpr(arg);
                try emitConst(self,".items); }");
            } else {
                try emitConst(self,"try ");
                try emitObjExpr(self, obj);
                try emitConst(self,".appendSlice(__global_allocator, ");
                try self.genExpr(arg);
                try emitConst(self,".items)");
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
        try emitConst(self,"try runtime.pyListInsertPV(__global_allocator, &");
        try emitObjExpr(self, obj);
        try emitConst(self,", ");
        try self.genExpr(args[0]);
        try emitConst(self,", runtime.PyValue.from(");
        try self.genExpr(args[1]);
        try emitConst(self,"))");
        return;
    }

    // Check if obj needs temp variable (list literal, comprehension, etc.)
    if (needsTempVariable(obj)) {
        try emitConst(self,"{ var __list_temp = ");
        try self.genExpr(obj);
        try emitConst(self,"; try __list_temp.insert(__global_allocator, @intCast(");
        try self.genExpr(args[0]);
        try emitConst(self,"), ");
        try self.genExpr(args[1]);
        try emitConst(self,"); }");
    } else {
        // Generate: try list.insert(__global_allocator, @intCast(index), item)
        // Need @intCast because index may be i64 from floor division, but insert needs usize
        try emitConst(self,"try ");
        try emitObjExpr(self, obj);
        try emitConst(self,".insert(__global_allocator, @intCast(");
        try self.genExpr(args[0]);
        try emitConst(self,"), ");
        try self.genExpr(args[1]);
        try emitConst(self,")");
    }
}

/// Generate code for list.remove(item)
/// Removes first occurrence of item
pub fn genRemove(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // list.remove() requires exactly 1 argument
    if (args.len != 1) return error.UnsupportedSyntax;

    // Generate: { const idx = std.mem.indexOfScalar(T, list.items, item).?; _ = list.orderedRemove(idx); }
    try emitConst(self,"{ const __idx = std.mem.indexOfScalar(i64, ");
    try self.genExpr(obj);
    try emitConst(self,".items, ");
    try self.genExpr(args[0]);
    try emitConst(self,").?; _ = ");
    try self.genExpr(obj);
    try emitConst(self,".orderedRemove(__idx); }");
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
        try emitConst(self,"{ var __list_temp = ");
        try self.genExpr(obj);
        try emitConst(self,"; std.mem.reverse(i64, __list_temp.items); }");
    } else {
        // Generate: std.mem.reverse(T, list.items)
        try emitConst(self,"std.mem.reverse(i64, ");
        try self.genExpr(obj);
        try emitConst(self,".items)");
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
        try emitConst(self,"{ var __list_temp = ");
        try self.genExpr(obj);
        try emitConst(self,"; std.mem.sort(i64, __list_temp.items, {}, comptime std.sort.asc(i64)); }");
    } else {
        // Generate: std.mem.sort(i64, list.items, {}, comptime std.sort.asc(i64))
        try emitConst(self,"std.mem.sort(i64, ");
        try self.genExpr(obj);
        try emitConst(self,".items, {}, comptime std.sort.asc(i64))");
    }
}

/// Generate code for list.clear()
/// Removes all items
pub fn genClear(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Handle list literals and temporary expressions that need temp variable
    if (needsTempVariable(obj)) {
        try emitConst(self,"{ var __list_temp = ");
        try self.genExpr(obj);
        try emitConst(self,"; __list_temp.clearRetainingCapacity(); }");
    } else {
        // Generate: list.clearRetainingCapacity()
        try emitObjExpr(self, obj);
        try emitConst(self,".clearRetainingCapacity()");
    }
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
            const label = try self.emitInlineBlockStart("copy");
            try emitConst(self,"const __list_temp = ");
            try self.genExpr(obj);
            try emitFmtConst(self, "; break :{s} try __list_temp.clone(); ", .{label});
            try self.emitInlineBlockEnd();
        } else {
            try emitConst(self,"try ");
            try emitObjExpr(self, obj);
            try emitConst(self,".clone()");
        }
    } else {
        // ArrayList.clone() requires allocator argument
        if (needsTempVariable(obj)) {
            const label = try self.emitInlineBlockStart("copy");
            try emitConst(self,"const __list_temp = ");
            try self.genExpr(obj);
            try emitFmtConst(self, "; break :{s} try __list_temp.clone(__global_allocator); ", .{label});
            try self.emitInlineBlockEnd();
        } else {
            try emitConst(self,"try ");
            try emitObjExpr(self, obj);
            try emitConst(self,".clone(__global_allocator)");
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
    try emitConst(self,"@as(i64, @intCast(std.mem.indexOfScalar(");
    try emitConst(self,elem_type);
    try emitConst(self,", ");
    try self.genExpr(obj);
    try emitConst(self,".items, ");
    try self.genExpr(args[0]);
    try emitConst(self,").?))");
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
    try emitConst(self,"@as(i64, @intCast(runtime.pyCount(");
    try emitConst(self,elem_type);
    try emitConst(self,", (");
    try self.genExpr(obj);
    try emitConst(self,").items, ");
    try self.genExpr(args[0]);
    try emitConst(self,")))");
}

/// Generate code for deque.appendleft(item)
/// Inserts item at the beginning (index 0)
pub fn genAppendleft(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // deque.appendleft() requires exactly 1 argument
    if (args.len != 1) return error.UnsupportedSyntax;

    // Generate: try deque.insert(__global_allocator, 0, item)
    try emitConst(self,"try ");
    try emitObjExpr(self, obj);
    try emitConst(self,".insert(__global_allocator, 0, ");
    try self.genExpr(args[0]);
    try emitConst(self,")");
}

/// Generate code for deque.popleft()
/// Removes and returns the first item
pub fn genPopleft(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    // Generate: deque.orderedRemove(0)
    try self.genExpr(obj);
    try emitConst(self,".orderedRemove(0)");
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
        try emitConst(self,"{ for (&");
        try self.genExpr(arg);
        try emitConst(self,") |__ext_item| { try ");
        try self.genExpr(obj);
        try emitConst(self,".insert(__global_allocator, 0, __ext_item); } }");
    } else {
        // ArrayList variable: use .items
        try emitConst(self,"{ const __ext_temp = ");
        try self.genExpr(arg);
        try emitConst(self,".items; for (__ext_temp) |__ext_item| { try ");
        try self.genExpr(obj);
        try emitConst(self,".insert(__global_allocator, 0, __ext_item); } }");
    }
}

/// Generate code for deque.rotate(n)
/// Rotates deque n steps to the right (negative = left)
pub fn genRotate(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // Generate: std.mem.rotate(T, deque.items, n)
    // Note: std.mem.rotate rotates left, so we need to negate for Python's right rotation
    try emitConst(self,"std.mem.rotate(@TypeOf(");
    try self.genExpr(obj);
    try emitConst(self,".items[0]), ");
    try self.genExpr(obj);
    try emitConst(self,".items, @as(usize, @intCast(");
    try self.genExpr(obj);
    try emitConst(self,".items.len)) -% @as(usize, @intCast(");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try emitConst(self,"1");
    }
    try emitConst(self,")))");
}
