/// Dict literal code generation
/// Handles dict literal expressions with comptime and runtime paths
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const expressions = @import("../expressions.zig");
const genExpr = expressions.genExpr;
const mutation_analyzer = @import("../../../analysis/native_types/mutation_analyzer.zig");

/// Key type inference result
const KeyTypeResult = enum { int, string, unknown };

/// Infer key type from statements that assign to a dict variable
fn inferKeyTypeFromStmts(stmts: []const ast.Node, var_name: []const u8) KeyTypeResult {
    for (stmts) |stmt| {
        // Look for assignments like d[key] = value
        if (stmt == .assign) {
            for (stmt.assign.targets) |target| {
                if (target == .subscript) {
                    const subscript = target.subscript;
                    // Check if subscript base is our variable
                    if (subscript.value.* == .name and std.mem.eql(u8, subscript.value.name.id, var_name)) {
                        // Check key type - slice is a union, check if it's index type
                        if (subscript.slice == .index) {
                            const slice = subscript.slice.index;
                            if (slice.* == .constant) {
                                switch (slice.constant.value) {
                                    .int => return .int,
                                    .string => return .string,
                                    else => {},
                                }
                            } else if (slice.* == .name) {
                                // Variable - could be from range iterator (int)
                                return .int;
                            } else if (slice.* == .binop) {
                                // Binary op like i+1 - likely int
                                return .int;
                            }
                        }
                    }
                }
            }
        } else if (stmt == .for_stmt) {
            // Check for-loop body for dict assignments
            const result = inferKeyTypeFromStmts(stmt.for_stmt.body, var_name);
            if (result != .unknown) return result;
        } else if (stmt == .with_stmt) {
            // Check with-block body
            const result = inferKeyTypeFromStmts(stmt.with_stmt.body, var_name);
            if (result != .unknown) return result;
        }
    }
    return .unknown;
}

/// Look up method body in current class and infer key type
fn inferKeyTypeFromContext(self: *NativeCodegen, var_name: []const u8) KeyTypeResult {
    // Use current_function_body directly if available (set by class method generator)
    if (self.current_function_body) |body| {
        return inferKeyTypeFromStmts(body, var_name);
    }
    return .unknown;
}

/// Check if a node is a compile-time constant (can use comptime)
pub fn isComptimeConstant(node: ast.Node) bool {
    return switch (node) {
        .constant => true,
        .unaryop => |u| isComptimeConstant(u.operand.*),
        .binop => |b| isComptimeConstant(b.left.*) and isComptimeConstant(b.right.*),
        .tuple => |t| {
            // Tuple is comptime if all elements are comptime
            for (t.elts) |elt| {
                if (!isComptimeConstant(elt)) return false;
            }
            return true;
        },
        .list => |l| {
            // List is comptime if all elements are comptime
            for (l.elts) |elt| {
                if (!isComptimeConstant(elt)) return false;
            }
            return true;
        },
        else => false,
    };
}

/// Generate dict literal as StringHashMap
pub fn genDict(self: *NativeCodegen, dict: ast.Node.Dict) CodegenError!void {
    // Determine which allocator to use based on scope
    // In main() (scope 0): use 'allocator' (local variable)
    // In functions (scope > 0): use '__global_allocator' (module-level)
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";

    // Empty dict - check if mutations will use int keys, string keys, or mixed
    if (dict.keys.len == 0) {
        // Check mutations for this dict variable
        var has_int_keys = false;
        var has_str_keys = false;
        if (self.current_assign_target) |var_name| {
            if (self.mutation_info) |mutations| {
                has_int_keys = mutation_analyzer.hasDictIntKeyMutation(mutations.*, var_name);
                has_str_keys = mutation_analyzer.hasDictStrKeyMutation(mutations.*, var_name);
            } else {
                // No mutation info (in function/method context) - try lookahead
                const inferred = inferKeyTypeFromContext(self, var_name);
                has_int_keys = inferred == .int;
                has_str_keys = inferred == .string;
            }
        }

        if (has_int_keys and has_str_keys) {
            // Mixed key types - use StringHashMap with runtime.PyValue values
            // Convert all keys to strings at runtime
            try self.emit("hashmap_helper.StringHashMap(runtime.PyValue).init(");
        } else if (has_int_keys) {
            // Use AutoHashMap for int keys
            // Also use i64 value type since d[i] = i typically has int value too
            try self.emit("std.AutoHashMap(i64, i64).init(");
        } else if (has_str_keys) {
            // String keys with mutations - use i64 value type for common pattern d['key'] = 1
            try self.emit("hashmap_helper.StringHashMap(i64).init(");
        } else {
            // Default to StringHashMap for unknown empty dicts
            // Use runtime.PyValue for maximum flexibility with heterogeneous values
            try self.emit("hashmap_helper.StringHashMap(runtime.PyValue).init(");
        }
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
    // Use Zig type strings to catch differences in nested types (e.g., tuple element types)
    if (all_comptime and dict.values.len > 0) {
        const first_type = try self.type_inferrer.inferExpr(dict.values[0]);
        var first_zig_type_buf = std.ArrayList(u8){};
        try first_type.toZigType(self.allocator, &first_zig_type_buf);
        for (dict.values[1..]) |value| {
            const this_type = try self.type_inferrer.inferExpr(value);
            var this_zig_type_buf = std.ArrayList(u8){};
            try this_type.toZigType(self.allocator, &this_zig_type_buf);
            // Full type string comparison catches nested type differences (e.g., tuple element types)
            if (!std.mem.eql(u8, first_zig_type_buf.items, this_zig_type_buf.items)) {
                // Types differ - fall back to runtime path (can't unify tuples with different element types)
                all_comptime = false;
                break;
            }
        }
    }

    // Also check for tuples with bigint elements - these can't use comptime path
    // because BigInt requires runtime allocation
    if (all_comptime and dict.values.len > 0) {
        for (dict.values) |value| {
            const val_type = try self.type_inferrer.inferExpr(value);
            if (val_type == .tuple) {
                for (val_type.tuple) |elem_type| {
                    if (elem_type == .bigint) {
                        all_comptime = false;
                        break;
                    }
                }
            }
            if (!all_comptime) break;
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
    var uses_float_keys = false;
    for (dict.keys) |key| {
        if (key != .constant or key.constant.value != .none) {
            const key_type = try self.type_inferrer.inferExpr(key);
            uses_int_keys = key_type == .int;
            uses_float_keys = key_type == .float;
            break;
        }
    }

    // Infer value type - check if all values have same type
    var val_type: @import("../../../analysis/native_types.zig").NativeType = .unknown;
    if (dict.values.len > 0) {
        val_type = try getEntryValueType(self, dict.keys[0], dict.values[0]);

        // Check if all values have consistent type using Zig type string comparison
        var all_same = true;
        var first_zig_type = std.ArrayList(u8){};
        try val_type.toZigType(self.allocator, &first_zig_type);
        for (dict.keys[1..], dict.values[1..]) |key, value| {
            const this_type = try getEntryValueType(self, key, value);
            var this_zig_type = std.ArrayList(u8){};
            try this_type.toZigType(self.allocator, &this_zig_type);
            // Compare full Zig type strings to catch nested type differences
            if (!std.mem.eql(u8, first_zig_type.items, this_zig_type.items)) {
                all_same = false;
                break;
            }
        }

        // If mixed types, use runtime.PyValue to allow heterogeneous values
        // This handles cases like fmtdict = {'': NATIVE, '<': STANDARD} where
        // NATIVE is StringHashMap(i64) and STANDARD is StringHashMap(tuple)
        if (!all_same) {
            val_type = .pyvalue;
        }
    }

    // Use unique label to avoid conflicts with nested dict literals
    const label_id = self.block_label_counter;
    self.block_label_counter += 1;
    try self.output.writer(self.allocator).print("dict_blk_{d}: {{\n", .{label_id});
    self.indent();
    try self.emitIndent();
    if (uses_int_keys) {
        try self.emit("var map = std.AutoHashMap(i64, ");
    } else if (uses_float_keys) {
        // Floats can't be hashed directly in Zig, use u64 bit representation
        try self.emit("var map = std.AutoHashMap(u64, ");
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
        if (uses_float_keys) {
            // Convert float key to bits for hashing
            try self.emit("@bitCast(");
            try genExpr(self, key);
            try self.emit(")");
        } else {
            try genExpr(self, key);
        }
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
        } else if (val_type == .pyvalue) {
            // PyValue: wrap the value with PyValue.fromAlloc()
            try self.emit("try runtime.PyValue.fromAlloc(");
            try self.emit(alloc_name);
            try self.emit(", ");
            try genExpr(self, value);
            try self.emit(")");
        } else {
            try genExpr(self, value);
        }

        try self.emit(");\n");
    }

    try self.emitIndent();
    // Use the label_id that was captured at the start of this function
    try self.output.writer(self.allocator).print("break :dict_blk_{d} map;\n", .{label_id});
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
