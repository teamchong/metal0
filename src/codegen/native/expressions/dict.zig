/// Dict literal code generation
/// Handles dict literal expressions with comptime and runtime paths
///
/// MIGRATION STATUS: Using ZigBuilder for structured code generation
/// - Uses captureExpr() to bridge AST expressions to ZigValue
/// - Emits using emitZigValue() for type-safe output
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const expressions = @import("../expressions.zig");
const genExpr = expressions.genExpr;
const mutation_analyzer = @import("../../../analysis/native_types/mutation_analyzer.zig");
const type_traits = @import("../../../analysis/traits/type_traits.zig");
const string_traits = @import("../../../analysis/traits/string_traits.zig");
const container_traits = @import("../../../analysis/traits/container_traits.zig");
const expr_emitter = @import("../expr_emitter.zig");
const builder_mod = @import("codegen.builder");
const ZigValue = builder_mod.ZigValue;

// MIGRATED TO ZIGBUILDER

// ============================================
// Dict operation helpers - auto-closing patterns
// ============================================

/// Emit hashmap_helper.StringHashMap(value_type).init(alloc)
/// MIGRATED TO BUILDER: uses emitMethodCallExpr
fn emitStringHashMapInit(self: *NativeCodegen, value_type: []const u8, alloc_name: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    const alloc = self.arena.allocator();
    const receiver_str = try std.fmt.allocPrint(alloc, "hashmap_helper.StringHashMap({s})", .{value_type});
    const receiver = ZigValue.raw(receiver_str);
    try b.emitMethodCallExpr(receiver, "init", &.{.{ .raw = alloc_name }});
    const result = try alloc.dupe(u8, b.getBodyAndClear());
    try self.emitZigValue(ZigValue.raw(result));
}

/// Emit std.AutoArrayHashMap(key_type, value_type).init(alloc)
/// MIGRATED TO BUILDER: uses emitMethodCallExpr
fn emitAutoArrayHashMapInit(self: *NativeCodegen, key_type: []const u8, value_type: []const u8, alloc_name: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    const alloc = self.arena.allocator();
    const receiver_str = try std.fmt.allocPrint(alloc, "std.AutoArrayHashMap({s}, {s})", .{ key_type, value_type });
    const receiver = ZigValue.raw(receiver_str);
    try b.emitMethodCallExpr(receiver, "init", &.{.{ .raw = alloc_name }});
    const result = try alloc.dupe(u8, b.getBodyAndClear());
    try self.emitZigValue(ZigValue.raw(result));
}

/// Emit runtime.PyValueHashMap(value_type).init(__global_allocator) (Zig 0.15 managed style)
/// Used for dicts with non-string keys (tuples, ints, bools, mixed types)
/// Note: ArrayHashMap in Zig 0.15 is managed and requires .init(allocator)
/// MIGRATED TO BUILDER: uses emitMethodCallExpr
fn emitPyValueHashMapInit(self: *NativeCodegen, value_type: []const u8) CodegenError!void {
    _ = value_type; // Value type is always PyValue for mixed key dicts
    const b = try self.getBuilder();
    const receiver = ZigValue.raw("runtime.PyValueHashMap(runtime.PyValue)");
    try b.emitMethodCallExpr(receiver, "init", &.{.allocator});
    const result = try self.arena.allocator().dupe(u8, b.getBodyAndClear());
    try self.emitZigValue(ZigValue.raw(result));
}

/// Emit try alloc.dupe(u8, str) for string duplication
/// MIGRATED TO BUILDER: uses emitMethodCallExpr with try wrapper
fn emitAllocDupe(self: *NativeCodegen, alloc_name: []const u8, str: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    const receiver = ZigValue.raw(alloc_name);
    try b.write("try ");
    try b.emitMethodCallExpr(receiver, "dupe", &.{
        .{ .raw = "u8" },
        .{ .raw = str },
    });
    const result = try self.arena.allocator().dupe(u8, b.getBodyAndClear());
    try self.emitZigValue(ZigValue.raw(result));
}

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
        .list => {
            // Lists are NOT comptime - they generate runtime ArrayList allocations
            // Even if elements are constants, the ArrayList creation is runtime
            return false;
        },
        else => false,
    };
}

/// Generate dict literal as StringHashMap
pub fn genDict(self: *NativeCodegen, dict: ast.Node.Dict) CodegenError!void {
    // Determine which allocator to use based on scope
    // In main() (scope 0): use 'allocator' (local variable)
    // In functions (scope > 0): use '__global_allocator' (module-level)
    const alloc_name = "__global_allocator";

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
            // Mixed key types - use PyValueHashMap for non-string keys
            try emitPyValueHashMapInit(self, "runtime.PyValue");
        } else if (has_int_keys) {
            // Use AutoArrayHashMap for int keys (has .keys() and .values() like Python)
            try emitAutoArrayHashMapInit(self, "i64", "i64", alloc_name);
        } else if (has_str_keys) {
            // String keys with mutations - use i64 value type for common pattern d['key'] = 1
            try emitStringHashMapInit(self, "i64", alloc_name);
        } else {
            // Default to PyValueHashMap for unknown empty dicts (may get non-string keys later)
            try emitPyValueHashMapInit(self, "runtime.PyValue");
        }
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
            if (container_traits.isTuple(val_type)) {
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

    // Infer key type from first key using getDictKeyType
    const key_type = try self.type_inferrer.inferExpr(dict.keys[0]);
    const key_classification = type_traits.getDictKeyType(key_type);

    const label = try self.emitInlineBlockStart("dict");
    try self.emit("\n");
    self.indent();
    try self.emitIndent();

    // Generate comptime tuple of key-value pairs
    // Track that we're inside a dict for proper nested list generation
    // Dict values should generate as ArrayList, not fixed arrays
    self.inside_list_depth += 1;
    defer self.inside_list_depth -= 1;

    try self.emit("const _kvs = .{\n");
    self.indent();
    for (dict.keys, dict.values) |key, value| {
        // Capture key and value expressions
        const key_operand = try self.captureExpr(key);
        const value_operand = try self.captureExpr(value);

        try self.emitIndent();
        try self.emit(".{ ");
        try self.emitZigValue(key_operand);
        try self.emit(", ");
        try self.emitZigValue(value_operand);
        try self.emit(" },\n");
    }
    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");

    // Infer value type at comptime, or use target type if context is set
    // Context is set when assigning to a variable with a widened dict type (e.g., dict(k, pyvalue))
    try self.emitIndent();
    if (self.target_dict_value_type) |target_type| {
        // Use widened type from assignment context
        try self.output.writer(self.allocator).print("const V = {s};\n", .{target_type});
    } else {
        // Infer from literal values
        try self.emit("const V = comptime runtime.InferDictValueType(@TypeOf(_kvs));\n");
    }

    // Use getDictKeyType to select correct HashMap type based on key type
    try self.emitIndent();
    switch (key_classification) {
        .int => {
            // Integer keys - use AutoArrayHashMap with i64 key type (has .keys() and .values())
            try self.emit("var _dict = std.AutoArrayHashMap(i64, V).init(");
            try self.emit(alloc_name);
            try self.emit(");\n");
        },
        .string => {
            // String keys - use StringHashMap
            try self.emit("var _dict = hashmap_helper.StringHashMap(V).init(");
            try self.emit(alloc_name);
            try self.emit(");\n");
        },
        .pyvalue => {
            // Unknown/mixed key types - use PyValueHashMap for non-string keys
            // PyValueHashMap uses managed ArrayHashMap (Zig 0.15) - requires .init(allocator)
            try self.emit("var _dict = runtime.PyValueHashMap(runtime.PyValue).init(");
            try self.emit(alloc_name);
            try self.emit(");\n");
        },
    }

    // Inline loop - unrolled at compile time
    try self.emitIndent();
    try self.emit("inline for (_kvs) |kv| {\n");
    self.indent();
    try self.emitIndent();
    // Generate unique label for cast block
    const id = self.nextNameId();
    const cast_label = try std.fmt.allocPrint(self.arena.allocator(), "__m{d}_cast", .{id});
    try self.emit("const cast_val = if (@TypeOf(kv[1]) != V) ");
    try self.emitFmt("({s}: {{\n", .{cast_label});
    self.indent();

    // Int to float cast
    try self.emitIndent();
    try self.emit("if (V == f64 and (@TypeOf(kv[1]) == i64 or @TypeOf(kv[1]) == comptime_int)) {\n");
    self.indent();
    try self.emitIndent();
    try self.emitFmt("break :{s} @as(f64, @floatFromInt(kv[1]));\n", .{cast_label});
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");

    // Comptime float cast
    try self.emitIndent();
    try self.emit("if (V == f64 and @TypeOf(kv[1]) == comptime_float) {\n");
    self.indent();
    try self.emitIndent();
    try self.emitFmt("break :{s} @as(f64, kv[1]);\n", .{cast_label});
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
    try self.emitFmt("break :{s} @as([]const u8, kv[1]);\n", .{cast_label});
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");

    // Null to ?void cast (for dict values that are all None)
    try self.emitIndent();
    try self.emit("if (V == ?void and @TypeOf(kv[1]) == @TypeOf(null)) {\n");
    self.indent();
    try self.emitIndent();
    try self.emitFmt("break :{s} null;\n", .{cast_label});
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");

    // PyValue conversion (for widened dict types)
    try self.emitIndent();
    try self.emit("if (V == runtime.PyValue) {\n");
    self.indent();
    try self.emitIndent();
    try self.emitFmt("break :{s} try runtime.toPyValue(__global_allocator, kv[1]);\n", .{cast_label});
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");

    // Default fallback
    try self.emitIndent();
    try self.emitFmt("break :{s} kv[1];\n", .{cast_label});
    self.dedent();
    try self.emitIndent();
    try self.emit("}) else kv[1];\n");
    try self.emitIndent();
    switch (key_classification) {
        .int => {
            // Cast comptime_int key to i64 for AutoHashMap
            try self.emit("try _dict.put(@as(i64, kv[0]), cast_val);\n");
        },
        .string => {
            try self.emit("try _dict.put(kv[0], cast_val);\n");
        },
        .pyvalue => {
            // Convert key and value to PyValue for mixed/unknown key types
            // PyValueHashMap uses managed ArrayHashMap - put() uses stored allocator
            try self.emit("try _dict.put(try runtime.toPyValue(");
            try self.emit(alloc_name);
            try self.emit(", kv[0]), try runtime.toPyValue(");
            try self.emit(alloc_name);
            try self.emit(", cast_val));\n");
        },
    }
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.emitFmt("break :{s} _dict;\n", .{label});
    self.dedent();
    try self.emitIndent();
    try self.emitInlineBlockEnd();
}

/// Helper to get value type from an entry (accounting for dict unpacking)
fn getEntryValueType(self: *NativeCodegen, key: ast.Node, value: ast.Node) CodegenError!@import("../../../analysis/native_types.zig").NativeType {
    // Dict unpacking: None key signals **other_dict
    if (key == .constant and key.constant.value == .none) {
        const dict_type = try self.type_inferrer.inferExpr(value);
        if (container_traits.isDict(dict_type)) {
            return dict_type.dict.value.*;
        }
        // Two-Flow: PyValue dict - value type is also PyValue
        if (dict_type == .pyvalue) {
            return .pyvalue;
        }
        return .unknown;
    }
    return try self.type_inferrer.inferExpr(value);
}

/// Generate runtime dict literal (fallback path)
fn genDictRuntime(self: *NativeCodegen, dict: ast.Node.Dict, alloc_name: []const u8) CodegenError!void {
    // Infer key type from first key (for non-unpacking entries)
    // Use getDictKeyType for proper classification (int, string, pyvalue for tuples/bools/etc)
    var key_classification: type_traits.DictKeyType = .string; // Default to string
    for (dict.keys) |key| {
        if (key != .constant or key.constant.value != .none) {
            const key_type = try self.type_inferrer.inferExpr(key);
            key_classification = type_traits.getDictKeyType(key_type);
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
    const label = try self.emitInlineBlockStart("dict");
    // Generate unique map variable name to avoid shadowing in nested dicts
    const map_var = try self.name_gen.temp();
    try self.emit("\n");
    self.indent();
    try self.emitIndent();
    switch (key_classification) {
        .int => {
            // Integer keys - use AutoArrayHashMap with i64 key type (has .keys() and .values())
            try self.emitFmt("var {s} = std.AutoArrayHashMap(i64, ", .{map_var});
            try val_type.toZigType(self.allocator, &self.output);
            try self.emit(").init(");
            try self.emit(alloc_name);
            try self.emit(");\n");
        },
        .string => {
            // String keys - use StringHashMap
            try self.emitFmt("var {s} = hashmap_helper.StringHashMap(", .{map_var});
            try val_type.toZigType(self.allocator, &self.output);
            try self.emit(").init(");
            try self.emit(alloc_name);
            try self.emit(");\n");
        },
        .pyvalue => {
            // Tuple/bool/mixed key types - use PyValueHashMap
            // PyValueHashMap uses managed ArrayHashMap - requires .init(allocator)
            try self.emitFmt("var {s} = runtime.PyValueHashMap(runtime.PyValue).init(", .{map_var});
            try self.emit(alloc_name);
            try self.emit(");\n");
        },
    }

    // Track if we need to convert values to strings
    const need_str_conversion = string_traits.isString(val_type);

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

    // Track that we're inside a dict for proper nested list generation
    // Dict values should generate as ArrayList, not fixed arrays
    self.inside_list_depth += 1;
    defer self.inside_list_depth -= 1;

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
            // If target dict expects PyValue, wrap the source value
            if (val_type == .pyvalue) {
                try self.emitFmt("try {s}.put(entry.key_ptr.*, try runtime.PyValue.fromAlloc(", .{map_var});
                try self.emit(alloc_name);
                try self.emit(", entry.value_ptr.*));\n");
            } else {
                try self.emitFmt("try {s}.put(entry.key_ptr.*, entry.value_ptr.*);\n", .{map_var});
            }
            self.dedent();
            try self.emitIndent();
            try self.emit("}\n");
            self.dedent();
            try self.emitIndent();
            try self.emit("}\n");
            continue;
        }

        try self.emitIndent();
        try self.emitFmt("try {s}.put(", .{map_var});

        // Generate key with appropriate conversion
        switch (key_classification) {
            .int => {
                // Cast to i64 for AutoArrayHashMap
                try self.emit("@as(i64, ");
                try genExpr(self, key);
                try self.emit(")");
            },
            .string => {
                try genExpr(self, key);
            },
            .pyvalue => {
                // Convert key to PyValue for PyValueHashMap
                try self.emit("try runtime.toPyValue(");
                try self.emit(alloc_name);
                try self.emit(", ");
                try genExpr(self, key);
                try self.emit(")");
            },
        }
        try self.emit(", ");

        // Generate value with appropriate conversion
        switch (key_classification) {
            .pyvalue => {
                // PyValueHashMap always uses PyValue values
                try self.emit("try runtime.toPyValue(");
                try self.emit(alloc_name);
                try self.emit(", ");
                try genExpr(self, value);
                try self.emit(")");
            },
            else => {
                // If dict values are string type and this value isn't string, convert it
                if (need_str_conversion) {
                    const value_type = try self.type_inferrer.inferExpr(value);
                    if (!string_traits.isString(value_type)) {
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
            },
        }

        try self.emit(");\n");
    }

    try self.emitIndent();
    // Break with map value
    try self.emitFmt("break :{s} {s};\n", .{ label, map_var });
    self.dedent();
    try self.emitIndent();
    try self.emitInlineBlockEnd();
}

/// Generate code to convert a value to string
fn genValueToString(
    self: *NativeCodegen,
    value: ast.Node,
    value_type: @import("../../../analysis/native_types.zig").NativeType,
    alloc_name: []const u8,
) CodegenError!void {
    if (type_traits.isBoolean(value_type)) {
        // Bool: use ternary for Python-style True/False
        try self.emit("try ");
        try self.emit(alloc_name);
        try self.emit(".dupe(u8, if (");
        try genExpr(self, value);
        try self.emit(") \"True\" else \"False\")");
    } else if (type_traits.isNone(value_type)) {
        // None: just use literal "None"
        try emitAllocDupe(self, alloc_name, "\"None\"");
    } else {
        try self.emit("try std.fmt.allocPrint(");
        try self.emit(alloc_name);
        try self.emit(", ");
        if (type_traits.isIntegral(value_type)) {
            try self.emit("\"{d}\"");
        } else if (type_traits.isFloating(value_type)) {
            try self.emit("\"{d}\"");
        } else {
            try self.emit("\"{any}\"");
        }
        try self.emit(", .{");
        try genExpr(self, value);
        try self.emit("})");
    }
}
