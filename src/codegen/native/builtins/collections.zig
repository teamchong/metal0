/// Collection builtins: sum(), all(), any(), sorted(), reversed(), enumerate(), zip()
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const producesBlockExpression = @import("../expressions.zig").producesBlockExpression;

/// String method codegen patterns for map(str.method, items)
const StrMethodPatterns = std.StaticStringMap([]const u8).initComptime(.{
    .{ "strip", "const __mapped = std.mem.trim(u8, __map_item, \" \\t\\r\\n\");\n" },
    .{ "upper", "const __mapped = runtime.str.upper(__global_allocator, __map_item) catch __map_item;\n" },
    .{ "lower", "const __mapped = runtime.str.lower(__global_allocator, __map_item) catch __map_item;\n" },
    .{ "lstrip", "const __mapped = std.mem.trimLeft(u8, __map_item, \" \\t\\r\\n\");\n" },
    .{ "rstrip", "const __mapped = std.mem.trimRight(u8, __map_item, \" \\t\\r\\n\");\n" },
});

/// Type conversion result types for map(int, ...), map(float, ...), map(str, ...)
const TypeConvResultTypes = std.StaticStringMap([]const u8).initComptime(.{
    .{ "int", "i64" },
    .{ "float", "f64" },
    .{ "str", "[]const u8" },
});

/// Type conversion code patterns
const TypeConvPatterns = std.StaticStringMap([]const u8).initComptime(.{
    .{ "int", "const __mapped = std.fmt.parseInt(i64, __map_item, 10) catch 0;\n" },
    .{ "float", "const __mapped = std.fmt.parseFloat(f64, __map_item) catch 0.0;\n" },
    .{ "str", "const __mapped = std.fmt.allocPrint(__global_allocator, \"{any}\", .{__map_item}) catch \"\";\n" },
});

/// Generate code for range(stop) or range(start, stop) or range(start, stop, step)
/// Returns an iterable range object (PyObject list)
pub fn genRange(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("(try runtime.builtins.range(__global_allocator, 0, 0, 1))");
        return;
    }

    // Generate runtime.builtins.range(allocator, start, stop, step)
    // Wrap each arg in @as(i64, @intCast(...)) to handle usize loop variables
    try self.emit("(try runtime.builtins.range(__global_allocator, ");
    if (args.len == 1) {
        // range(stop) -> range(0, stop, 1)
        try self.emit("0, @as(i64, @intCast(");
        try self.genExpr(args[0]);
        try self.emit(")), 1");
    } else if (args.len == 2) {
        // range(start, stop) -> range(start, stop, 1)
        try self.emit("@as(i64, @intCast(");
        try self.genExpr(args[0]);
        try self.emit(")), @as(i64, @intCast(");
        try self.genExpr(args[1]);
        try self.emit(")), 1");
    } else {
        // range(start, stop, step)
        try self.emit("@as(i64, @intCast(");
        try self.genExpr(args[0]);
        try self.emit(")), @as(i64, @intCast(");
        try self.genExpr(args[1]);
        try self.emit(")), @as(i64, @intCast(");
        try self.genExpr(args[2]);
        try self.emit("))");
    }
    try self.emit("))");
}

/// Generate code for enumerate(iterable)
/// Returns: list of (index, value) tuples
pub fn genEnumerate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(*anyopaque, null)");
        return;
    }

    const iterable = args[0];
    const start = if (args.len > 1) args[1] else null;

    // Infer iterable type
    const iterable_type = try self.inferExprScoped(iterable);
    const needs_items = @as(std.meta.Tag(@TypeOf(iterable_type)), iterable_type) == .list;

    // Generate block that builds list of (index, value) tuples
    try self.emit("(enum_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const __enum_iterable = ");
    try self.genExpr(iterable);
    try self.emit(";\n");
    try self.emitIndent();
    if (needs_items) {
        try self.emit("const __enum_slice = __enum_iterable.items;\n");
    } else {
        try self.emit("const __enum_slice = __enum_iterable;\n");
    }
    try self.emitIndent();
    try self.emit("var __enum_result = std.ArrayList(std.meta.Tuple(&[_]type{i64, @TypeOf(__enum_slice[0])})){};\n");
    try self.emitIndent();
    try self.emit("var __enum_idx: i64 = ");
    if (start) |s| {
        try self.genExpr(s);
    } else {
        try self.emit("0");
    }
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("for (__enum_slice) |__enum_item| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("__enum_result.append(__global_allocator, .{__enum_idx, __enum_item}) catch {};\n");
    try self.emitIndent();
    try self.emit("__enum_idx += 1;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :enum_blk __enum_result;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("})");
}

/// Generate code for zip(iter1, iter2, ...)
/// Returns: iterator of tuples
/// Note: zip() is best handled in for-loop context by statements.zig
/// Standalone usage not supported in native codegen
pub fn genZip(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // zip() is only supported in for-loops, not as a standalone expression
    try self.emit("@compileError(\"zip() only supported in for-loops: for x, y in zip(list1, list2)\")");
}

/// Generate code for sum(iterable)
/// Returns sum of all elements
pub fn genSum(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("return error.TypeError");
        return;
    }

    // Generate: blk: {
    //   var total: i64 = 0;
    //   for (items.items) |item| { total += item; }  // .items for ArrayList
    //   break :blk total;
    // }

    // Check if iterating over array variable (no .items) vs ArrayList
    const is_array_var = blk: {
        if (args[0] == .name) {
            const var_name = args[0].name.id;
            break :blk self.isArrayVar(var_name);
        }
        break :blk false;
    };

    const needs_wrap = producesBlockExpression(args[0]);

    try self.emit("blk: {\n");
    // If block expression, create temp variable first
    if (needs_wrap) {
        try self.emit("const __iterable = ");
        try self.genExpr(args[0]);
        try self.emit(";\n");
    }
    try self.emit("var total: i64 = 0;\n");
    try self.emit("for (");
    if (needs_wrap) {
        try self.emit("__iterable.items");
    } else {
        try self.genExpr(args[0]);
        // ArrayList needs .items for iteration, arrays don't
        if (!is_array_var) {
            try self.emit(".items");
        }
    }
    try self.emit(") |item| { total += item; }\n");
    try self.emit("break :blk total;\n");
    try self.emit("}");
}

/// Generate code for all(iterable)
/// Returns true if all elements are truthy
pub fn genAll(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("return error.TypeError");
        return;
    }

    // Generate: blk: {
    //   for (items.items) |item| {  // .items for ArrayList
    //     if (item == 0) break :blk false;
    //   }
    //   break :blk true;
    // }

    const needs_wrap = producesBlockExpression(args[0]);

    try self.emit("blk: {\n");
    // If block expression, create temp variable first
    if (needs_wrap) {
        try self.emit("const __iterable = ");
        try self.genExpr(args[0]);
        try self.emit(";\n");
    }
    try self.emit("for (");
    if (needs_wrap) {
        try self.emit("__iterable.items");
    } else {
        try self.genExpr(args[0]);
        try self.emit(".items");
    }
    try self.emit(") |item| {\n");
    try self.emit("if (item == 0) break :blk false;\n");
    try self.emit("}\n");
    try self.emit("break :blk true;\n");
    try self.emit("}");
}

/// Generate code for any(iterable)
/// Returns true if any element is truthy
pub fn genAny(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("return error.TypeError");
        return;
    }

    // Generate: any_N: {
    //   for (items) |item| {  // Direct iteration for arrays/slices
    //   // OR for (items.items) |item| { // .items for ArrayList/genexp
    //     if (@TypeOf(item) == bool) { if (item) break :any_N true; }
    //     else { if (item != 0) break :any_N true; }
    //   }
    //   break :any_N false;
    // }

    // Use unique label to avoid conflicts with outer blocks
    const any_label_id = self.block_label_counter;
    self.block_label_counter += 1;

    // Check if argument is a list/tuple literal (fixed array) or genexp/listcomp (ArrayList)
    const is_list_literal = (args[0] == .list or args[0] == .tuple);
    const is_arraylist = (args[0] == .genexp or args[0] == .listcomp);
    const needs_wrap = producesBlockExpression(args[0]);

    try self.output.writer(self.allocator).print("any_{d}: {{\n", .{any_label_id});
    // If block expression, create temp variable first
    if (needs_wrap) {
        try self.emit("const __iterable = ");
        try self.genExpr(args[0]);
        try self.emit(";\n");
    }
    try self.emit("for (");
    if (needs_wrap) {
        if (is_arraylist) {
            // genexp/listcomp produce ArrayList - need .items
            try self.emit("__iterable.items");
        } else {
            // List/tuple/dict literals produce fixed arrays - iterate directly
            try self.emit("__iterable");
        }
    } else if (is_list_literal) {
        // Fixed array from list literal - iterate directly
        try self.genExpr(args[0]);
    } else {
        // ArrayList variable - need .items
        try self.genExpr(args[0]);
        try self.emit(".items");
    }
    try self.emit(") |item| {\n");
    // Use comptime type check for truthy semantics - bool vs int
    try self.output.writer(self.allocator).print("if (@TypeOf(item) == bool) {{ if (item) break :any_{d} true; }} else {{ if (item != 0) break :any_{d} true; }}\n", .{ any_label_id, any_label_id });
    try self.emit("}\n");
    try self.output.writer(self.allocator).print("break :any_{d} false;\n", .{any_label_id});
    try self.emit("}");
}

/// Generate code for sorted(iterable)
/// Returns sorted copy
pub fn genSorted(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("return error.TypeError");
        return;
    }

    // Generate: blk: {
    //   var copy = try allocator.dupe(i64, items);
    //   std.mem.sort(i64, copy, {}, comptime std.sort.asc(i64));
    //   break :blk copy;
    // }
    // Always use __global_allocator since method allocator param may be discarded as "_"
    const alloc_name = "__global_allocator";

    try self.emit("blk: {\n");
    try self.emitFmt("const copy = try {s}.dupe(i64, ", .{alloc_name});
    try self.genExpr(args[0]);
    try self.emit(");\n");
    try self.emit("std.mem.sort(i64, copy, {}, comptime std.sort.asc(i64));\n");
    try self.emit("break :blk copy;\n");
    try self.emit("}");
}

/// Generate code for reversed(iterable)
/// Returns reversed copy of list
pub fn genReversed(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        // Wrong number of args - emit error for assertRaises compatibility
        try self.emit("return error.TypeError");
        return;
    }

    // Infer element type from argument
    const arg_type = try self.inferExprScoped(args[0]);
    const elem_zig_type: []const u8 = switch (@as(std.meta.Tag(@TypeOf(arg_type)), arg_type)) {
        .string => "u8", // Strings/bytes are []const u8
        .list => blk: {
            // Get element type from list
            var type_buf = std.ArrayList(u8){};
            try arg_type.list.*.toZigType(self.allocator, &type_buf);
            break :blk try type_buf.toOwnedSlice(self.allocator);
        },
        else => "i64", // Default to i64 for unknown types
    };

    // Generate: blk: {
    //   var copy = try allocator.dupe(elem_type, items);
    //   std.mem.reverse(elem_type, copy);
    //   break :blk copy;
    // }
    // Always use __global_allocator since method allocator param may be discarded as "_"
    const alloc_name = "__global_allocator";

    try self.emit("blk: {\n");
    try self.emitFmt("const copy = try {s}.dupe({s}, ", .{ alloc_name, elem_zig_type });
    try self.genExpr(args[0]);
    try self.emit(");\n");
    try self.emitFmt("std.mem.reverse({s}, copy);\n", .{elem_zig_type});
    try self.emit("break :blk copy;\n");
    try self.emit("}");
}

/// Generate code for map(func, iterable)
/// Applies function to each element
/// Supports common patterns like map(str.strip, items) and map(int, items)
pub fn genMap(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("@compileError(\"map() requires 2 arguments\")");
        return;
    }

    const func = args[0];
    const iterable = args[1];

    // Check iterable type to determine if we need .items for ArrayList
    const iterable_type = try self.inferExprScoped(iterable);
    const needs_items = @as(std.meta.Tag(@TypeOf(iterable_type)), iterable_type) == .list;

    // Check for known method patterns: map(str.strip, items) or map(str.split, items)
    if (func == .attribute) {
        const attr = func.attribute;
        if (attr.value.* == .name) {
            const type_name = attr.value.name.id;
            const method_name = attr.attr;

            // Handle str.strip, str.upper, str.lower, etc.
            if (std.mem.eql(u8, type_name, "str")) {
                const pattern = StrMethodPatterns.get(method_name) orelse "const __mapped = __map_item; // unsupported str method\n";
                try self.emit("__map_blk: {\n");
                self.indent();
                try self.emitIndent();
                try self.emit("var __map_result = std.ArrayList([]const u8){};\n");
                try self.emitIndent();
                try self.emit("const __map_iterable = ");
                try self.genExpr(iterable);
                try self.emit(";\n");
                try self.emitIndent();
                if (needs_items) {
                    try self.emit("for (__map_iterable.items) |__map_item| {\n");
                } else {
                    try self.emit("for (__map_iterable) |__map_item| {\n");
                }
                self.indent();
                try self.emitIndent();
                try self.emit(pattern);
                try self.emitIndent();
                try self.emit("__map_result.append(__global_allocator, __mapped) catch {};\n");
                self.dedent();
                try self.emitIndent();
                try self.emit("}\n");
                try self.emitIndent();
                try self.emit("break :__map_blk __map_result;\n");
                self.dedent();
                try self.emitIndent();
                try self.emit("}");
                return;
            }
        }
    }

    // Handle type conversion: map(int, items), map(float, items), map(str, items)
    if (func == .name) {
        const func_name = func.name.id;
        if (TypeConvResultTypes.get(func_name)) |result_type| {
            const conv_pattern = TypeConvPatterns.get(func_name) orelse "const __mapped = __map_item;\n";
            try self.emit("__map_blk: {\n");
            self.indent();
            try self.emitIndent();
            try self.emitFmt("var __map_result = std.ArrayList({s}){{}};\n", .{result_type});
            try self.emitIndent();
            try self.emit("const __map_iterable = ");
            try self.genExpr(iterable);
            try self.emit(";\n");
            try self.emitIndent();
            if (needs_items) {
                try self.emit("for (__map_iterable.items) |__map_item| {\n");
            } else {
                try self.emit("for (__map_iterable) |__map_item| {\n");
            }
            self.indent();
            try self.emitIndent();
            try self.emit(conv_pattern);
            try self.emitIndent();
            try self.emit("__map_result.append(__global_allocator, __mapped) catch {};\n");
            self.dedent();
            try self.emitIndent();
            try self.emit("}\n");
            try self.emitIndent();
            try self.emit("break :__map_blk __map_result;\n");
            self.dedent();
            try self.emitIndent();
            try self.emit("}");
            return;
        }
    }

    // Handle lambda: map(lambda x: x * 2, items)
    if (func == .lambda) {
        const lambda = func.lambda;
        // Infer result type from lambda body
        const result_type = self.type_inferrer.inferExpr(lambda.body.*) catch .unknown;
        var type_buf = std.ArrayList(u8){};
        defer type_buf.deinit(self.allocator);
        try result_type.toZigType(self.allocator, &type_buf);
        const zig_result_type = type_buf.items;

        try self.emit("(__map_blk: {\n");
        self.indent();
        try self.emitIndent();
        try self.emitFmt("var __map_result = std.ArrayList({s}){{}};\n", .{zig_result_type});
        try self.emitIndent();
        try self.emit("const __map_iterable = ");
        try self.genExpr(iterable);
        try self.emit(";\n");
        try self.emitIndent();
        if (needs_items) {
            try self.emit("for (__map_iterable.items) |__map_item| {\n");
        } else {
            try self.emit("for (__map_iterable) |__map_item| {\n");
        }
        self.indent();
        try self.emitIndent();

        // Generate inline lambda body with __map_item substituted for parameter
        // Assumes single parameter lambda
        if (lambda.args.len > 0) {
            const param_name = lambda.args[0].name;
            // Register param as alias for __map_item
            try self.var_renames.put(param_name, "__map_item");
            defer _ = self.var_renames.swapRemove(param_name);

            try self.emit("const __mapped = ");
            try self.genExpr(lambda.body.*);
            try self.emit(";\n");
        } else {
            try self.emit("const __mapped = ");
            try self.genExpr(lambda.body.*);
            try self.emit(";\n");
        }

        try self.emitIndent();
        try self.emit("__map_result.append(__global_allocator, __mapped) catch {};\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
        try self.emitIndent();
        try self.emit("break :__map_blk __map_result;\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("})");
        return;
    }

    // Fallback: Generate runtime map using anytype
    // For unknown functions, we store the iterable first, then infer from first element
    try self.emit("(__map_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const __map_iterable = ");
    try self.genExpr(iterable);
    try self.emit(";\n");
    try self.emitIndent();
    // Get slice to iterate over
    if (needs_items) {
        try self.emit("const __map_slice = __map_iterable.items;\n");
    } else {
        try self.emit("const __map_slice = __map_iterable;\n");
    }
    try self.emitIndent();
    try self.emit("const __map_func = ");
    try self.genExpr(func);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var __map_result = std.ArrayList(@TypeOf(__map_func(__map_slice[0]))){};\n");
    try self.emitIndent();
    try self.emit("for (__map_slice) |__map_item| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const __mapped = __map_func(__map_item);\n");
    try self.emitIndent();
    try self.emit("__map_result.append(__global_allocator, __mapped) catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :__map_blk __map_result;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("})");
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
    try self.emit("@compileError(\"filter() not supported - use explicit for loop with if instead\")");
}

/// Generate code for iter(iterable)
/// Returns a stateful iterator over the iterable
pub fn genIter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) {
        try self.emit("@as(?*anyopaque, null)");
        return;
    }

    // Infer the type of the iterable to choose the right iterator
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    // For strings, create a stateful StringIterator
    if (arg_type == .string) {
        try self.emit("runtime.builtins.strIterator(");
        try self.genExpr(args[0]);
        try self.emit(")");
        return;
    }

    // For other types, pass through (they handle iteration differently)
    try self.genExpr(args[0]);
}

/// Generate code for next(iterator, [default])
/// Returns the next item from the iterator
pub fn genNext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) {
        try self.emit("@as(?*anyopaque, null)");
        return;
    }

    // For custom iterator objects with __next__ method
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;
    if (arg_type == .class_instance) {
        try self.genExpr(args[0]);
        try self.emit(".__next__()");
        return;
    }

    // For StringIterator and other stateful iterators, pass pointer for mutation
    // The runtime.builtins.next() function handles both pointers and values
    try self.emit("runtime.builtins.next(&");
    try self.genExpr(args[0]);
    try self.emit(")");
}

// Built-in functions implementation status:
// ✅ Implemented: sum, all, any, sorted, reversed, iter, next
// ❌ Not supported (need function pointers): map, filter
// ❌ Not supported (need for-loop integration): enumerate, zip
//
// Future improvements:
// - Add enumerate/zip support in for-loop codegen (statements.zig)
// - Consider comptime function pointer support for map/filter
