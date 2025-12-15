/// List literal code generation
/// Handles list literal expressions with array optimization and comptime/runtime paths
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const expressions = @import("../expressions.zig");
const genExpr = expressions.genExpr;
const native_types = @import("../../../analysis/native_types.zig");
const NativeType = native_types.NativeType;
const string_traits = @import("../../../analysis/traits/string_traits.zig");
const type_traits = @import("../../../analysis/traits/type_traits.zig");

// Re-export dict generation from dict.zig
const dict = @import("dict.zig");
pub const genDict = dict.genDict;

// Re-export isComptimeConstant for use by other modules
pub const isComptimeConstant = dict.isComptimeConstant;

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

/// Builtin type names that need special handling when used as first-class values
/// Maps Python type names to runtime callable functions with ([]const u8) -> []const u8 signature
const BuiltinTypeNames = std.StaticStringMap([]const u8).initComptime(.{
    .{ "bool", "runtime.boolBuiltin" },
    .{ "int", "runtime.intBuiltin" },
    .{ "float", "runtime.floatBuiltin" },
    .{ "str", "runtime.strBuiltin" },
    .{ "bytes", "runtime.bytesBuiltin" },
    .{ "list", "runtime.listBuiltin" },
    .{ "dict", "runtime.dictBuiltin" },
    .{ "set", "runtime.setBuiltin" },
    .{ "tuple", "runtime.tupleBuiltin" },
    .{ "frozenset", "runtime.frozensetBuiltin" },
    .{ "type", "runtime.typeBuiltin" },
    .{ "object", "runtime.objectBuiltin" },
    .{ "complex", "runtime.complexBuiltin" },
});

/// Generate an element for a list of callables (PyCallable)
/// Wraps lambdas, classes, and other callable elements in PyCallable.fromFn
fn genCallableElement(self: *NativeCodegen, elem: ast.Node, elem_type: NativeType) CodegenError!void {
    switch (elem_type) {
        .callable => {
            // Check if this is a builtin type name that needs wrapping
            if (elem == .name) {
                if (BuiltinTypeNames.get(elem.name.id)) |builtin_fn| {
                    // Use PyCallable.fromAny with the runtime builtin function
                    try self.emit("runtime.builtins.PyCallable.fromAny(@TypeOf(");
                    try self.emit(builtin_fn);
                    try self.emit("), ");
                    try self.emit(builtin_fn);
                    try self.emit(")");
                    return;
                }
            }
            // Already a PyCallable (bytes_factory, etc.) - emit directly
            try genExpr(self, elem);
        },
        .function => {
            // Lambda or function - wrap using fromAny for type erasure
            try self.emit("runtime.builtins.PyCallable.fromAny(@TypeOf(");
            try genExpr(self, elem);
            try self.emit("), ");
            try genExpr(self, elem);
            try self.emit(")");
        },
        .class_instance => |class_name| {
            // Class used as constructor - wrap in PyCallable
            try self.emit("runtime.builtins.PyCallable.fromAny(@TypeOf(");
            try self.emit(class_name);
            try self.emit(".init), ");
            try self.emit(class_name);
            try self.emit(".init)");
        },
        else => {
            // Unknown callable type - try to wrap it generically
            // Check if it's a name node for a class
            if (elem == .name) {
                const name = elem.name.id;
                // Check if it's a known class in class_fields
                if (self.type_inferrer.class_fields.contains(name)) {
                    try self.emit("runtime.builtins.PyCallable.fromAny(@TypeOf(");
                    try self.emit(name);
                    try self.emit(".init), ");
                    try self.emit(name);
                    try self.emit(".init)");
                    return;
                }
            }
            // Fallback - wrap using fromAny for type erasure
            try self.emit("runtime.builtins.PyCallable.fromAny(@TypeOf(");
            try genExpr(self, elem);
            try self.emit("), ");
            try genExpr(self, elem);
            try self.emit(")");
        },
    }
}

/// Generate fixed-size array literal for constant, homogeneous lists
fn genArrayLiteral(self: *NativeCodegen, list: ast.Node.List) CodegenError!void {
    // Determine element type from first element
    const elem_type_str = switch (list.elts[0].constant.value) {
        .int => "i64",
        .bigint => "runtime.BigInt",
        .float => "f64",
        .string => "[]const u8",
        .bytes => "runtime.builtins.PyBytes",
        .bool => "bool",
        .none => "void",
        .complex => "runtime.PyComplex",
    };

    // Emit array literal: [_]T{elem1, elem2, ...}
    try self.emit("[_]");
    try self.emit(elem_type_str);
    try self.emit("{");

    for (list.elts, 0..) |elem, i| {
        if (i > 0) try self.emit(", ");

        // Emit element value - use genExpr for proper formatting
        try genExpr(self, elem);
    }

    try self.emit("}");
}

/// Generate list literal as ArrayList (Python lists are always mutable)
pub fn genList(self: *NativeCodegen, list: ast.Node.List) CodegenError!void {
    // Empty lists - use type from context if available
    if (list.elts.len == 0) {
        // Check if we have a target variable name from assignment context
        if (self.current_assign_target) |target_name| {
            // Check if function_traits analysis determined this list needs PyValue type
            // (will be assigned heterogeneous types later via += or append)
            if (self.varNeedsPyValue(target_name)) {
                try self.emit("std.ArrayListUnmanaged(runtime.PyValue){}");
                return;
            }

            // Look up the inferred type for this variable
            var type_buf = std.ArrayListUnmanaged(u8){};
            defer type_buf.deinit(self.allocator);
            const var_type = self.type_inferrer.getScopedVar(target_name) orelse
                self.type_inferrer.var_types.get(target_name);
            if (var_type) |vt| {
                vt.toZigType(self.allocator, &type_buf) catch {};
                if (type_buf.items.len > 0) {
                    // Check if element type is exactly *runtime.PyObject (unknown element)
                    // This specifically matches lists of unknown elements, NOT structs/tuples
                    // containing *runtime.PyObject (which are valid typed elements)
                    if (std.mem.eql(u8, type_buf.items, "std.ArrayListUnmanaged(*runtime.PyObject)"))
                    {
                        try self.emit("std.ArrayListUnmanaged([]const u8){}");
                        return;
                    }
                    // Use the inferred type directly if it's an ArrayList
                    if (std.mem.startsWith(u8, type_buf.items, "std.ArrayListUnmanaged(")) {
                        try self.emit(type_buf.items);
                        try self.emit("{}");
                        return;
                    }
                }
            }
        }
        // Default to i64 for empty lists without type context
        try self.emit("std.ArrayListUnmanaged(i64){}");
        return;
    }

    // Check if we can optimize to fixed-size array (constant + homogeneous)
    // BUT: Only use array optimization at the top level (inside_list_depth == 0)
    // Nested lists (inside other lists) must be ArrayLists to match parent's element type
    // Also skip array optimization if elements are themselves lists (nested lists)
    const has_nested_lists = blk: {
        for (list.elts) |elem| {
            if (elem == .list) break :blk true;
        }
        break :blk false;
    };
    // Only use array literal if:
    // 1. We're at top level (not inside another list)
    // 2. Elements are constants
    // 3. Elements are homogeneous
    // 4. No nested lists (which require ArrayList type)
    if (self.inside_list_depth == 0 and isConstantList(list) and allSameType(list.elts) and !has_nested_lists) {
        return try genArrayLiteral(self, list);
    }

    // Track that we're inside a list for nested list generation
    self.inside_list_depth += 1;
    defer self.inside_list_depth -= 1;

    // Check if all elements are compile-time constants → use comptime optimization!
    // BUT: Skip comptime path if we have nested lists - the type inference doesn't
    // work correctly for nested ArrayList structures
    var all_comptime = true;
    for (list.elts) |elem| {
        if (!isComptimeConstant(elem)) {
            all_comptime = false;
            break;
        }
    }

    // COMPTIME PATH: All elements known at compile time AND no nested lists
    // Nested lists need runtime path because InferListType can't handle ArrayList element types
    if (all_comptime and !has_nested_lists) {
        try genListComptime(self, list);
        return;
    }

    // RUNTIME PATH: Dynamic list (fallback to current widening approach)
    try genListRuntime(self, list);
}

/// Generate comptime-optimized list literal
fn genListComptime(self: *NativeCodegen, list: ast.Node.List) CodegenError!void {
    // Generate unique block label using block_label_counter (not pointer addresses)
    const label_id = self.block_label_counter;
    self.block_label_counter += 1;
    const label = try std.fmt.allocPrint(self.allocator, "__list_blk_{d}", .{label_id});
    defer self.allocator.free(label);
    const list_var = try std.fmt.allocPrint(self.allocator, "__list_{d}", .{label_id});
    defer self.allocator.free(list_var);
    const values_var = try std.fmt.allocPrint(self.allocator, "__values_{d}", .{label_id});
    defer self.allocator.free(values_var);

    try self.emit(label);
    try self.emit(": {\n");
    self.indent();
    try self.emitIndent();

    // Generate comptime tuple
    try self.emit("const ");
    try self.emit(values_var);
    try self.emit(" = .{ ");
    for (list.elts, 0..) |elem, i| {
        if (i > 0) try self.emit(", ");
        try genExpr(self, elem);
    }
    try self.emit(" };\n");

    // Let Zig's comptime infer the type and generate optimal code
    try self.emitIndent();
    try self.emit("const __T = comptime runtime.InferListType(@TypeOf(");
    try self.emit(values_var);
    try self.emit("));\n");

    try self.emitIndent();
    try self.emit("var ");
    try self.emit(list_var);
    try self.emit(" = std.ArrayListUnmanaged(__T){};\n");

    // Inline loop - call runtime helper for type casting (reduces monomorphization)
    try self.emitIndent();
    try self.emit("inline for (");
    try self.emit(values_var);
    try self.emit(") |val| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("try runtime.list_ops.appendCast(__T, &");
    try self.emit(list_var);
    try self.emit(", __global_allocator, val);\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.emit("break :");
    try self.emit(label);
    try self.emit(" ");
    try self.emit(list_var);
    try self.emit(";\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Widen tuple types element-wise, making positions optional if any element has None
fn widenTupleTypes(allocator: std.mem.Allocator, t1: NativeType, t2: NativeType) !NativeType {
    // Both must be tuples with same length
    if (@as(std.meta.Tag(NativeType), t1) != .tuple or @as(std.meta.Tag(NativeType), t2) != .tuple) {
        return t1.widen(t2);
    }
    if (t1.tuple.len != t2.tuple.len) {
        return t1.widen(t2);
    }

    // Widen each position
    var new_types = try allocator.alloc(NativeType, t1.tuple.len);
    for (t1.tuple, t2.tuple, 0..) |elem1, elem2, i| {
        // If either is None, result is optional of the other
        if (elem1 == .none and elem2 != .none) {
            const inner = try allocator.create(NativeType);
            inner.* = elem2;
            new_types[i] = .{ .optional = inner };
        } else if (elem2 == .none and elem1 != .none) {
            const inner = try allocator.create(NativeType);
            inner.* = elem1;
            new_types[i] = .{ .optional = inner };
        } else {
            new_types[i] = elem1.widen(elem2);
        }
    }

    return .{ .tuple = new_types };
}

/// Generate runtime list literal (fallback path)
fn genListRuntime(self: *NativeCodegen, list: ast.Node.List) CodegenError!void {
    // Generate unique block label using block_label_counter (not pointer addresses)
    const label_id = self.block_label_counter;
    self.block_label_counter += 1;
    const runtime_label = try std.fmt.allocPrint(self.allocator, "__list_rt_{d}", .{label_id});
    defer self.allocator.free(runtime_label);
    const list_var = try std.fmt.allocPrint(self.allocator, "__list_var_{d}", .{label_id});
    defer self.allocator.free(list_var);

    try self.emit(runtime_label);
    try self.emit(": {\n");
    self.indent();
    try self.emitIndent();

    // Infer element type using type widening
    var elem_type = try self.type_inferrer.inferExpr(list.elts[0]);

    // Widen type to accommodate all elements (use element-wise widening for tuples)
    for (list.elts[1..]) |elem| {
        const this_type = try self.type_inferrer.inferExpr(elem);
        elem_type = try widenTupleTypes(self.allocator, elem_type, this_type);
    }

    try self.emit("var ");
    try self.emit(list_var);
    try self.emit(" = std.ArrayListUnmanaged(");
    try elem_type.toZigType(self.allocator, &self.output);
    try self.emit("){};\n");

    // Append each element (with type coercion if needed)
    for (list.elts) |elem| {
        try self.emitIndent();
        try self.emit("try ");
        try self.emit(list_var);
        try self.emit(".append(__global_allocator, ");

        // Check if we need to cast this element
        const this_type = try self.type_inferrer.inferExpr(elem);
        // Need int→float cast when list element type is float but value is int
        // (type_traits.isConvertible confirms int→float is valid)
        const needs_cast = type_traits.isFloating(elem_type) and type_traits.isIntegral(this_type);

        if (needs_cast) {
            try self.emit("@as(f64, @floatFromInt(");
            try genExpr(self, elem);
            try self.emit("))");
        } else if (type_traits.isCallable(elem_type)) {
            // List of callables - wrap non-PyCallable elements
            try genCallableElement(self, elem, this_type);
        } else {
            try genExpr(self, elem);
        }

        try self.emit(");\n");
    }

    try self.emitIndent();
    try self.emit("break :");
    try self.emit(runtime_label);
    try self.emit(" ");
    try self.emit(list_var);
    try self.emit(";\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate set literal as StringHashMap(void) for strings, AutoHashMap for others
pub fn genSet(self: *NativeCodegen, set_node: ast.Node.Set) CodegenError!void {
    // Empty sets shouldn't happen (parsed as empty dict), but handle it
    if (set_node.elts.len == 0) {
        try self.emit("hashmap_helper.StringHashMap(void).init(__global_allocator)");
        return;
    }

    // Generate unique block label using block_label_counter (not pointer addresses)
    const label_id = self.block_label_counter;
    self.block_label_counter += 1;
    const label = try std.fmt.allocPrint(self.allocator, "__set_blk_{d}", .{label_id});
    defer self.allocator.free(label);

    try self.emit(label);
    try self.emit(": {\n");
    self.indent();
    try self.emitIndent();

    // Infer element type from first element
    var elem_type = try self.type_inferrer.inferExpr(set_node.elts[0]);
    for (set_node.elts[1..]) |elem| {
        const this_type = try self.type_inferrer.inferExpr(elem);
        elem_type = elem_type.widen(this_type);
    }

    // Use StringHashMap for strings, AutoHashMap for primitives
    // Note: floats need special handling - use u64 bit representation as key
    const is_string = string_traits.isString(elem_type);
    const is_float = type_traits.isFloating(elem_type);
    if (is_string) {
        try self.emit("var _set = hashmap_helper.StringHashMap(void).init(__global_allocator);\n");
    } else if (is_float) {
        // Floats can't be hashed directly in Zig, use u64 bit representation
        try self.emit("var _set = std.AutoHashMap(u64, void).init(__global_allocator);\n");
    } else {
        try self.emit("var _set = std.AutoHashMap(");
        try elem_type.toZigType(self.allocator, &self.output);
        try self.emit(", void).init(__global_allocator);\n");
    }

    // Add each element (use catch unreachable since allocation failures are rare)
    for (set_node.elts) |elem| {
        try self.emitIndent();
        if (is_float) {
            // Convert float to bits for hashing
            try self.emit("_set.put(@bitCast(");
            try genExpr(self, elem);
            try self.emit("), {}) catch unreachable;\n");
        } else {
            try self.emit("_set.put(");
            try genExpr(self, elem);
            try self.emit(", {}) catch unreachable;\n");
        }
    }

    try self.emitIndent();
    try self.emit("break :");
    try self.emit(label);
    try self.emit(" _set;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}
