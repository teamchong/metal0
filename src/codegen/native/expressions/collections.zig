/// Collection literal code generation
/// Handles list and dict literal expressions
const std = @import("std");
const ast = @import("../../../ast.zig");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const expressions = @import("../expressions.zig");
const genExpr = expressions.genExpr;

/// Check if a node is a compile-time constant (can use comptime)
fn isComptimeConstant(node: ast.Node) bool {
    return switch (node) {
        .constant => true,
        .unaryop => |u| isComptimeConstant(u.operand.*),
        .binop => |b| isComptimeConstant(b.left.*) and isComptimeConstant(b.right.*),
        else => false,
    };
}

/// Check if a list contains only literal values (candidates for array optimization)
fn isConstantList(list: ast.Node.List) bool {
    if (list.elts.len == 0) return false; // Empty lists stay dynamic

    for (list.elts) |elem| {
        // Check if element is a literal constant
        const is_literal = switch (elem) {
            .constant => true,
            else => false,
        };
        if (!is_literal) return false;
    }

    return true;
}

/// Check if all elements in a list have the same type (homogeneous)
fn allSameType(elements: []ast.Node) bool {
    if (elements.len == 0) return true;

    // Get type tag of first element
    const first_const = switch (elements[0]) {
        .constant => |c| c,
        else => return false,
    };

    const first_type_tag = @as(std.meta.Tag(@TypeOf(first_const.value)), first_const.value);

    // Check all other elements match
    for (elements[1..]) |elem| {
        const elem_const = switch (elem) {
            .constant => |c| c,
            else => return false,
        };

        const elem_type_tag = @as(std.meta.Tag(@TypeOf(elem_const.value)), elem_const.value);
        if (elem_type_tag != first_type_tag) return false;
    }

    return true;
}

/// Generate fixed-size array literal for constant, homogeneous lists
fn genArrayLiteral(self: *NativeCodegen, list: ast.Node.List) CodegenError!void {
    // Determine element type from first element
    const elem_type_str = switch (list.elts[0].constant.value) {
        .int => "i64",
        .float => "f64",
        .string => "[]const u8",
        .bool => "bool",
    };

    // Emit array literal: [_]T{elem1, elem2, ...}
    try self.output.appendSlice(self.allocator, "[_]");
    try self.output.appendSlice(self.allocator, elem_type_str);
    try self.output.appendSlice(self.allocator, "{");

    for (list.elts, 0..) |elem, i| {
        if (i > 0) try self.output.appendSlice(self.allocator, ", ");

        // Emit element value - use genExpr for proper formatting
        try genExpr(self, elem);
    }

    try self.output.appendSlice(self.allocator, "}");
}

/// Generate list literal as ArrayList (Python lists are always mutable)
pub fn genList(self: *NativeCodegen, list: ast.Node.List) CodegenError!void {
    // Empty lists
    if (list.elts.len == 0) {
        try self.output.appendSlice(self.allocator, "std.ArrayList(i64){}");
        return;
    }

    // Check if we can optimize to fixed-size array (constant + homogeneous)
    if (isConstantList(list) and allSameType(list.elts)) {
        return try genArrayLiteral(self, list);
    }

    // Check if all elements are compile-time constants → use comptime optimization!
    var all_comptime = true;
    for (list.elts) |elem| {
        if (!isComptimeConstant(elem)) {
            all_comptime = false;
            break;
        }
    }

    // COMPTIME PATH: All elements known at compile time
    if (all_comptime) {
        // Generate unique block label
        const label = try std.fmt.allocPrint(self.allocator, "list_{d}", .{@intFromPtr(list.elts.ptr)});
        defer self.allocator.free(label);

        try self.output.appendSlice(self.allocator, label);
        try self.output.appendSlice(self.allocator, ": {\n");
        self.indent();
        try self.emitIndent();

        // Generate comptime tuple
        try self.output.appendSlice(self.allocator, "const _values = .{ ");
        for (list.elts, 0..) |elem, i| {
            if (i > 0) try self.output.appendSlice(self.allocator, ", ");
            try genExpr(self, elem);
        }
        try self.output.appendSlice(self.allocator, " };\n");

        // Let Zig's comptime infer the type and generate optimal code
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "const T = comptime runtime.InferListType(@TypeOf(_values));\n");

        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "var _list = std.ArrayList(T){};\n");

        // Inline loop - unrolled at Zig compile time!
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "inline for (_values) |val| {\n");
        self.indent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "const cast_val = if (@TypeOf(val) != T) cast_blk: {\n");
        self.indent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "if (T == f64 and (@TypeOf(val) == i64 or @TypeOf(val) == comptime_int)) {\n");
        self.indent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "break :cast_blk @as(f64, @floatFromInt(val));\n");
        self.dedent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "}\n");
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "if (T == f64 and @TypeOf(val) == comptime_float) {\n");
        self.indent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "break :cast_blk @as(f64, val);\n");
        self.dedent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "}\n");
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "break :cast_blk val;\n");
        self.dedent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "} else val;\n");
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "try _list.append(allocator, cast_val);\n");
        self.dedent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "}\n");

        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "break :");
        try self.output.appendSlice(self.allocator, label);
        try self.output.appendSlice(self.allocator, " _list;\n");
        self.dedent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "}");
        return;
    }

    // RUNTIME PATH: Dynamic list (fallback to current widening approach)
    const runtime_label = try std.fmt.allocPrint(self.allocator, "list_{d}", .{@intFromPtr(list.elts.ptr)});
    defer self.allocator.free(runtime_label);

    try self.output.appendSlice(self.allocator, runtime_label);
    try self.output.appendSlice(self.allocator, ": {\n");
    self.indent();
    try self.emitIndent();

    // Infer element type using type widening
    var elem_type = try self.type_inferrer.inferExpr(list.elts[0]);

    // Widen type to accommodate all elements
    for (list.elts[1..]) |elem| {
        const this_type = try self.type_inferrer.inferExpr(elem);
        elem_type = elem_type.widen(this_type);
    }

    try self.output.appendSlice(self.allocator, "var _list = std.ArrayList(");
    try elem_type.toZigType(self.allocator, &self.output);
    try self.output.appendSlice(self.allocator, "){};\n");

    // Append each element (with type coercion if needed)
    for (list.elts) |elem| {
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "try _list.append(allocator, ");

        // Check if we need to cast this element
        const this_type = try self.type_inferrer.inferExpr(elem);
        const needs_cast = (elem_type == .float and this_type == .int);

        if (needs_cast) {
            try self.output.appendSlice(self.allocator, "@as(f64, @floatFromInt(");
            try genExpr(self, elem);
            try self.output.appendSlice(self.allocator, "))");
        } else {
            try genExpr(self, elem);
        }

        try self.output.appendSlice(self.allocator, ");\n");
    }

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "break :");
    try self.output.appendSlice(self.allocator, runtime_label);
    try self.output.appendSlice(self.allocator, " _list;\n");
    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate dict literal as StringHashMap
pub fn genDict(self: *NativeCodegen, dict: ast.Node.Dict) CodegenError!void {
    // Empty dict
    if (dict.keys.len == 0) {
        try self.output.appendSlice(self.allocator, "std.StringHashMap(i64).init(allocator)");
        return;
    }

    // Check if all keys and values are compile-time constants
    var all_comptime = true;
    for (dict.keys) |key| {
        if (!isComptimeConstant(key)) {
            all_comptime = false;
            break;
        }
    }
    if (all_comptime) {
        for (dict.values) |value| {
            if (!isComptimeConstant(value)) {
                all_comptime = false;
                break;
            }
        }
    }

    // Check if values have compatible types (no mixed types that need runtime conversion)
    // Only int/float widening is allowed for comptime path
    if (all_comptime and dict.values.len > 0) {
        const first_type = try self.type_inferrer.inferExpr(dict.values[0]);
        for (dict.values[1..]) |value| {
            const this_type = try self.type_inferrer.inferExpr(value);
            // Check if types are incompatible (e.g., string + int)
            const tags_match = @as(std.meta.Tag(@TypeOf(first_type)), first_type) == @as(std.meta.Tag(@TypeOf(this_type)), this_type);
            const is_int_float_mix = (first_type == .int and this_type == .float) or (first_type == .float and this_type == .int);
            if (!tags_match and !is_int_float_mix) {
                // Mixed types that need runtime conversion - fall back to runtime path
                all_comptime = false;
                break;
            }
        }
    }

    // COMPTIME PATH: All entries known at compile time AND have compatible types
    if (all_comptime) {
        const label = try std.fmt.allocPrint(self.allocator, "dict_{d}", .{@intFromPtr(dict.keys.ptr)});
        defer self.allocator.free(label);

        try self.output.appendSlice(self.allocator, label);
        try self.output.appendSlice(self.allocator, ": {\n");
        self.indent();
        try self.emitIndent();

        // Generate comptime tuple of key-value pairs
        try self.output.appendSlice(self.allocator, "const _kvs = .{\n");
        self.indent();
        for (dict.keys, dict.values) |key, value| {
            try self.emitIndent();
            try self.output.appendSlice(self.allocator, ".{ ");
            try genExpr(self, key);
            try self.output.appendSlice(self.allocator, ", ");
            try genExpr(self, value);
            try self.output.appendSlice(self.allocator, " },\n");
        }
        self.dedent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "};\n");

        // Infer value type at comptime
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "const V = comptime runtime.InferDictValueType(@TypeOf(_kvs));\n");

        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "var _dict = std.StringHashMap(V).init(allocator);\n");

        // Inline loop - unrolled at compile time
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "inline for (_kvs) |kv| {\n");
        self.indent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "const cast_val = if (@TypeOf(kv[1]) != V) cast_blk: {\n");
        self.indent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "if (V == f64 and (@TypeOf(kv[1]) == i64 or @TypeOf(kv[1]) == comptime_int)) {\n");
        self.indent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "break :cast_blk @as(f64, @floatFromInt(kv[1]));\n");
        self.dedent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "}\n");
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "if (V == f64 and @TypeOf(kv[1]) == comptime_float) {\n");
        self.indent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "break :cast_blk @as(f64, kv[1]);\n");
        self.dedent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "}\n");
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "if (V == []const u8) {\n");
        self.indent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "const kv_type_info = @typeInfo(@TypeOf(kv[1]));\n");
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "if (kv_type_info == .pointer and kv_type_info.pointer.size == .one) {\n");
        self.indent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "const child = @typeInfo(kv_type_info.pointer.child);\n");
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "if (child == .array and child.array.child == u8) {\n");
        self.indent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "break :cast_blk @as([]const u8, kv[1]);\n");
        self.dedent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "}\n");
        self.dedent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "}\n");
        self.dedent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "}\n");
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "break :cast_blk kv[1];\n");
        self.dedent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "} else kv[1];\n");
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "try _dict.put(kv[0], cast_val);\n");
        self.dedent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "}\n");

        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "break :");
        try self.output.appendSlice(self.allocator, label);
        try self.output.appendSlice(self.allocator, " _dict;\n");
        self.dedent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "}");
        return;
    }

    // RUNTIME PATH: Dynamic dict (fallback to current approach)
    // Infer value type - check if all values have same type
    var val_type: @import("../../../analysis/native_types.zig").NativeType = .unknown;
    if (dict.values.len > 0) {
        val_type = try self.type_inferrer.inferExpr(dict.values[0]);

        // Check if all values have consistent type
        var all_same = true;
        for (dict.values[1..]) |value| {
            const this_type = try self.type_inferrer.inferExpr(value);
            // Simple type equality check
            if (@as(std.meta.Tag(@TypeOf(val_type)), val_type) != @as(std.meta.Tag(@TypeOf(this_type)), this_type)) {
                all_same = false;
                break;
            }
        }

        // If mixed types, convert all to strings (Python's str())
        if (!all_same) {
            val_type = .{ .string = .runtime };
        }
    }

    // Generate: cast_blk: {
    //   var map = std.StringHashMap(T).init(allocator);
    //   try map.put("key", value);
    //   break :blk map;
    // }

    try self.output.appendSlice(self.allocator, "blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "var map = std.StringHashMap(");
    try val_type.toZigType(self.allocator, &self.output);
    try self.output.appendSlice(self.allocator, ").init(allocator);\n");

    // Track if we need to convert values to strings
    const need_str_conversion = val_type == .string;

    // Check if we have mixed types (need memory management)
    var has_mixed_types = false;
    if (need_str_conversion and dict.values.len > 0) {
        const first_type = try self.type_inferrer.inferExpr(dict.values[0]);
        for (dict.values[1..]) |value| {
            const this_type = try self.type_inferrer.inferExpr(value);
            if (@as(std.meta.Tag(@TypeOf(first_type)), first_type) != @as(std.meta.Tag(@TypeOf(this_type)), this_type)) {
                has_mixed_types = true;
                break;
            }
        }
    }

    // Add all key-value pairs
    for (dict.keys, dict.values) |key, value| {
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "try map.put(");
        try genExpr(self, key);
        try self.output.appendSlice(self.allocator, ", ");

        // If dict values are string type and this value isn't string, convert it
        if (need_str_conversion) {
            const value_type = try self.type_inferrer.inferExpr(value);
            if (value_type != .string) {
                // Convert to string using std.fmt.allocPrint
                try self.output.appendSlice(self.allocator, "try std.fmt.allocPrint(allocator, ");
                switch (value_type) {
                    .int => try self.output.appendSlice(self.allocator, "\"{d}\""),
                    .float => try self.output.appendSlice(self.allocator, "\"{d}\""),
                    .bool => try self.output.appendSlice(self.allocator, "\"{any}\""),
                    else => try self.output.appendSlice(self.allocator, "\"{any}\""),
                }
                try self.output.appendSlice(self.allocator, ", .{");
                try genExpr(self, value);
                try self.output.appendSlice(self.allocator, "})");
            } else if (has_mixed_types) {
                // For mixed-type dicts, duplicate ALL strings so we can free uniformly
                try self.output.appendSlice(self.allocator, "try allocator.dupe(u8, ");
                try genExpr(self, value);
                try self.output.appendSlice(self.allocator, ")");
            } else {
                try genExpr(self, value);
            }
        } else {
            try genExpr(self, value);
        }

        try self.output.appendSlice(self.allocator, ");\n");
    }

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "break :blk map;\n");
    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}");
}
