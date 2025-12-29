/// List literal code generation
/// Handles list literal expressions with array optimization and comptime/runtime paths
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
const native_types = @import("../../../analysis/native_types.zig");
const NativeType = native_types.NativeType;
const string_traits = @import("../../../analysis/traits/string_traits.zig");
const type_traits = @import("../../../analysis/traits/type_traits.zig");
const expr_emitter = @import("../expr_emitter.zig");
const builder_mod = @import("codegen.builder");
const ZigValue = builder_mod.ZigValue;
const CallArg = builder_mod.ZigBuilder.CallArg;

// MIGRATED TO ZIGBUILDER

// ============================================
// Collection operation helpers - auto-closing patterns
// ============================================

/// Emit runtime.builtins.PyCallable.fromAny(@TypeOf(expr), expr) using builder
fn emitPyCallableFromAny(self: *NativeCodegen, expr: ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    const alloc = self.arena.allocator();
    // Capture expression to get raw string
    const expr_val = try self.captureExpr(expr);
    try b.emitValueCore(expr_val);
    const expr_raw = try alloc.dupe(u8, b.getBodyAndClear());
    // Build @TypeOf(expr) expression
    const typeof_expr = try std.fmt.allocPrint(alloc, "@TypeOf({s})", .{expr_raw});
    try b.emitCallExpr("runtime.builtins.PyCallable.fromAny", &[_]CallArg{
        .{ .raw = typeof_expr },
        .{ .raw = expr_raw },
    });
    const result = try alloc.dupe(u8, b.getBodyAndClear());
    try self.emitZigValue(ZigValue.raw(result));
}

/// Emit runtime.builtins.PyCallable.fromAny(@TypeOf(name.init), name.init) for class constructors
fn emitPyCallableFromInit(self: *NativeCodegen, class_name: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    const alloc = self.arena.allocator();
    // Build class_name.init expression
    const init_expr = try std.fmt.allocPrint(alloc, "{s}.init", .{class_name});
    const typeof_expr = try std.fmt.allocPrint(alloc, "@TypeOf({s})", .{init_expr});
    try b.emitCallExpr("runtime.builtins.PyCallable.fromAny", &[_]CallArg{
        .{ .raw = typeof_expr },
        .{ .raw = init_expr },
    });
    const result = try alloc.dupe(u8, b.getBodyAndClear());
    try self.emitZigValue(ZigValue.raw(result));
}

/// Emit runtime.builtins.PyCallable.fromAny(@TypeOf(fn_name), fn_name) for raw function names
fn emitPyCallableFromRaw(self: *NativeCodegen, fn_name: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    const alloc = self.arena.allocator();
    const typeof_expr = try std.fmt.allocPrint(alloc, "@TypeOf({s})", .{fn_name});
    try b.emitCallExpr("runtime.builtins.PyCallable.fromAny", &[_]CallArg{
        .{ .raw = typeof_expr },
        .{ .raw = fn_name },
    });
    const result = try alloc.dupe(u8, b.getBodyAndClear());
    try self.emitZigValue(ZigValue.raw(result));
}

/// Emit @as(f64, @floatFromInt(operand)) for int-to-float conversion
fn emitFloatFromInt(self: *NativeCodegen, operand: ZigValue) CodegenError!void {
    try self.emit("@as(f64, @floatFromInt(");
    try self.emitZigValue(operand);
    try self.emit("))");
}

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
                    // Use PyCallable.fromAny with the runtime builtin function (builder pattern)
                    try emitPyCallableFromRaw(self, builtin_fn);
                    return;
                }
            }
            // Already a PyCallable (bytes_factory, etc.) - emit directly
            try genExpr(self, elem);
        },
        .function => {
            // Lambda or function - wrap using fromAny for type erasure
            try emitPyCallableFromAny(self, elem);
        },
        .class_instance => |class_name| {
            // Class used as constructor - wrap in PyCallable
            try emitPyCallableFromInit(self, class_name);
        },
        else => {
            // Unknown callable type - try to wrap it generically
            // Check if it's a name node for a class
            if (elem == .name) {
                const name = elem.name.id;
                // Check if it's a known class in class_fields
                if (self.type_inferrer.class_fields.contains(name)) {
                    try emitPyCallableFromInit(self, name);
                    return;
                }
            }
            // Fallback - wrap using fromAny for type erasure
            try emitPyCallableFromAny(self, elem);
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

        // Capture and emit element value
        const operand = try self.captureExpr(elem);
        try self.emitZigValue(operand);
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
    // Generate unique names using NameGen to prevent shadowing
    const id = self.nextNameId();

    try self.emitFmt("__list_blk_{d}: {{\n", .{id});
    self.indent();
    try self.emitIndent();

    // Generate comptime tuple
    try self.emitFmt("const __values_{d} = .{{ ", .{id});
    for (list.elts, 0..) |elem, i| {
        if (i > 0) try self.emit(", ");
        const operand = try self.captureExpr(elem);
        try self.emitZigValue(operand);
    }
    try self.emit(" };\n");

    // Let Zig's comptime infer the type and generate optimal code
    try self.emitIndent();
    try self.emitFmt("const __T_{d} = comptime runtime.InferListType(@TypeOf(__values_{d}));\n", .{ id, id });

    try self.emitIndent();
    try self.emitFmt("var __list_{d} = std.ArrayListUnmanaged(__T_{d}){{}};\n", .{ id, id });

    // Inline loop - call runtime helper for type casting (reduces monomorphization)
    try self.emitIndent();
    try self.emitFmt("inline for (__values_{d}) |val| {{\n", .{id});
    self.indent();
    try self.emitIndent();
    try self.emitFmt("try runtime.list_ops.appendCast(__T_{d}, &__list_{d}, __global_allocator, val);\n", .{ id, id });
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.emitFmt("break :__list_blk_{d} __list_{d};\n", .{ id, id });
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Widen tuple types element-wise, making positions optional if any element has None
/// Recursively widens nested tuples to handle heterogeneous nested structures
/// Public to allow use in other codegen modules (e.g., value_generation)
pub fn widenTupleTypes(allocator: std.mem.Allocator, t1: NativeType, t2: NativeType) !NativeType {
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
        } else if (@as(std.meta.Tag(NativeType), elem1) == .tuple and @as(std.meta.Tag(NativeType), elem2) == .tuple) {
            // Recursively widen nested tuples (e.g., list of tuple of tuples)
            new_types[i] = try widenTupleTypes(allocator, elem1, elem2);
        } else {
            new_types[i] = elem1.widen(elem2);
        }
    }

    return .{ .tuple = new_types };
}

/// Generate runtime list literal (fallback path)
fn genListRuntime(self: *NativeCodegen, list: ast.Node.List) CodegenError!void {
    // Generate unique names using NameGen to prevent shadowing
    const id = self.nextNameId();

    try self.emitFmt("__list_rt_{d}: {{\n", .{id});
    self.indent();
    try self.emitIndent();

    // Infer element type using type widening
    var elem_type = try self.type_inferrer.inferExpr(list.elts[0]);

    // Widen type to accommodate all elements (use element-wise widening for tuples)
    for (list.elts[1..]) |elem| {
        const this_type = try self.type_inferrer.inferExpr(elem);
        elem_type = try widenTupleTypes(self.allocator, elem_type, this_type);
    }

    try self.emitFmt("var __list_var_{d} = std.ArrayListUnmanaged(", .{id});
    try elem_type.toZigType(self.allocator, &self.output);
    try self.emit("){};\n");

    // Append each element (with type coercion if needed)
    for (list.elts) |elem| {
        try self.emitIndent();
        try self.emitFmt("try __list_var_{d}.append(__global_allocator, ", .{id});

        // Check if we need to cast this element
        const this_type = try self.type_inferrer.inferExpr(elem);
        // Need int→float cast when list element type is float but value is int
        // (type_traits.isConvertible confirms int→float is valid)
        const needs_cast = type_traits.isFloating(elem_type) and type_traits.isIntegral(this_type);

        // Capture the element expression
        const operand = try self.captureExpr(elem);

        if (needs_cast) {
            try emitFloatFromInt(self, operand);
        } else if (type_traits.isCallable(elem_type)) {
            // List of callables - wrap non-PyCallable elements
            try genCallableElement(self, elem, this_type);
        } else {
            try self.emitZigValue(operand);
        }

        try self.emit(");\n");
    }

    try self.emitIndent();
    try self.emitFmt("break :__list_rt_{d} __list_var_{d};\n", .{ id, id });
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

    // Generate unique names using NameGen to prevent shadowing
    const id = self.nextNameId();

    try self.emitFmt("__set_blk_{d}: {{\n", .{id});
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
        try self.emitFmt("var __set_{d} = hashmap_helper.StringHashMap(void).init(__global_allocator);\n", .{id});
    } else if (is_float) {
        // Floats can't be hashed directly in Zig, use u64 bit representation
        try self.emitFmt("var __set_{d} = std.AutoHashMap(u64, void).init(__global_allocator);\n", .{id});
    } else {
        try self.emitFmt("var __set_{d} = std.AutoHashMap(", .{id});
        try elem_type.toZigType(self.allocator, &self.output);
        try self.emit(", void).init(__global_allocator);\n");
    }

    // Add each element (use try for error handling)
    for (set_node.elts) |elem| {
        // Capture element expression
        const operand = try self.captureExpr(elem);

        try self.emitIndent();
        if (is_float) {
            // Convert float to bits for hashing
            try self.emitFmt("try __set_{d}.put(@bitCast(", .{id});
            try self.emitZigValue(operand);
            try self.emit("), {});\n");
        } else {
            try self.emitFmt("try __set_{d}.put(", .{id});
            try self.emitZigValue(operand);
            try self.emit(", {});\n");
        }
    }

    try self.emitIndent();
    try self.emitFmt("break :__set_blk_{d} __set_{d};\n", .{ id, id });
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}
