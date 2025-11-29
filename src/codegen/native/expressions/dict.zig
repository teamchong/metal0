/// Dict literal code generation
/// Handles dict literal expressions with comptime and runtime paths
const std = @import("std");
const ast = @import("ast");
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

    // Empty dict - use anyopaque for unknown value type (consistent with type inference)
    if (dict.keys.len == 0) {
        try self.emit("hashmap_helper.StringHashMap(*const anyopaque).init(");
        try self.emit(alloc_name);
        try self.emit(")");
        return;
    }

    // Check if all keys and values are compile-time constants
    // Dict unpacking (**other) is never comptime
    var all_comptime = true;
    for (dict.keys) |key| {
        // None key signals dict unpacking - not comptime
        if (key == .constant and key.constant.value == .none) {
            all_comptime = false;
            break;
        }
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

    // Infer key type from first key
    const key_type = try self.type_inferrer.inferExpr(dict.keys[0]);
    const uses_int_keys = key_type == .int;

    try self.emit(label);
    try self.emit(": {\n");
    self.indent();
    try self.emitIndent();

    // Generate comptime tuple of key-value pairs
    try self.emit("const _kvs = .{\n");
    self.indent();
    for (dict.keys, dict.values) |key, value| {
        try self.emitIndent();
        try self.emit(".{ ");
        try genExpr(self, key);
        try self.emit(", ");
        try genExpr(self, value);
        try self.emit(" },\n");
    }
    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");

    // Infer value type at comptime
    try self.emitIndent();
    try self.emit("const V = comptime runtime.InferDictValueType(@TypeOf(_kvs));\n");

    try self.emitIndent();
    if (uses_int_keys) {
        // Integer keys - use AutoHashMap with i64 key type
        try self.emit("var _dict = std.AutoHashMap(i64, V).init(");
    } else {
        // String keys - use StringHashMap
        try self.emit("var _dict = hashmap_helper.StringHashMap(V).init(");
    }
    try self.emit(alloc_name);
    try self.emit(");\n");

    // Inline loop - unrolled at compile time
    try self.emitIndent();
    try self.emit("inline for (_kvs) |kv| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const cast_val = if (@TypeOf(kv[1]) != V) cast_blk: {\n");
    self.indent();

    // Int to float cast
    try self.emitIndent();
    try self.emit("if (V == f64 and (@TypeOf(kv[1]) == i64 or @TypeOf(kv[1]) == comptime_int)) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("break :cast_blk @as(f64, @floatFromInt(kv[1]));\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");

    // Comptime float cast
    try self.emitIndent();
    try self.emit("if (V == f64 and @TypeOf(kv[1]) == comptime_float) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("break :cast_blk @as(f64, kv[1]);\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");

    // String array to slice cast
    try self.emitIndent();
    try self.emit("if (V == []const u8) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const kv_type_info = @typeInfo(@TypeOf(kv[1]));\n");
    try self.emitIndent();
    try self.emit("if (kv_type_info == .pointer and kv_type_info.pointer.size == .one) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const child = @typeInfo(kv_type_info.pointer.child);\n");
    try self.emitIndent();
    try self.emit("if (child == .array and child.array.child == u8) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("break :cast_blk @as([]const u8, kv[1]);\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");

    // Default fallback
    try self.emitIndent();
    try self.emit("break :cast_blk kv[1];\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("} else kv[1];\n");
    try self.emitIndent();
    if (uses_int_keys) {
        // Cast comptime_int key to i64 for AutoHashMap
        try self.emit("try _dict.put(@as(i64, kv[0]), cast_val);\n");
    } else {
        try self.emit("try _dict.put(kv[0], cast_val);\n");
    }
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.emit("break :");
    try self.emit(label);
    try self.emit(" _dict;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Helper to get value type from an entry (accounting for dict unpacking)
fn getEntryValueType(self: *NativeCodegen, key: ast.Node, value: ast.Node) CodegenError!@import("../../../analysis/native_types.zig").NativeType {
    // Dict unpacking: None key signals **other_dict
    if (key == .constant and key.constant.value == .none) {
        const dict_type = try self.type_inferrer.inferExpr(value);
        if (dict_type == .dict) {
            return dict_type.dict.value.*;
        }
        return .unknown;
    }
    return try self.type_inferrer.inferExpr(value);
}

/// Generate runtime dict literal (fallback path)
fn genDictRuntime(self: *NativeCodegen, dict: ast.Node.Dict, alloc_name: []const u8) CodegenError!void {
    // Infer key type from first key (for non-unpacking entries)
    var uses_int_keys = false;
    for (dict.keys) |key| {
        if (key != .constant or key.constant.value != .none) {
            const key_type = try self.type_inferrer.inferExpr(key);
            uses_int_keys = key_type == .int;
            break;
        }
    }

    // Infer value type - check if all values have same type
    var val_type: @import("../../../analysis/native_types.zig").NativeType = .unknown;
    if (dict.values.len > 0) {
        val_type = try getEntryValueType(self, dict.keys[0], dict.values[0]);

        // Check if all values have consistent type
        var all_same = true;
        for (dict.keys[1..], dict.values[1..]) |key, value| {
            const this_type = try getEntryValueType(self, key, value);
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

    try self.emit("blk: {\n");
    self.indent();
    try self.emitIndent();
    if (uses_int_keys) {
        try self.emit("var map = std.AutoHashMap(i64, ");
    } else {
        try self.emit("var map = hashmap_helper.StringHashMap(");
    }
    try val_type.toZigType(self.allocator, &self.output);
    try self.emit(").init(");
    try self.emit(alloc_name);
    try self.emit(");\n");

    // Track if we need to convert values to strings
    const need_str_conversion = val_type == .string;

    // Check if we have mixed types (need memory management)
    var has_mixed_types = false;
    if (need_str_conversion and dict.values.len > 0) {
        const first_type = try getEntryValueType(self, dict.keys[0], dict.values[0]);
        for (dict.keys[1..], dict.values[1..]) |key, value| {
            const this_type = try getEntryValueType(self, key, value);
            if (@as(std.meta.Tag(@TypeOf(first_type)), first_type) != @as(std.meta.Tag(@TypeOf(this_type)), this_type)) {
                has_mixed_types = true;
                break;
            }
        }
    }

    // Add all key-value pairs
    for (dict.keys, dict.values) |key, value| {
        // Check for dict unpacking: {**other_dict} represented as None key
        if (key == .constant and key.constant.value == .none) {
            // Dict unpacking: merge entries from another dict
            try self.emitIndent();
            try self.emit("{\n");
            self.indent();
            try self.emitIndent();
            try self.emit("var iter = (");
            try genExpr(self, value);
            try self.emit(").iterator();\n");
            try self.emitIndent();
            try self.emit("while (iter.next()) |entry| {\n");
            self.indent();
            try self.emitIndent();
            try self.emit("try map.put(entry.key_ptr.*, entry.value_ptr.*);\n");
            self.dedent();
            try self.emitIndent();
            try self.emit("}\n");
            self.dedent();
            try self.emitIndent();
            try self.emit("}\n");
            continue;
        }

        try self.emitIndent();
        try self.emit("try map.put(");
        try genExpr(self, key);
        try self.emit(", ");

        // If dict values are string type and this value isn't string, convert it
        if (need_str_conversion) {
            const value_type = try self.type_inferrer.inferExpr(value);
            if (value_type != .string) {
                try genValueToString(self, value, value_type, alloc_name);
            } else if (has_mixed_types) {
                // For mixed-type dicts, duplicate ALL strings so we can free uniformly
                try self.emit("try ");
                try self.emit(alloc_name);
                try self.emit(".dupe(u8, ");
                try genExpr(self, value);
                try self.emit(")");
            } else {
                try genExpr(self, value);
            }
        } else {
            try genExpr(self, value);
        }

        try self.emit(");\n");
    }

    try self.emitIndent();
    try self.emit("break :blk map;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
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
        try self.emit("try ");
        try self.emit(alloc_name);
        try self.emit(".dupe(u8, if (");
        try genExpr(self, value);
        try self.emit(") \"True\" else \"False\")");
    } else if (value_type == .none) {
        // None: just use literal "None"
        try self.emit("try ");
        try self.emit(alloc_name);
        try self.emit(".dupe(u8, \"None\")");
    } else {
        try self.emit("try std.fmt.allocPrint(");
        try self.emit(alloc_name);
        try self.emit(", ");
        switch (value_type) {
            .int => try self.emit("\"{d}\""),
            .float => try self.emit("\"{d}\""),
            else => try self.emit("\"{any}\""),
        }
        try self.emit(", .{");
        try genExpr(self, value);
        try self.emit("})");
    }
}
