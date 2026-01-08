/// List methods - .append(), .pop(), .extend(), .remove(), etc.
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const expressions = @import("../expressions.zig");
const producesBlockExpression = expressions.producesBlockExpression;
const emitObjExpr = expressions.emitObjExpr;
const container_traits = @import("../../../analysis/traits/container_traits.zig");
const emitPyValueFromAlloc = @import("../expressions/calls.zig").emitPyValueFromAlloc;

/// Helper: emit runtime.pyListAppendPV(__global_allocator, &obj, runtime.PyValue.from(item)) with bracket matching
fn emitPyListAppendPV(self: *NativeCodegen, obj: ast.Node, item: ast.Node, use_try: bool, catch_unreachable: bool) CodegenError!void {
    const Ctx = struct { o: ast.Node, i: ast.Node, try_prefix: bool, catch_unreach: bool };
    if (use_try) try self.emit("try ");
    try self.emitCallCtx("runtime.pyListAppendPV", Ctx{ .o = obj, .i = item, .try_prefix = use_try, .catch_unreach = catch_unreachable }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.emit("__global_allocator, &");
            try emitObjExpr(s, ctx.o);
            try s.emitCallCtx(", runtime.PyValue.from", ctx.i, struct {
                pub fn inner(ss: *NativeCodegen, i: ast.Node) CodegenError!void {
                    try ss.genExpr(i);
                }
            }.inner);
        }
    }.f);
    if (catch_unreachable) try self.emit(" catch unreachable");
}

/// Helper: emit runtime.pyListExtendPV(__global_allocator, &obj, runtime.PyValue.from(arg)) with bracket matching
/// Context-aware try: use `try` only if function returns error union, otherwise `catch unreachable`
fn emitPyListExtendPV(self: *NativeCodegen, obj: ast.Node, arg: ast.Node) CodegenError!void {
    const at_module_level = self.current_function_name == null;
    const can_try = !at_module_level and self.current_function_can_try;
    if (can_try) try self.emit("try ");
    const Ctx = struct { o: ast.Node, a: ast.Node };
    try self.emitCallCtx("runtime.pyListExtendPV", Ctx{ .o = obj, .a = arg }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.emit("__global_allocator, &");
            try emitObjExpr(s, ctx.o);
            try s.emitCallCtx(", runtime.PyValue.from", ctx.a, struct {
                pub fn inner(ss: *NativeCodegen, a: ast.Node) CodegenError!void {
                    try ss.genExpr(a);
                }
            }.inner);
        }
    }.f);
    if (!can_try) try self.emit(" catch unreachable");
}

/// Helper: emit runtime.pyListInsertPV(__global_allocator, &obj, idx, runtime.PyValue.from(item)) with bracket matching
/// Context-aware try: use `try` only if function returns error union, otherwise `catch unreachable`
fn emitPyListInsertPV(self: *NativeCodegen, obj: ast.Node, idx: ast.Node, item: ast.Node) CodegenError!void {
    const at_module_level = self.current_function_name == null;
    const can_try = !at_module_level and self.current_function_can_try;
    if (can_try) try self.emit("try ");
    const Ctx = struct { o: ast.Node, idx: ast.Node, i: ast.Node };
    try self.emitCallCtx("runtime.pyListInsertPV", Ctx{ .o = obj, .idx = idx, .i = item }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.emit("__global_allocator, &");
            try emitObjExpr(s, ctx.o);
            try s.emit(", ");
            try s.genExpr(ctx.idx);
            try s.emitCallCtx(", runtime.PyValue.from", ctx.i, struct {
                pub fn inner(ss: *NativeCodegen, i: ast.Node) CodegenError!void {
                    try ss.genExpr(i);
                }
            }.inner);
        }
    }.f);
    if (!can_try) try self.emit(" catch unreachable");
}

/// Helper: emit runtime.listExtendIterable(__global_allocator, &obj, arg) with bracket matching
/// Context-aware try: use `try` only if function returns error union, otherwise `catch unreachable`
fn emitListExtendIterable(self: *NativeCodegen, obj: ast.Node, arg: ast.Node) CodegenError!void {
    const at_module_level = self.current_function_name == null;
    const can_try = !at_module_level and self.current_function_can_try;
    if (can_try) try self.emit("try ");
    const Ctx = struct { o: ast.Node, a: ast.Node };
    try self.emitCallCtx("runtime.listExtendIterable", Ctx{ .o = obj, .a = arg }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.emit("__global_allocator, &");
            try emitObjExpr(s, ctx.o);
            try s.emit(", ");
            try s.genExpr(ctx.a);
        }
    }.f);
    if (!can_try) try self.emit(" catch unreachable");
}

// emitObjExpr imported from expressions.zig (DRY consolidation)

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

// isListUncertain replaced by self.isExprUncertain() (DRY consolidation)

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
    if (self.isExprUncertain(obj)) {
        // Route to PyValue-First API that compiles ONCE (no monomorphization)
        // In defer blocks, 'try' is not allowed - use catch unreachable instead
        try emitPyListAppendPV(self, obj, args[0], !self.inside_defer, self.inside_defer);
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
        const list_temp = try self.name_gen.temp();
        // In defer blocks, 'try' is not allowed - use catch unreachable instead
        if (self.inside_defer) {
            try self.emitFmt("{{ var {s} = ", .{list_temp});
            try self.genExpr(obj);
            try self.emitFmt("; {s}.append(__global_allocator, ", .{list_temp});

            if (elem_is_pyvalue) {
                try self.emit("runtime.PyValue.fromAlloc(__global_allocator, ");
                try self.genExpr(args[0]);
                try self.emit(") catch unreachable");
            } else if (elem_is_callable and item_is_lambda) {
                self.callable_context_param_type = "[]const u8";
                defer self.callable_context_param_type = null;
                // Use self.emitInlineBlockStart (not builder) to write to same output buffer
                const label2 = try self.emitInlineBlockStart("callable");
                const callable_temp = try self.name_gen.temp();
                try self.emitFmt("const {s} = ", .{callable_temp});
                try self.genExpr(args[0]);
                try self.emitFmt("; break :{s} runtime.builtins.PyCallable.fromAny(@TypeOf({s}), {s}); ", .{ label2, callable_temp, callable_temp });
                try self.emitInlineBlockEnd();
            } else {
                try self.genExpr(args[0]);
            }

            try self.emit(") catch unreachable; }");
        } else {
            try self.emitFmt("{{ var {s} = ", .{list_temp});
            try self.genExpr(obj);
            try self.emitFmt("; try {s}.append(__global_allocator, ", .{list_temp});

            if (elem_is_pyvalue) {
                try emitPyValueFromAlloc(self, args[0]);
            } else if (elem_is_callable and item_is_lambda) {
                self.callable_context_param_type = "[]const u8";
                defer self.callable_context_param_type = null;
                // Use self.emitInlineBlockStart (not builder) to write to same output buffer
                const label2 = try self.emitInlineBlockStart("callable");
                const callable_temp = try self.name_gen.temp();
                try self.emitFmt("const {s} = ", .{callable_temp});
                try self.genExpr(args[0]);
                try self.emitFmt("; break :{s} runtime.builtins.PyCallable.fromAny(@TypeOf({s}), {s}); ", .{ label2, callable_temp, callable_temp });
                try self.emitInlineBlockEnd();
            } else {
                try self.genExpr(args[0]);
            }

            try self.emit("); }");
        }
    } else {
        // Existing code for variables/attributes/subscripts
        // In defer blocks, 'try' is not allowed - use catch unreachable instead
        if (self.inside_defer) {
            try emitObjExpr(self, obj);
            try self.emit(".append(__global_allocator, ");

            if (elem_is_pyvalue) {
                try self.emit("runtime.PyValue.fromAlloc(__global_allocator, ");
                try self.genExpr(args[0]);
                try self.emit(") catch unreachable");
            } else if (elem_is_callable and item_is_lambda) {
                self.callable_context_param_type = "[]const u8";
                defer self.callable_context_param_type = null;
                // Use self.emitInlineBlockStart (not builder) to write to same output buffer
                const label2 = try self.emitInlineBlockStart("callable");
                const callable_temp = try self.name_gen.temp();
                try self.emitFmt("const {s} = ", .{callable_temp});
                try self.genExpr(args[0]);
                try self.emitFmt("; break :{s} runtime.builtins.PyCallable.fromAny(@TypeOf({s}), {s}); ", .{ label2, callable_temp, callable_temp });
                try self.emitInlineBlockEnd();
            } else {
                try self.genExpr(args[0]);
            }

            try self.emit(") catch unreachable");
        } else {
            // Check if current function can use `try` (returns error union)
            // At module level or in error-returning functions: use try
            // In non-error functions (like __eq__): use catch unreachable
            const at_module_level = self.current_function_name == null;
            const can_try = at_module_level or self.current_function_can_try;

            if (elem_is_pyvalue) {
                // Avoid nested try by storing fromAlloc result in temp var first
                // Before: try obj.append(alloc, try PyValue.fromAlloc(...))
                // After:  { const __v = try PyValue.fromAlloc(...); try obj.append(alloc, __v); }
                const pyval_temp = try self.name_gen.temp();
                try self.emit("{ const ");
                try self.emit(pyval_temp);
                try self.emit(" = ");
                try emitPyValueFromAlloc(self, args[0]);
                if (can_try) {
                    try self.emit("; try ");
                } else {
                    try self.emit("; ");
                }
                try emitObjExpr(self, obj);
                try self.emit(".append(__global_allocator, ");
                try self.emit(pyval_temp);
                if (can_try) {
                    try self.emit("); }");
                } else {
                    try self.emit(") catch unreachable; }");
                }
                return; // Complete statement, don't add extra ")" from line 263
            } else if (elem_is_callable and item_is_lambda) {
                if (can_try) try self.emit("try ");
                try emitObjExpr(self, obj);
                try self.emit(".append(__global_allocator, ");
                self.callable_context_param_type = "[]const u8";
                defer self.callable_context_param_type = null;
                // Use self.emitInlineBlockStart (not builder) to write to same output buffer
                const label2 = try self.emitInlineBlockStart("callable");
                const callable_temp = try self.name_gen.temp();
                try self.emitFmt("const {s} = ", .{callable_temp});
                try self.genExpr(args[0]);
                try self.emitFmt("; break :{s} runtime.builtins.PyCallable.fromAny(@TypeOf({s}), {s}); ", .{ label2, callable_temp, callable_temp });
                try self.emitInlineBlockEnd();
            } else {
                // Regular case - emit try obj.append(alloc, arg) or with catch unreachable
                if (can_try) try self.emit("try ");
                try emitObjExpr(self, obj);
                try self.emit(".append(__global_allocator, ");
                try self.genExpr(args[0]);
            }

            try self.emit(")");
            if (!can_try and !(elem_is_callable and item_is_lambda)) {
                // For non-callable cases that don't return early, add catch unreachable
                // The callable case already handled its own ) from emitInlineBlockEnd
                if (!elem_is_pyvalue) try self.emit(" catch unreachable");
            } else if (!can_try and (elem_is_callable and item_is_lambda)) {
                try self.emit(" catch unreachable");
            }
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
    if (self.isExprUncertain(obj)) {
        // Route to PyValue-First API that compiles ONCE (no monomorphization)
        try emitPyListExtendPV(self, obj, args[0]);
        return;
    }

    const arg = args[0];

    // Check if obj needs temp variable (list literal, comprehension, etc.)
    const obj_needs_temp = needsTempVariable(obj);

    // Check if argument is a list literal - use & slice syntax
    if (arg == .list) {
        if (obj_needs_temp) {
            const list_temp = try self.name_gen.temp();
            try self.emitFmt("{{ var {s} = ", .{list_temp});
            try self.genExpr(obj);
            try self.emitFmt("; try {s}.appendSlice(__global_allocator, &", .{list_temp});
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
            const list_temp = try self.name_gen.temp();
            const arg_temp = try self.name_gen.temp();
            try self.emitFmt("{{ var {s} = ", .{list_temp});
            try self.genExpr(obj);
            try self.emitFmt("; const {s} = ", .{arg_temp});
            try self.genExpr(arg);
            try self.emitFmt("; try {s}.appendSlice(__global_allocator, {s}.items); }}", .{ list_temp, arg_temp });
        } else {
            // Only arg needs temp (existing code)
            const arg_temp = try self.name_gen.temp();
            try self.emitFmt("{{ const {s} = ", .{arg_temp});
            try self.genExpr(arg);
            try self.emit("; try ");
            try emitObjExpr(self, obj);
            try self.emitFmt(".appendSlice(__global_allocator, {s}.items); }}", .{arg_temp});
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
                const list_temp = try self.name_gen.temp();
                try self.emitFmt("{{ var {s} = ", .{list_temp});
                try self.genExpr(obj);
                try self.emitFmt("; try runtime.listExtendIterable(__global_allocator, &{s}, ", .{list_temp});
                try self.genExpr(arg);
                try self.emit("); }");
            } else {
                try emitListExtendIterable(self, obj, arg);
            }
        } else {
            // Assume ArrayList variable - use .items
            if (obj_needs_temp) {
                const list_temp = try self.name_gen.temp();
                try self.emitFmt("{{ var {s} = ", .{list_temp});
                try self.genExpr(obj);
                try self.emitFmt("; try {s}.appendSlice(__global_allocator, ", .{list_temp});
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
    if (self.isExprUncertain(obj)) {
        // Route to PyValue-First API that compiles ONCE (no monomorphization)
        try emitPyListInsertPV(self, obj, args[0], args[1]);
        return;
    }

    // Check if list expects PyValue or PyObject elements
    const list_type = self.type_inferrer.inferExpr(obj) catch .unknown;
    const elem_is_pyvalue = pyvalue: {
        if (container_traits.isList(list_type)) {
            const elem_type = list_type.list.*;
            const elem_tag = @as(std.meta.Tag(@TypeOf(elem_type)), elem_type);
            break :pyvalue (elem_tag == .pyvalue or elem_tag == .unknown);
        }
        break :pyvalue false;
    };

    // Check if obj needs temp variable (list literal, comprehension, etc.)
    if (needsTempVariable(obj)) {
        const list_temp = try self.name_gen.temp();
        try self.emitFmt("{{ var {s} = ", .{list_temp});
        try self.genExpr(obj);
        try self.emitFmt("; try {s}.insert(__global_allocator, @intCast(", .{list_temp});
        try self.genExpr(args[0]);
        try self.emit("), ");
        if (elem_is_pyvalue) {
            try emitPyValueFromAlloc(self, args[1]);
        } else {
            try self.genExpr(args[1]);
        }
        try self.emit("); }");
    } else {
        // Generate: try list.insert(__global_allocator, @intCast(index), item)
        // Need @intCast because index may be i64 from floor division, but insert needs usize
        try self.emit("try ");
        try emitObjExpr(self, obj);
        try self.emit(".insert(__global_allocator, @intCast(");
        try self.genExpr(args[0]);
        try self.emit("), ");
        if (elem_is_pyvalue) {
            try emitPyValueFromAlloc(self, args[1]);
        } else {
            try self.genExpr(args[1]);
        }
        try self.emit(")");
    }
}

/// Generate code for list.remove(item)
/// Removes first occurrence of item
pub fn genRemove(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // list.remove() requires exactly 1 argument
    if (args.len != 1) return error.UnsupportedSyntax;

    // Generate: { const idx = std.mem.indexOfScalar(T, list.items, item).?; _ = list.orderedRemove(idx); }
    const idx = try self.name_gen.temp();
    try self.emitFmt("{{ const {s} = std.mem.indexOfScalar(i64, ", .{idx});
    try self.genExpr(obj);
    try self.emit(".items, ");
    try self.genExpr(args[0]);
    try self.emit(").?; _ = ");
    try self.genExpr(obj);
    try self.emitFmt(".orderedRemove({s}); }}", .{idx});
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
        // Generate: { var list_temp = expr; std.mem.reverse(i64, list_temp.items); }
        const list_temp = try self.name_gen.temp();
        try self.emitFmt("{{ var {s} = ", .{list_temp});
        try self.genExpr(obj);
        try self.emitFmt("; std.mem.reverse(i64, {s}.items); }}", .{list_temp});
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
        // Generate: { var list_temp = expr; std.mem.sort(i64, list_temp.items, {}, comptime std.sort.asc(i64)); }
        const list_temp = try self.name_gen.temp();
        try self.emitFmt("{{ var {s} = ", .{list_temp});
        try self.genExpr(obj);
        try self.emitFmt("; std.mem.sort(i64, {s}.items, {{}}, comptime std.sort.asc(i64)); }}", .{list_temp});
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

    // Handle list literals and temporary expressions that need temp variable
    if (needsTempVariable(obj)) {
        const list_temp = try self.name_gen.temp();
        try self.emitFmt("{{ var {s} = ", .{list_temp});
        try self.genExpr(obj);
        try self.emitFmt("; {s}.clearRetainingCapacity(); }}", .{list_temp});
    } else {
        // Generate: list.clearRetainingCapacity()
        try emitObjExpr(self, obj);
        try self.emit(".clearRetainingCapacity()");
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
            try self.withInlineBlock("copy", obj, struct {
                fn emit(s: *NativeCodegen, label: []const u8, o: ast.Node) CodegenError!void {
                    const list_temp = try s.name_gen.temp();
                    try s.emitFmt("const {s} = ", .{list_temp});
                    try s.genExpr(o);
                    try s.emitFmt("; break :{s} try {s}.clone()", .{ label, list_temp });
                }
            }.emit);
        } else {
            try self.emit("try ");
            try emitObjExpr(self, obj);
            try self.emit(".clone()");
        }
    } else {
        // ArrayList.clone() requires allocator argument
        if (needsTempVariable(obj)) {
            try self.withInlineBlock("copy", obj, struct {
                fn emit(s: *NativeCodegen, label: []const u8, o: ast.Node) CodegenError!void {
                    const list_temp = try s.name_gen.temp();
                    try s.emitFmt("const {s} = ", .{list_temp});
                    try s.genExpr(o);
                    try s.emitFmt("; break :{s} try {s}.clone(__global_allocator)", .{ label, list_temp });
                }
            }.emit);
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
    const ext_item = try self.name_gen.temp();
    if (arg == .list) {
        // Array literals: iterate directly with &
        try self.emit("{ for (&");
        try self.genExpr(arg);
        try self.emitFmt(") |{s}| {{ try ", .{ext_item});
        try self.genExpr(obj);
        try self.emitFmt(".insert(__global_allocator, 0, {s}); }} }}", .{ext_item});
    } else {
        // ArrayList variable: use .items
        const ext_temp = try self.name_gen.temp();
        try self.emitFmt("{{ const {s} = ", .{ext_temp});
        try self.genExpr(arg);
        try self.emitFmt(".items; for ({s}) |{s}| {{ try ", .{ ext_temp, ext_item });
        try self.genExpr(obj);
        try self.emitFmt(".insert(__global_allocator, 0, {s}); }} }}", .{ext_item});
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

// ============================================================================
// Unknown-typed list operations (for module-level variables in closures)
// These generate runtime calls that work with any list-like PyValue
// ============================================================================

/// Generate code for list.append(item) on unknown-typed objects
/// Used when type inference returns .unknown (e.g., module-level vars in closures)
/// Generates: runtime.pyListAppendPV(__global_allocator, &obj, runtime.PyValue.from(item))
pub fn genAppendUnknown(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return error.UnsupportedSyntax;

    // Use the same PyValue-first API as uncertain types
    // In defer blocks, 'try' is not allowed - use catch unreachable instead
    try emitPyListAppendPV(self, obj, args[0], !self.inside_defer, self.inside_defer);
}

/// Generate code for list.extend(iterable) on unknown-typed objects
/// Generates: runtime.pyListExtendPV(__global_allocator, &obj, runtime.PyValue.from(arg))
pub fn genExtendUnknown(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return error.UnsupportedSyntax;

    // Use the same PyValue-first API as uncertain types
    try emitPyListExtendPV(self, obj, args[0]);
}

/// Generate code for list.insert(idx, item) on unknown-typed objects
/// Generates: runtime.pyListInsertPV(__global_allocator, &obj, idx, runtime.PyValue.from(item))
pub fn genInsertUnknown(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 2) return error.UnsupportedSyntax;

    // Use the same PyValue-first API as uncertain types
    try emitPyListInsertPV(self, obj, args[0], args[1]);
}

/// Generate code for list.pop() on unknown-typed objects
/// Generates: runtime.pyListPopPV(&obj, idx) or runtime.pyListPopPV(&obj, null)
pub fn genPopUnknown(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    const at_module_level = self.current_function_name == null;
    const cannot_use_try = at_module_level or self.inside_defer;

    if (!cannot_use_try) try self.emit("try ");
    try self.emit("runtime.pyListPopPV(&");
    try emitObjExpr(self, obj);
    try self.emit(", ");
    if (args.len > 0) {
        // list.pop(idx) - pop at specific index
        try self.genExpr(args[0]);
    } else {
        // list.pop() - pop last item (null means last)
        try self.emit("null");
    }
    try self.emit(")");
    if (cannot_use_try) try self.emit(" catch unreachable");
}

/// Generate code for list.clear() on unknown-typed objects
/// Generates: runtime.pyListClearPV(&obj)
pub fn genClearUnknown(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;

    try self.emit("runtime.pyListClearPV(&");
    try emitObjExpr(self, obj);
    try self.emit(")");
}
