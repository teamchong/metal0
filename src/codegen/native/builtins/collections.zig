/// Collection builtins: sum(), all(), any(), sorted(), reversed(), enumerate(), zip()
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const producesBlockExpression = @import("../expressions.zig").producesBlockExpression;
const string_traits = @import("../../../analysis/traits/string_traits.zig");
const container_traits = @import("../../../analysis/traits/container_traits.zig");
const type_traits = @import("../../../analysis/traits/type_traits.zig");
const expr_emitter = @import("../expr_emitter.zig");

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
        try emitConst(self,"(try runtime.builtins.range(__global_allocator, 0, 0, 1))");
        return;
    }

    // Generate runtime.builtins.range(allocator, start, stop, step)
    // Wrap each arg in @as(i64, @intCast(...)) to handle usize loop variables
    try emitConst(self,"(try runtime.builtins.range(__global_allocator, ");
    if (args.len == 1) {
        // range(stop) -> range(0, stop, 1)
        try emitConst(self,"0, @as(i64, @intCast(");
        try self.genExpr(args[0]);
        try emitConst(self,")), 1");
    } else if (args.len == 2) {
        // range(start, stop) -> range(start, stop, 1)
        try emitConst(self,"@as(i64, @intCast(");
        try self.genExpr(args[0]);
        try emitConst(self,")), @as(i64, @intCast(");
        try self.genExpr(args[1]);
        try emitConst(self,")), 1");
    } else {
        // range(start, stop, step)
        try emitConst(self,"@as(i64, @intCast(");
        try self.genExpr(args[0]);
        try emitConst(self,")), @as(i64, @intCast(");
        try self.genExpr(args[1]);
        try emitConst(self,")), @as(i64, @intCast(");
        try self.genExpr(args[2]);
        try emitConst(self,"))");
    }
    try emitConst(self,"))");
}

/// Generate code for enumerate(iterable)
/// Returns: list of (index, value) tuples
pub fn genEnumerate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self,"@as(*anyopaque, null)");
        return;
    }

    const iterable = args[0];
    const start = if (args.len > 1) args[1] else null;

    // Generate block that builds list of (index, value) tuples
    // Two-Flow: Use runtime.iterSlice for universal handling (ArrayList, PyValue, slice, etc.)
    const enum_id = self.nextNameId();
    try emitFmtConst(self, "(__m{d}_enum: {{\n", .{enum_id});
    self.indent();
    try self.emitIndent();
    try emitConst(self,"const __enum_iterable = ");
    try self.genExpr(iterable);
    try emitConst(self,";\n");
    try self.emitIndent();
    // runtime.iterSlice handles all iterable types: ArrayList→.items, PyValue→.list/.tuple, slice→slice
    try emitConst(self,"const __enum_slice = runtime.iterSlice(__enum_iterable);\n");
    try self.emitIndent();
    try emitConst(self,"var __enum_result = std.ArrayListUnmanaged(std.meta.Tuple(&[_]type{i64, @TypeOf(__enum_slice[0])})){};\n");
    try self.emitIndent();
    try emitConst(self,"var __enum_idx: i64 = ");
    if (start) |s| {
        try self.genExpr(s);
    } else {
        try emitConst(self,"0");
    }
    try emitConst(self,";\n");
    try self.emitIndent();
    try emitConst(self,"for (__enum_slice) |__enum_item| {\n");
    self.indent();
    try self.emitIndent();
    try emitConst(self,"__enum_result.append(__global_allocator, .{__enum_idx, __enum_item}) catch unreachable;\n");
    try self.emitIndent();
    try emitConst(self,"__enum_idx += 1;\n");
    self.dedent();
    try self.emitIndent();
    try emitConst(self,"}\n");
    try self.emitIndent();
    try emitFmtConst(self, "break :__m{d}_enum __enum_result;\n", .{enum_id});
    self.dedent();
    try self.emitIndent();
    try emitConst(self,"})");
}

/// Generate code for zip(iter1, iter2, ...)
/// Returns: ArrayList of tuples pairing elements from each iterable
/// Note: zip() in for-loops is optimized by for_special.zig
pub fn genZip(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try emitConst(self,"std.ArrayListUnmanaged(struct{}){}");
        return;
    }

    // Generate block that creates list of tuples
    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    try emitFmtConst(self, "zip_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    // Store each iterable with runtime.iterSlice for universal handling
    // Two-Flow: iterSlice handles ArrayList, PyValue, slice, etc.
    for (args, 0..) |arg, i| {
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const __zip_arg_{d} = runtime.iterSlice(", .{i});
        try self.genExpr(arg);
        try emitConst(self,");\n");
    }

    // Calculate minimum length
    try self.emitIndent();
    try emitConst(self,"const __zip_len = @min(");
    for (0..args.len) |i| {
        if (i > 0) try emitConst(self,", ");
        try self.output.writer(self.allocator).print("__zip_arg_{d}.len", .{i});
    }
    try emitConst(self,");\n");

    // Create result list - use anytype tuple struct
    try self.emitIndent();
    try emitConst(self,"var __zip_result = std.ArrayListUnmanaged(struct { ");
    for (0..args.len) |i| {
        if (i > 0) try emitConst(self,", ");
        try self.output.writer(self.allocator).print("@\"{d}\": @TypeOf(__zip_arg_{d}[0])", .{ i, i });
    }
    try emitConst(self," }){};\n");

    // Iterate and build tuples
    try self.emitIndent();
    try emitConst(self,"var __zip_i: usize = 0;\n");
    try self.emitIndent();
    try emitConst(self,"while (__zip_i < __zip_len) : (__zip_i += 1) {\n");
    self.indent_level += 1;
    try self.emitIndent();
    try emitConst(self,"try __zip_result.append(__global_allocator, .{ ");
    for (0..args.len) |i| {
        if (i > 0) try emitConst(self,", ");
        // Use named field initialization (.@"0" = val) for structs with named fields
        try self.output.writer(self.allocator).print(".@\"{d}\" = __zip_arg_{d}[__zip_i]", .{ i, i });
    }
    try emitConst(self," });\n");
    self.indent_level -= 1;
    try self.emitIndent();
    try emitConst(self,"}\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :zip_{d} __zip_result;\n", .{label_id});
    try self.emitIndent();
    try emitConst(self,"}");
}

/// Check if an iterable expression is uncertain (needs PyValue)
/// Two-Flow: routes uncertain types to PyValue methods
fn isIterableUncertain(self: *NativeCodegen, expr: ast.Node) bool {
    if (expr == .name) {
        const name = expr.name.id;
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

/// Generate code for sum(iterable)
/// Returns sum of all elements
/// Two-Flow: routes uncertain iterables to PyValue.pySum()
pub fn genSum(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self,"return error.TypeError");
        return;
    }

    // Two-Flow: Check if iterable is uncertain
    if (isIterableUncertain(self, args[0])) {
        // Route to PyValue.pySum() for runtime type safety
        try self.genExpr(args[0]);
        try emitConst(self,".pySum()");
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

    const sum_id = self.nextNameId();
    try emitFmtConst(self, "__m{d}_sum: {{\n", .{sum_id});
    // If block expression, create temp variable first
    if (needs_wrap) {
        try emitConst(self,"const __iterable = ");
        try self.genExpr(args[0]);
        try emitConst(self,";\n");
    }
    try emitConst(self,"var total: i64 = 0;\n");
    try emitConst(self,"for (");
    if (needs_wrap) {
        try emitConst(self,"__iterable.items");
    } else {
        try self.genExpr(args[0]);
        // ArrayList needs .items for iteration, arrays don't
        if (!is_array_var) {
            try emitConst(self,".items");
        }
    }
    try emitConst(self,") |item| { total += item; }\n");
    try emitFmtConst(self, "break :__m{d}_sum total;\n", .{sum_id});
    try emitConst(self,"}");
}

/// Generate code for all(iterable)
/// Returns true if all elements are truthy
/// Two-Flow: routes uncertain iterables to PyValue.pyAll()
pub fn genAll(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self,"return error.TypeError");
        return;
    }

    // Two-Flow: Check if iterable is uncertain
    if (isIterableUncertain(self, args[0])) {
        // Route to PyValue.pyAll() for runtime type safety
        try self.genExpr(args[0]);
        try emitConst(self,".pyAll()");
        return;
    }

    // Generate: blk: {
    //   for (items.items) |item| {  // .items for ArrayList
    //     if (item == 0) break :blk false;
    //   }
    //   break :blk true;
    // }

    const needs_wrap = producesBlockExpression(args[0]);

    const all_id = self.nextNameId();
    try emitFmtConst(self, "__m{d}_all: {{\n", .{all_id});
    // If block expression, create temp variable first
    if (needs_wrap) {
        try emitConst(self,"const __iterable = ");
        try self.genExpr(args[0]);
        try emitConst(self,";\n");
    }
    try emitConst(self,"for (");
    if (needs_wrap) {
        try emitConst(self,"__iterable.items");
    } else {
        try self.genExpr(args[0]);
        try emitConst(self,".items");
    }
    try emitConst(self,") |item| {\n");
    try emitFmtConst(self, "if (item == 0) break :__m{d}_all false;\n", .{all_id});
    try emitConst(self,"}\n");
    try emitFmtConst(self, "break :__m{d}_all true;\n", .{all_id});
    try emitConst(self,"}");
}

/// Generate code for any(iterable)
/// Returns true if any element is truthy
/// Two-Flow: routes uncertain iterables to PyValue.pyAny()
pub fn genAny(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self,"return error.TypeError");
        return;
    }

    // Two-Flow: Check if iterable is uncertain
    if (isIterableUncertain(self, args[0])) {
        // Route to PyValue.pyAny() for runtime type safety
        try self.genExpr(args[0]);
        try emitConst(self,".pyAny()");
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
    const any_id = self.nextNameId();

    // Check if argument is a list/tuple literal (fixed array) or genexp/listcomp (ArrayList)
    const is_list_literal = (args[0] == .list or args[0] == .tuple);
    const is_arraylist = (args[0] == .genexp or args[0] == .listcomp);
    const needs_wrap = producesBlockExpression(args[0]);

    try emitFmtConst(self, "__m{d}_any: {{\n", .{any_id});
    // If block expression, create temp variable first
    if (needs_wrap) {
        try emitConst(self,"const __iterable = ");
        try self.genExpr(args[0]);
        try emitConst(self,";\n");
    }
    try emitConst(self,"for (");
    if (needs_wrap) {
        if (is_arraylist) {
            // genexp/listcomp produce ArrayList - need .items
            try emitConst(self,"__iterable.items");
        } else {
            // List/tuple/dict literals produce fixed arrays - iterate directly
            try emitConst(self,"__iterable");
        }
    } else if (is_list_literal) {
        // Fixed array from list literal - iterate directly
        try self.genExpr(args[0]);
    } else {
        // ArrayList variable - need .items
        try self.genExpr(args[0]);
        try emitConst(self,".items");
    }
    try emitConst(self,") |item| {\n");
    // Use comptime type check for truthy semantics - bool vs int
    try emitFmtConst(self, "if (@TypeOf(item) == bool) {{ if (item) break :__m{d}_any true; }} else {{ if (item != 0) break :__m{d}_any true; }}\n", .{ any_id, any_id });
    try emitConst(self,"}\n");
    try emitFmtConst(self, "break :__m{d}_any false;\n", .{any_id});
    try emitConst(self,"}");
}

/// Generate code for sorted(iterable)
/// Returns sorted copy
pub fn genSorted(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self,"return error.TypeError");
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

    const sorted_id = self.nextNameId();
    try emitFmtConst(self, "__m{d}_sorted: {{\n", .{sorted_id});
    try emitFmtConst(self, "const __sorted_copy = try {s}.dupe(i64, ", .{alloc_name});
    try self.genExpr(args[0]);
    try emitConst(self,");\n");
    try emitConst(self,"std.mem.sort(i64, __sorted_copy, {}, comptime std.sort.asc(i64));\n");
    try emitFmtConst(self, "break :__m{d}_sorted __sorted_copy;\n", .{sorted_id});
    try emitConst(self,"}");
}

/// Generate code for reversed(iterable)
/// Returns reversed copy of list, or reversed keys for dict
pub fn genReversed(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        // Wrong number of args - emit error for assertRaises compatibility
        try emitConst(self,"return error.TypeError");
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
    // At module level (scope 0), we can't use 'try' - use 'catch unreachable' instead
    const at_module_level = self.symbol_table.currentScopeLevel() == 0;
    const try_prefix = if (at_module_level) "" else "try ";
    const catch_suffix = if (at_module_level) " catch unreachable" else "";

    if (is_dict) {
        // For dicts, reversed() returns reversed keys
        const rev_dict_id = self.nextNameId();
        try emitFmtConst(self, "__m{d}_rev_dict: {{\n", .{rev_dict_id});
        try emitConst(self,"const _raw_iterable = ");
        try self.genExpr(args[0]);
        try emitConst(self,";\n");
        if (at_module_level) {
            try emitConst(self,"const _iterable = _raw_iterable;\n");
        } else {
            try emitConst(self,"const _iterable = if (@typeInfo(@TypeOf(_raw_iterable)) == .error_union) try _raw_iterable else _raw_iterable;\n");
        }
        try emitFmtConst(self, "const __reversed_copy = {s}{s}.dupe([]const u8, _iterable.keys()){s};\n", .{ try_prefix, alloc_name, catch_suffix });
        try emitConst(self,"std.mem.reverse([]const u8, __reversed_copy);\n");
        try emitFmtConst(self, "break :__m{d}_rev_dict __reversed_copy;\n", .{rev_dict_id});
        try emitConst(self,"}");
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

    const rev_id = self.nextNameId();
    try emitFmtConst(self, "__m{d}_rev: {{\n", .{rev_id});
    try emitConst(self,"const _rev_input = ");
    try self.genExpr(args[0]);
    try emitConst(self,";\n");
    // Use container_dispatch helper - handles PyBytes (.data), ArrayList (.items), arrays, slices
    try emitConst(self,"const _rev_slice = runtime.container_dispatch.getSlice(@TypeOf(_rev_input), _rev_input);\n");
    try emitFmtConst(self, "const __reversed_copy = {s}{s}.dupe({s}, _rev_slice){s};\n", .{ try_prefix, alloc_name, elem_zig_type, catch_suffix });
    try emitFmtConst(self, "std.mem.reverse({s}, __reversed_copy);\n", .{elem_zig_type});
    if (is_bytes) {
        // Wrap result in PyBytes for bytes input
        try emitFmtConst(self, "break :__m{d}_rev runtime.builtins.PyBytes.init(__reversed_copy);\n", .{rev_id});
    } else {
        try emitFmtConst(self, "break :__m{d}_rev __reversed_copy;\n", .{rev_id});
    }
    try emitConst(self,"}");
}

/// Generate code for map(func, iterable)
/// Applies function to each element
/// Supports common patterns like map(str.strip, items) and map(int, items)
pub fn genMap(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        const map_err_id = self.nextNameId();
        try emitFmtConst(self, "(__m{d}_map_err: {{ @panic(\"map() requires 2 arguments\"); }})", .{map_err_id});
        return;
    }

    const func = args[0];
    const iterable = args[1];

    // Check iterable type to determine if we need .items for ArrayList
    const iterable_type = try self.inferExprScoped(iterable);
    const needs_items = container_traits.isList(iterable_type);

    // Check for known method patterns: map(str.strip, items) or map(str.split, items)
    if (func == .attribute) {
        const attr = func.attribute;
        if (attr.value.* == .name) {
            const type_name = attr.value.name.id;
            const method_name = attr.attr;

            // Handle str.strip, str.upper, str.lower, etc.
            if (std.mem.eql(u8, type_name, "str")) {
                const pattern = StrMethodPatterns.get(method_name) orelse "const __mapped = __map_item; // unsupported str method\n";
                const map_str_id = self.nextNameId();
                try emitFmtConst(self, "__m{d}_map_str: {{\n", .{map_str_id});
                self.indent();
                try self.emitIndent();
                try emitConst(self,"var __map_result = std.ArrayListUnmanaged([]const u8){};\n");
                try self.emitIndent();
                try emitConst(self,"const __map_iterable = ");
                try self.genExpr(iterable);
                try emitConst(self,";\n");
                try self.emitIndent();
                if (needs_items) {
                    try emitConst(self,"for (__map_iterable.items) |__map_item| {\n");
                } else {
                    try emitConst(self,"for (__map_iterable) |__map_item| {\n");
                }
                self.indent();
                try self.emitIndent();
                try emitConst(self,pattern);
                try self.emitIndent();
                try emitConst(self,"__map_result.append(__global_allocator, __mapped) catch unreachable;\n");
                self.dedent();
                try self.emitIndent();
                try emitConst(self,"}\n");
                try self.emitIndent();
                try emitFmtConst(self, "break :__m{d}_map_str __map_result;\n", .{map_str_id});
                self.dedent();
                try self.emitIndent();
                try emitConst(self,"}");
                return;
            }
        }
    }

    // Handle type conversion: map(int, items), map(float, items), map(str, items)
    if (func == .name) {
        const func_name = func.name.id;
        if (TypeConvResultTypes.get(func_name)) |result_type| {
            const conv_pattern = TypeConvPatterns.get(func_name) orelse "const __mapped = __map_item;\n";
            const map_conv_id = self.nextNameId();
            try emitFmtConst(self, "__m{d}_map_conv: {{\n", .{map_conv_id});
            self.indent();
            try self.emitIndent();
            try emitFmtConst(self, "var __map_result = std.ArrayListUnmanaged({s}){{}};\n", .{result_type});
            try self.emitIndent();
            try emitConst(self,"const __map_iterable = ");
            try self.genExpr(iterable);
            try emitConst(self,";\n");
            try self.emitIndent();
            if (needs_items) {
                try emitConst(self,"for (__map_iterable.items) |__map_item| {\n");
            } else {
                try emitConst(self,"for (__map_iterable) |__map_item| {\n");
            }
            self.indent();
            try self.emitIndent();
            try emitConst(self,conv_pattern);
            try self.emitIndent();
            try emitConst(self,"__map_result.append(__global_allocator, __mapped) catch unreachable;\n");
            self.dedent();
            try self.emitIndent();
            try emitConst(self,"}\n");
            try self.emitIndent();
            try emitFmtConst(self, "break :__m{d}_map_conv __map_result;\n", .{map_conv_id});
            self.dedent();
            try self.emitIndent();
            try emitConst(self,"}");
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

        const map_lambda_id = self.nextNameId();
        try emitFmtConst(self, "(__m{d}_map_lambda: {{\n", .{map_lambda_id});
        self.indent();
        try self.emitIndent();
        try emitFmtConst(self, "var __map_result = std.ArrayListUnmanaged({s}){{}};\n", .{zig_result_type});
        try self.emitIndent();
        try emitConst(self,"const __map_iterable = ");
        try self.genExpr(iterable);
        try emitConst(self,";\n");
        try self.emitIndent();
        if (needs_items) {
            try emitConst(self,"for (__map_iterable.items) |__map_item| {\n");
        } else {
            try emitConst(self,"for (__map_iterable) |__map_item| {\n");
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

            try emitConst(self,"const __mapped = ");
            try self.genExpr(lambda.body.*);
            try emitConst(self,";\n");
        } else {
            try emitConst(self,"const __mapped = ");
            try self.genExpr(lambda.body.*);
            try emitConst(self,";\n");
        }

        try self.emitIndent();
        try emitConst(self,"__map_result.append(__global_allocator, __mapped) catch unreachable;\n");
        self.dedent();
        try self.emitIndent();
        try emitConst(self,"}\n");
        try self.emitIndent();
        try emitFmtConst(self, "break :__m{d}_map_lambda __map_result;\n", .{map_lambda_id});
        self.dedent();
        try self.emitIndent();
        try emitConst(self,"})");
        return;
    }

    // Fallback: Generate runtime map using anytype
    // For unknown functions, we store the iterable first, then infer from first element
    // Use iterSlice to handle all iterable types (ArrayList, PyValue, slice, etc.)
    const map_fallback_id = self.nextNameId();
    try emitFmtConst(self, "(__m{d}_map: {{\n", .{map_fallback_id});
    self.indent();
    try self.emitIndent();
    try emitConst(self,"const __map_iterable = ");
    try self.genExpr(iterable);
    try emitConst(self,";\n");
    try self.emitIndent();
    // Use iterSlice for universal iterable handling (ArrayList, PyValue, slice, etc.)
    try emitConst(self,"const __map_slice = runtime.iterSlice(__map_iterable);\n");
    try self.emitIndent();
    try emitConst(self,"const __map_func = ");
    try self.genExpr(func);
    try emitConst(self,";\n");
    try self.emitIndent();
    try emitConst(self,"var __map_result = std.ArrayListUnmanaged(@TypeOf(__map_func(__map_slice[0]))){};\n");
    try self.emitIndent();
    try emitConst(self,"for (__map_slice) |__map_item| {\n");
    self.indent();
    try self.emitIndent();
    try emitConst(self,"const __mapped = __map_func(__map_item);\n");
    try self.emitIndent();
    try emitConst(self,"__map_result.append(__global_allocator, __mapped) catch unreachable;\n");
    self.dedent();
    try self.emitIndent();
    try emitConst(self,"}\n");
    try self.emitIndent();
    try emitFmtConst(self, "break :__m{d}_map __map_result;\n", .{map_fallback_id});
    self.dedent();
    try self.emitIndent();
    try emitConst(self,"})");
}

/// Generate code for filter(func, iterable)
/// Falls back to bytecode VM for dynamic execution (lambdas, complex expressions)
pub fn genFilter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        return error.UnsupportedSyntax;
    }

    // Use AST printer to convert filter arguments to Python source
    // This handles lambdas, attribute access, and all complex expressions
    const ast_printer = @import("../ast_printer.zig");
    var printer = ast_printer.AstPrinter.init(self.allocator);
    defer printer.deinit();

    const func_source = printer.print(args[0]) catch {
        // Fallback to error if AST printing fails
        return error.UnsupportedSyntax;
    };
    defer self.allocator.free(func_source);

    // Reset printer for second arg
    printer.output.clearRetainingCapacity();
    const iter_source = printer.print(args[1]) catch {
        return error.UnsupportedSyntax;
    };
    defer self.allocator.free(iter_source);

    // Build full filter() source string and emit VM fallback
    var source_buf = std.ArrayList(u8){};
    defer source_buf.deinit(self.allocator);
    try source_buf.appendSlice(self.allocator, "list(filter(");
    try source_buf.appendSlice(self.allocator, func_source);
    try source_buf.appendSlice(self.allocator, ", ");
    try source_buf.appendSlice(self.allocator, iter_source);
    try source_buf.appendSlice(self.allocator, "))");

    const core = @import("../main/core.zig");
    try core.emitVMFallback(self, source_buf.items);
}

/// Generate code for iter(iterable)
/// Returns a stateful iterator over the iterable
pub fn genIter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) {
        // iter() requires at least one argument
        return error.UnsupportedSyntax;
    }

    // Infer the type of the iterable to choose the right iterator
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    // For strings, create a stateful StringIterator
    if (string_traits.isString(arg_type)) {
        try emitConst(self,"runtime.builtins.strIterator(");
        try self.genExpr(args[0]);
        try emitConst(self,")");
        return;
    }

    // For tuples/arrays/slices, create a proper SequenceIterator
    if (container_traits.isTuple(arg_type) or container_traits.isList(arg_type)) {
        // Check if this is an ArrayList variable (needs .items accessor)
        const is_arraylist = if (args[0] == .name)
            self.isArrayListVar(args[0].name.id)
        else
            false;

        if (is_arraylist) {
            // ArrayList variable: use .items to get slice
            try emitConst(self,"runtime.iterators.iter(i64, ");
            try self.genExpr(args[0]);
            try emitConst(self,".items)");
        } else {
            // Use container_dispatch helper to reduce monomorphization
            try emitConst(self,"runtime.iterators.iter(i64, runtime.container_dispatch.toIterSlice(@TypeOf(");
            try self.genExpr(args[0]);
            try emitConst(self,"), ");
            try self.genExpr(args[0]);
            try emitConst(self,"))");
        }
        return;
    }

    // Check if argument is a call to range() - returns *PyObject which is a PyList
    if (args[0] == .call) {
        const call = args[0].call;
        if (call.func.* == .name) {
            const func_name = call.func.name.id;
            if (std.mem.eql(u8, func_name, "range")) {
                // iter(range(...)) - range returns *PyObject (PyList)
                // Wrap in PyValue.from to match __iter__ return type
                try emitConst(self,"runtime.PyValue.from(");
                try self.genExpr(args[0]);
                try emitConst(self,")");
                return;
            }
        }
    }

    // For unknown types, use container_dispatch helper to reduce monomorphization
    // Replaces inline @typeInfo/@hasField checks with centralized helper
    try emitConst(self,"runtime.container_dispatch.toIterSlice(@TypeOf(");
    try self.genExpr(args[0]);
    try emitConst(self,"), ");
    try self.genExpr(args[0]);
    try emitConst(self,")");
}

/// Generate code for next(iterator, [default])
/// Returns the next item from the iterator
pub fn genNext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) {
        // next() requires at least one argument
        return error.UnsupportedSyntax;
    }

    // For custom iterator objects with __next__ method
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;
    if (type_traits.isClassInstance(arg_type)) {
        try self.genExpr(args[0]);
        try emitConst(self,".__next__()");
        return;
    }

    // For list_iterator (SequenceIterator), call .next() directly
    const is_list_iterator = switch (arg_type) {
        .list_iterator => true,
        else => false,
    };
    if (is_list_iterator) {
        try emitConst(self,"(");
        try self.genExpr(args[0]);
        try emitConst(self,".next() catch |err| switch (err) { error.StopIteration => @panic(\"StopIteration\") })");
        return;
    }

    // For StringIterator and other stateful iterators, pass pointer for mutation
    // The runtime.builtins.next() returns an error union, wrap with try/catch
    // Use catch to convert StopIteration/TypeError to panic (matches Python semantics)
    try emitConst(self,"(runtime.builtins.next(&");
    try self.genExpr(args[0]);
    try emitConst(self,") catch |err| switch (err) { error.StopIteration => @panic(\"StopIteration\"), error.TypeError => @panic(\"TypeError: object is not an iterator\") })");
}

// Built-in functions implementation status:
// ✅ Implemented: sum, all, any, sorted, reversed, iter, next
// ❌ Not supported (need function pointers): map, filter
// ❌ Not supported (need for-loop integration): enumerate, zip
//
// Future improvements:
// - Add enumerate/zip support in for-loop codegen (statements.zig)
// - Consider comptime function pointer support for map/filter
