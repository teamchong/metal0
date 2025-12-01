/// List literal code generation
/// Handles list literal expressions with array optimization and comptime/runtime paths
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const expressions = @import("../expressions.zig");
const genExpr = expressions.genExpr;
const native_types = @import("../../../analysis/native_types.zig");
const NativeType = native_types.NativeType;

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
        .bytes => "[]const u8",
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
        // and its inferred type indicates string elements
        if (self.current_assign_target) |target_name| {
            // Look up the inferred type for this variable
            var type_buf = std.ArrayList(u8){};
            defer type_buf.deinit(self.allocator);
            const var_type = self.type_inferrer.getScopedVar(target_name) orelse
                self.type_inferrer.var_types.get(target_name);
            if (var_type) |vt| {
                vt.toZigType(self.allocator, &type_buf) catch {};
                if (type_buf.items.len > 0) {
                    // Check if it's a string list (PyObject = strings in our context)
                    if (std.mem.indexOf(u8, type_buf.items, "std.ArrayList(*runtime.PyObject)") != null or
                        std.mem.indexOf(u8, type_buf.items, "std.ArrayList([]const u8)") != null)
                    {
                        try self.emit("std.ArrayList([]const u8){}");
                        return;
                    }
                    // Use the inferred type directly if it's an ArrayList
                    if (std.mem.startsWith(u8, type_buf.items, "std.ArrayList(")) {
                        try self.emit(type_buf.items);
                        try self.emit("{}");
                        return;
                    }
                }
            }
        }
        // Default to i64 for empty lists without type context
        try self.emit("std.ArrayList(i64){}");
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
        try genListComptime(self, list);
        return;
    }

    // RUNTIME PATH: Dynamic list (fallback to current widening approach)
    try genListRuntime(self, list);
}

/// Generate comptime-optimized list literal
fn genListComptime(self: *NativeCodegen, list: ast.Node.List) CodegenError!void {
    // Generate unique block label and list variable name
    const list_id = @intFromPtr(list.elts.ptr);
    const label = try std.fmt.allocPrint(self.allocator, "list_{d}", .{list_id});
    defer self.allocator.free(label);
    const list_var = try std.fmt.allocPrint(self.allocator, "_list_{d}", .{list_id});
    defer self.allocator.free(list_var);
    const values_var = try std.fmt.allocPrint(self.allocator, "_values_{d}", .{list_id});
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
    try self.emit("const T = comptime runtime.InferListType(@TypeOf(");
    try self.emit(values_var);
    try self.emit("));\n");

    try self.emitIndent();
    try self.emit("var ");
    try self.emit(list_var);
    try self.emit(" = std.ArrayList(T){};\n");

    // Inline loop - unrolled at Zig compile time!
    try self.emitIndent();
    try self.emit("inline for (");
    try self.emit(values_var);
    try self.emit(") |val| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const cast_val = if (@TypeOf(val) != T) cast_blk: {\n");
    self.indent();
    // PyValue conversion for heterogeneous lists
    try self.emitIndent();
    try self.emit("if (T == runtime.PyValue) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("break :cast_blk try runtime.PyValue.fromAlloc(__global_allocator, val);\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("if (T == f64 and (@TypeOf(val) == i64 or @TypeOf(val) == comptime_int)) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("break :cast_blk @as(f64, @floatFromInt(val));\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("if (T == f64 and @TypeOf(val) == comptime_float) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("break :cast_blk @as(f64, val);\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :cast_blk val;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("} else val;\n");
    try self.emitIndent();
    try self.emit("try ");
    try self.emit(list_var);
    try self.emit(".append(__global_allocator, cast_val);\n");
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
    const list_id = @intFromPtr(list.elts.ptr);
    const runtime_label = try std.fmt.allocPrint(self.allocator, "list_{d}", .{list_id});
    defer self.allocator.free(runtime_label);
    const list_var = try std.fmt.allocPrint(self.allocator, "_list_{d}", .{list_id});
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
    try self.emit(" = std.ArrayList(");
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
        const needs_cast = (elem_type == .float and this_type == .int);

        if (needs_cast) {
            try self.emit("@as(f64, @floatFromInt(");
            try genExpr(self, elem);
            try self.emit("))");
        } else if (@as(std.meta.Tag(NativeType), elem_type) == .callable) {
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

    // Generate unique block label
    const label = try std.fmt.allocPrint(self.allocator, "set_{d}", .{@intFromPtr(set_node.elts.ptr)});
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
    const is_string = (elem_type == .string);
    const is_float = (elem_type == .float);
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
