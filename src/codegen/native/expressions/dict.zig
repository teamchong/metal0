/// Dict literal code generation
/// Handles dict literal expressions with comptime and runtime paths
const std = @import("std");
const ast = @import("../../../ast.zig");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const expressions = @import("../expressions.zig");
const genExpr = expressions.genExpr;

/// Check if a node is a compile-time constant (can use comptime)
pub fn isComptimeConstant(node: ast.Node) bool {
    return switch (node) {
        .constant => true,
        .unaryop => |u| isComptimeConstant(u.operand.*),
        .binop => |b| isComptimeConstant(b.left.*) and isComptimeConstant(b.right.*),
        else => false,
    };
}

/// Generate dict literal as StringHashMap
pub fn genDict(self: *NativeCodegen, dict: ast.Node.Dict) CodegenError!void {
    // Determine which allocator to use based on scope
    // In main() (scope 0): use 'allocator' (local variable)
    // In functions (scope > 0): use '__global_allocator' (module-level)
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";

    // Empty dict
    if (dict.keys.len == 0) {
        try self.output.appendSlice(self.allocator, "hashmap_helper.StringHashMap(i64).init(");
        try self.output.appendSlice(self.allocator, alloc_name);
        try self.output.appendSlice(self.allocator, ")");
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
        try genDictComptime(self, dict, alloc_name);
        return;
    }

    // RUNTIME PATH: Dynamic dict (fallback to current approach)
    try genDictRuntime(self, dict, alloc_name);
}

/// Generate comptime-optimized dict literal
fn genDictComptime(self: *NativeCodegen, dict: ast.Node.Dict, alloc_name: []const u8) CodegenError!void {
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
    try self.output.appendSlice(self.allocator, "var _dict = hashmap_helper.StringHashMap(V).init(");
    try self.output.appendSlice(self.allocator, alloc_name);
    try self.output.appendSlice(self.allocator, ");\n");

    // Inline loop - unrolled at compile time
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "inline for (_kvs) |kv| {\n");
    self.indent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "const cast_val = if (@TypeOf(kv[1]) != V) cast_blk: {\n");
    self.indent();

    // Int to float cast
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "if (V == f64 and (@TypeOf(kv[1]) == i64 or @TypeOf(kv[1]) == comptime_int)) {\n");
    self.indent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "break :cast_blk @as(f64, @floatFromInt(kv[1]));\n");
    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}\n");

    // Comptime float cast
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "if (V == f64 and @TypeOf(kv[1]) == comptime_float) {\n");
    self.indent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "break :cast_blk @as(f64, kv[1]);\n");
    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}\n");

    // String array to slice cast
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

    // Default fallback
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
}

/// Generate runtime dict literal (fallback path)
fn genDictRuntime(self: *NativeCodegen, dict: ast.Node.Dict, alloc_name: []const u8) CodegenError!void {
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

    try self.output.appendSlice(self.allocator, "blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "var map = hashmap_helper.StringHashMap(");
    try val_type.toZigType(self.allocator, &self.output);
    try self.output.appendSlice(self.allocator, ").init(");
    try self.output.appendSlice(self.allocator, alloc_name);
    try self.output.appendSlice(self.allocator, ");\n");

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
                try genValueToString(self, value, value_type, alloc_name);
            } else if (has_mixed_types) {
                // For mixed-type dicts, duplicate ALL strings so we can free uniformly
                try self.output.appendSlice(self.allocator, "try ");
                try self.output.appendSlice(self.allocator, alloc_name);
                try self.output.appendSlice(self.allocator, ".dupe(u8, ");
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

/// Generate code to convert a value to string
fn genValueToString(
    self: *NativeCodegen,
    value: ast.Node,
    value_type: @import("../../../analysis/native_types.zig").NativeType,
    alloc_name: []const u8,
) CodegenError!void {
    if (value_type == .bool) {
        // Bool: use ternary for Python-style True/False
        try self.output.appendSlice(self.allocator, "try ");
        try self.output.appendSlice(self.allocator, alloc_name);
        try self.output.appendSlice(self.allocator, ".dupe(u8, if (");
        try genExpr(self, value);
        try self.output.appendSlice(self.allocator, ") \"True\" else \"False\")");
    } else if (value_type == .none) {
        // None: just use literal "None"
        try self.output.appendSlice(self.allocator, "try ");
        try self.output.appendSlice(self.allocator, alloc_name);
        try self.output.appendSlice(self.allocator, ".dupe(u8, \"None\")");
    } else {
        try self.output.appendSlice(self.allocator, "try std.fmt.allocPrint(");
        try self.output.appendSlice(self.allocator, alloc_name);
        try self.output.appendSlice(self.allocator, ", ");
        switch (value_type) {
            .int => try self.output.appendSlice(self.allocator, "\"{d}\""),
            .float => try self.output.appendSlice(self.allocator, "\"{d}\""),
            else => try self.output.appendSlice(self.allocator, "\"{any}\""),
        }
        try self.output.appendSlice(self.allocator, ", .{");
        try genExpr(self, value);
        try self.output.appendSlice(self.allocator, "})");
    }
}
