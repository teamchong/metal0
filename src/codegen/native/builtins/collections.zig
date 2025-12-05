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
    try self.emit("var __enum_result = std.ArrayListUnmanaged(std.meta.Tuple(&[_]type{i64, @TypeOf(__enum_slice[0])})){};\n");
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
/// Returns: ArrayList of tuples pairing elements from each iterable
/// Note: zip() in for-loops is optimized by for_special.zig
pub fn genZip(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("std.ArrayListUnmanaged(struct{}){}");
        return;
    }

    // Generate block that creates list of tuples
    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    try self.output.writer(self.allocator).print("zip_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Store each iterable with .items access for ArrayLists
    for (args, 0..) |arg, i| {
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const __zip_arg_{d} = ", .{i});
        try self.genExpr(arg);
        // Check if it's a list type that needs .items
        const arg_type = self.type_inferrer.inferExpr(arg) catch .unknown;
        if (arg_type == .list) {
            try self.emit(".items");
        }
        try self.emit(";\n");
    }

    // Calculate minimum length
    try self.emitIndent();
    try self.emit("const __zip_len = @min(");
    for (0..args.len) |i| {
        if (i > 0) try self.emit(", ");
        try self.output.writer(self.allocator).print("__zip_arg_{d}.len", .{i});
    }
    try self.emit(");\n");

    // Create result list - use anytype tuple struct
    try self.emitIndent();
    try self.emit("var __zip_result = std.ArrayListUnmanaged(struct { ");
    for (0..args.len) |i| {
        if (i > 0) try self.emit(", ");
        try self.output.writer(self.allocator).print("@\"{d}\": @TypeOf(__zip_arg_{d}[0])", .{ i, i });
    }
    try self.emit(" }){};\n");

    // Iterate and build tuples
    try self.emitIndent();
    try self.emit("var __zip_i: usize = 0;\n");
    try self.emitIndent();
    try self.emit("while (__zip_i < __zip_len) : (__zip_i += 1) {\n");
    self.indent_level += 1;
    try self.emitIndent();
    try self.emit("try __zip_result.append(__global_allocator, .{ ");
    for (0..args.len) |i| {
        if (i > 0) try self.emit(", ");
        try self.output.writer(self.allocator).print("__zip_arg_{d}[__zip_i]", .{i});
    }
    try self.emit(" });\n");
    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :zip_{d} __zip_result;\n", .{label_id});
    try self.emitIndent();
    try self.emit("}");
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
    //   var __sorted_copy = try allocator.dupe(i64, items);
    //   std.mem.sort(i64, __sorted_copy, {}, comptime std.sort.asc(i64));
    //   break :blk __sorted_copy;
    // }
    // Always use __global_allocator since method allocator param may be discarded as "_"
    // Use __sorted_copy to avoid shadowing any imported 'copy' module
    const alloc_name = "__global_allocator";

    try self.emit("blk: {\n");
    try self.emitFmt("const __sorted_copy = try {s}.dupe(i64, ", .{alloc_name});
    try self.genExpr(args[0]);
    try self.emit(");\n");
    try self.emit("std.mem.sort(i64, __sorted_copy, {}, comptime std.sort.asc(i64));\n");
    try self.emit("break :blk __sorted_copy;\n");
    try self.emit("}");
}

/// Generate code for reversed(iterable)
/// Returns reversed copy of list, or reversed keys for dict
pub fn genReversed(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        // Wrong number of args - emit error for assertRaises compatibility
        try self.emit("return error.TypeError");
        return;
    }

    // Check if arg is a dict literal or dict() call
    const is_dict = blk: {
        if (args[0] == .dict) break :blk true;
        if (args[0] == .call) {
            const call = args[0].call;
            if (call.func.* == .name and std.mem.eql(u8, call.func.name.id, "dict")) {
                break :blk true;
            }
        }
        break :blk false;
    };

    const alloc_name = "__global_allocator";

    if (is_dict) {
        // For dicts, reversed() returns reversed keys
        try self.emit("__rev_dict_blk: {\n");
        try self.emit("const _raw_iterable = ");
        try self.genExpr(args[0]);
        try self.emit(";\n");
        try self.emit("const _iterable = if (@typeInfo(@TypeOf(_raw_iterable)) == .error_union) try _raw_iterable else _raw_iterable;\n");
        try self.emitFmt("const __reversed_copy = try {s}.dupe([]const u8, _iterable.keys());\n", .{alloc_name});
        try self.emit("std.mem.reverse([]const u8, __reversed_copy);\n");
        try self.emit("break :__rev_dict_blk __reversed_copy;\n");
        try self.emit("}");
        return;
    }

    // Infer element type from argument
    const arg_type = try self.inferExprScoped(args[0]);
    const arg_tag = @as(std.meta.Tag(@TypeOf(arg_type)), arg_type);
    const is_bytes = arg_tag == .bytes;
    const elem_zig_type: []const u8 = switch (arg_tag) {
        .string, .bytes => "u8", // Strings/bytes are []const u8 or PyBytes (element is u8)
        .list => blk: {
            // Get element type from list
            var type_buf = std.ArrayListUnmanaged(u8){};
            try arg_type.list.*.toZigType(self.allocator, &type_buf);
            break :blk try type_buf.toOwnedSlice(self.allocator);
        },
        .dict => "[]const u8", // Dict keys are strings
        else => "i64", // Default to i64 for unknown types
    };

    // Generate: blk: {
    //   const _input = data;
    //   // Coerce array to slice if needed using @as and &
    //   const _slice = if (@typeInfo(@TypeOf(_input)) == .array) &_input else _input;
    //   var copy = try allocator.dupe(elem_type, _slice);
    //   std.mem.reverse(elem_type, copy);
    //   break :blk copy;  // or PyBytes.init(copy) for bytes
    // }

    try self.emit("blk: {\n");
    try self.emit("const _rev_input = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    // Handle PyBytes struct (has .data field), arrays, and slices
    try self.emit("const _rev_slice = blk2: {\n");
    try self.emit("    const T = @TypeOf(_rev_input);\n");
    try self.emit("    if (@typeInfo(T) == .@\"struct\" and @hasField(T, \"data\")) break :blk2 _rev_input.data\n");
    try self.emit("    else if (@typeInfo(T) == .array) break :blk2 @as([]const @typeInfo(T).array.child, &_rev_input)\n");
    try self.emit("    else break :blk2 _rev_input;\n");
    try self.emit("};\n");
    try self.emitFmt("const __reversed_copy = try {s}.dupe({s}, _rev_slice);\n", .{ alloc_name, elem_zig_type });
    try self.emitFmt("std.mem.reverse({s}, __reversed_copy);\n", .{elem_zig_type});
    if (is_bytes) {
        // Wrap result in PyBytes for bytes input
        try self.emit("break :blk runtime.builtins.PyBytes.init(__reversed_copy);\n");
    } else {
        try self.emit("break :blk __reversed_copy;\n");
    }
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
                try self.emit("var __map_result = std.ArrayListUnmanaged([]const u8){};\n");
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
            try self.emitFmt("var __map_result = std.ArrayListUnmanaged({s}){{}};\n", .{result_type});
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
        var type_buf = std.ArrayListUnmanaged(u8){};
        defer type_buf.deinit(self.allocator);
        try result_type.toZigType(self.allocator, &type_buf);
        const zig_result_type = type_buf.items;

        try self.emit("(__map_blk: {\n");
        self.indent();
        try self.emitIndent();
        try self.emitFmt("var __map_result = std.ArrayListUnmanaged({s}){{}};\n", .{zig_result_type});
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
    // Use iterSlice to handle all iterable types (ArrayList, PyValue, slice, etc.)
    try self.emit("(__map_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const __map_iterable = ");
    try self.genExpr(iterable);
    try self.emit(";\n");
    try self.emitIndent();
    // Use iterSlice for universal iterable handling (ArrayList, PyValue, slice, etc.)
    try self.emit("const __map_slice = runtime.iterSlice(__map_iterable);\n");
    try self.emitIndent();
    try self.emit("const __map_func = ");
    try self.genExpr(func);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var __map_result = std.ArrayListUnmanaged(@TypeOf(__map_func(__map_slice[0]))){};\n");
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

    // For tuples/arrays/slices, create a proper SequenceIterator
    if (arg_type == .tuple or arg_type == .list) {
        // Check if this is an ArrayList variable (needs .items accessor)
        const is_arraylist = if (args[0] == .name)
            self.isArrayListVar(args[0].name.id)
        else
            false;

        if (is_arraylist) {
            // ArrayList variable: use .items to get slice
            try self.emit("runtime.iterators.iter(i64, ");
            try self.genExpr(args[0]);
            try self.emit(".items)");
        } else {
            // Use runtime check to handle both ArrayList and fixed array
            try self.emit("iter_list_blk: { const __iterable = ");
            try self.genExpr(args[0]);
            try self.emit("; break :iter_list_blk runtime.iterators.iter(i64, if (@hasField(@TypeOf(__iterable), \"items\")) __iterable.items else __iterable); }");
        }
        return;
    }

    // For unknown types, try to create an iterator at runtime
    // This handles cases where the type can't be inferred at compile time
    try self.emit("iter_blk: { const _iterable = ");
    try self.genExpr(args[0]);
    try self.emit("; const _iter_type = @typeInfo(@TypeOf(_iterable)); ");
    try self.emit("break :iter_blk if (_iter_type == .pointer and _iter_type.pointer.size == .slice) ");
    try self.emit("runtime.iterators.SequenceIterator(@typeInfo(_iter_type.pointer.child).array.child).init(_iterable) ");
    try self.emit("else if (_iter_type == .array) ");
    try self.emit("runtime.iterators.SequenceIterator(_iter_type.array.child).init(&_iterable) ");
    try self.emit("else _iterable; }");
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
    // The runtime.builtins.next() returns an error union, wrap with try/catch
    // Use catch to convert StopIteration/TypeError to panic (matches Python semantics)
    try self.emit("(runtime.builtins.next(&");
    try self.genExpr(args[0]);
    try self.emit(") catch |err| switch (err) { error.StopIteration => @panic(\"StopIteration\"), error.TypeError => @panic(\"TypeError: object is not an iterator\") })");
}

// Built-in functions implementation status:
// ✅ Implemented: sum, all, any, sorted, reversed, iter, next
// ❌ Not supported (need function pointers): map, filter
// ❌ Not supported (need for-loop integration): enumerate, zip
//
// Future improvements:
// - Add enumerate/zip support in for-loop codegen (statements.zig)
// - Consider comptime function pointer support for map/filter
