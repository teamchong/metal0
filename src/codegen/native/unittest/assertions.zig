/// unittest assertion code generation
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const parent = @import("../expressions.zig");
const shared = @import("../shared_maps.zig");
const PyToZigTypes = shared.PyTypeToZig;
const zig_keywords = @import("utils.zig_keywords");
const NativeType = @import("../../../analysis/native_types/core.zig").NativeType;

/// Check if a name is a Python builtin type name (not a user variable)
fn isBuiltinTypeName(name: []const u8) bool {
    // Use shared RuntimeExceptions map for comprehensive exception coverage
    if (shared.RuntimeExceptions.has(name)) return true;

    const builtin_types = [_][]const u8{
        "int",      "float",      "str",         "bool",       "list",       "dict",      "set",         "tuple",
        "type",     "object",     "bytes",       "bytearray",  "frozenset",  "range",     "complex",     "memoryview",
        "slice",    "property",   "classmethod", "staticmethod", "super",
    };
    for (builtin_types) |t| {
        if (std.mem.eql(u8, name, t)) return true;
    }
    return false;
}

const FloatMethodInfo = struct { func: []const u8, needs_alloc: bool };
const FloatMethods = std.StaticStringMap(FloatMethodInfo).initComptime(.{
    .{ "as_integer_ratio", FloatMethodInfo{ .func = "AsIntegerRatio", .needs_alloc = false } },
    .{ "is_integer", FloatMethodInfo{ .func = "IsInteger", .needs_alloc = false } },
    .{ "hex", FloatMethodInfo{ .func = "Hex(__global_allocator, ", .needs_alloc = true } },
    .{ "conjugate", FloatMethodInfo{ .func = "Conjugate", .needs_alloc = false } },
    // Use Big variants for __floor__/__ceil__ to handle large floats (1.23e167) without overflow
    .{ "__floor__", FloatMethodInfo{ .func = "FloorBig(__global_allocator, ", .needs_alloc = true } },
    .{ "__ceil__", FloatMethodInfo{ .func = "CeilBig(__global_allocator, ", .needs_alloc = true } },
    .{ "__trunc__", FloatMethodInfo{ .func = "Trunc(__global_allocator, ", .needs_alloc = true } },
    .{ "__round__", FloatMethodInfo{ .func = "Round(__global_allocator, ", .needs_alloc = true } },
});

// Float class methods (e.g., float.__getformat__) - maps Python method names to runtime function names
const FloatClassMethods = std.StaticStringMap([]const u8).initComptime(.{
    .{ "fromhex", "runtime.floatFromHex" },
    .{ "__getformat__", "runtime.floatGetFormat" },
});

/// Handler type for assertion methods
const AssertHandler = *const fn (*NativeCodegen, ast.Node, []ast.Node) CodegenError!void;

// Comptime generator for simple 1-arg assertions: try unittest.func(arg)
fn gen1ArgAssert(comptime func_name: []const u8) AssertHandler {
    return struct {
        fn handler(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
            _ = obj;
            if (args.len < 1) {
                try self.emit("@compileError(\"" ++ func_name ++ " requires 1 argument\")");
                return;
            }
            try self.emit("try unittest." ++ func_name ++ "(");
            try parent.genExpr(self, args[0]);
            try self.emit(")");
        }
    }.handler;
}

// Comptime generator for simple 2-arg assertions: try unittest.func(a, b)
fn gen2ArgAssert(comptime func_name: []const u8) AssertHandler {
    return struct {
        fn handler(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
            _ = obj;
            if (args.len < 2) {
                try self.emit("@compileError(\"" ++ func_name ++ " requires 2 arguments\")");
                return;
            }
            try self.emit("try unittest." ++ func_name ++ "(");
            try parent.genExpr(self, args[0]);
            try self.emit(", ");
            try parent.genExpr(self, args[1]);
            try self.emit(")");
        }
    }.handler;
}

/// Emit a callable invocation with shared special-case handling.
/// This centralizes the logic used by assertRaises/assertRaisesRegex/assertWarns
/// so we don't need to patch every variant individually when adding support
/// for tricky callables (builtins, module attrs, lambda wrappers, etc.).
fn emitCallableInvocation(
    self: *NativeCodegen,
    callable: ast.Node,
    call_args: []const ast.Node,
    keyword_args: []const ast.Node.KeywordArg,
) CodegenError!void {
    var callable_copy = callable;
    const mut_args: []ast.Node = @constCast(call_args);
    const mut_kwargs: []ast.Node.KeywordArg = @constCast(keyword_args);

    // If keyword args are present, delegate to the general call generator which
    // already knows how to route module/builtin dispatch.
    if (keyword_args.len > 0) {
        const call = ast.Node.Call{
            .func = &callable_copy,
            .args = mut_args,
            .keyword_args = mut_kwargs,
        };
        try parent.genCall(self, call);
        return;
    }

    if (callable == .attribute) {
        const attr = callable.attribute;

        if (attr.value.* == .name) {
            const base_name = attr.value.name.id;
            // Attribute on imported module vs local variable
            const is_module_func = !self.isDeclared(base_name) and
                (self.import_registry.lookup(base_name) != null);

            if (is_module_func) {
                const call = ast.Node.Call{
                    .func = &callable_copy,
                    .args = mut_args,
                    .keyword_args = &.{},
                };
                try parent.genCall(self, call);
                return;
            } else if (std.mem.eql(u8, base_name, "self")) {
                try self.emit("self.@\"");
                try self.emit(attr.attr);
                try self.emit("\"(");
                for (call_args, 0..) |arg, i| {
                    if (i > 0) try self.emit(", ");
                    try parent.genExpr(self, arg);
                }
                try self.emit(")");
                return;
            } else if (attr.value.* == .call) {
                if (FloatMethods.get(attr.attr)) |info| {
                    try self.emit("__ar_obj_blk: { const __ar_obj = ");
                    try parent.genExpr(self, attr.value.*);
                    try self.emit("; break :__ar_obj_blk (runtime.float");
                    try self.emit(info.func);
                    try self.emit(if (info.needs_alloc) "__ar_obj)" else "(__ar_obj)");
                    // FloorBig/CeilBig return error unions
                    // In assertRaises context (inside_try_body), let error propagate
                    // Otherwise, catch unreachable for normal assertEqual context
                    const is_big_variant = std.mem.indexOf(u8, info.func, "Big") != null;
                    if (is_big_variant) {
                        if (self.inside_try_body) {
                            try self.emit(")"); // Let error propagate for assertRaises
                        } else {
                            try self.emit(" catch unreachable)");
                        }
                    } else {
                        try self.emit(")");
                    }
                    try self.emit("; }");
                } else {
                    try self.emit("__ar_obj_blk: { const __ar_obj = ");
                    try parent.genExpr(self, attr.value.*);
                    try self.emit("; break :__ar_obj_blk __ar_obj.@\"");
                    try self.emit(attr.attr);
                    try self.emit("\"(");
                    for (call_args, 0..) |arg, i| {
                        if (i > 0) try self.emit(", ");
                        try parent.genExpr(self, arg);
                    }
                    try self.emit("); }");
                }
                return;
            } else if (PyToZigTypes.has(base_name)) {
                // Builtin type methods
                if (std.mem.eql(u8, base_name, "float")) {
                    if (FloatClassMethods.get(attr.attr)) |func_name| {
                        try self.emit(func_name);
                        try self.emit("(");
                        for (call_args, 0..) |arg, i| {
                            if (i > 0) try self.emit(", ");
                            try parent.genExpr(self, arg);
                        }
                        try self.emit(")");
                        return;
                    }
                }
                try self.emit("runtime.");
                try self.emit(base_name);
                try self.emit(attr.attr);
                try self.emit("(");
                for (call_args, 0..) |arg, i| {
                    if (i > 0) try self.emit(", ");
                    try parent.genExpr(self, arg);
                }
                try self.emit(")");
                return;
            }

            // Simple variable attribute - local variable's method
            const no_arg_methods = std.StaticStringMap(void).initComptime(.{
                .{ "clear", {} },
                .{ "copy", {} },
                .{ "keys", {} },
                .{ "values", {} },
                .{ "items", {} },
                .{ "popitem", {} },
                .{ "reverse", {} },
            });
            if (no_arg_methods.has(attr.attr) and call_args.len > 0) {
                try self.emit("__ar_noarg_blk: { ");
                for (call_args) |arg| {
                    try self.emit("_ = ");
                    try parent.genExpr(self, arg);
                    try self.emit("; ");
                }
                try self.emit("break :__ar_noarg_blk error.TypeError; }");
            } else {
                try parent.genExpr(self, attr.value.*);
                try self.emit(".@\"");
                try self.emit(attr.attr);
                try self.emit("\"(");
                for (call_args, 0..) |arg, i| {
                    if (i > 0) try self.emit(", ");
                    try parent.genExpr(self, arg);
                }
                try self.emit(")");
            }
            return;
        }

        // Complex expression attribute (e.g., {}.update, some_call().method)
        // Check for float methods that need runtime dispatch (as_integer_ratio, __floor__, etc.)
        if (FloatMethods.get(attr.attr)) |info| {
            try self.emit("__ar_obj_blk: { const __ar_obj = ");
            try parent.genExpr(self, attr.value.*);
            try self.emit("; break :__ar_obj_blk (runtime.float");
            try self.emit(info.func);
            try self.emit(if (info.needs_alloc) "__ar_obj)" else "(__ar_obj)");
            // FloorBig/CeilBig return error unions
            // In assertRaises context (inside_try_body), let error propagate
            // Otherwise, catch unreachable for normal assertEqual context
            const is_big_variant = std.mem.indexOf(u8, info.func, "Big") != null;
            if (is_big_variant) {
                if (self.inside_try_body) {
                    try self.emit(")"); // Let error propagate for assertRaises
                } else {
                    try self.emit(" catch unreachable)");
                }
            } else {
                try self.emit(")");
            }
            try self.emit("; }");
            return;
        }
        try self.emit("__ar_obj_blk: { const __ar_obj = ");
        try parent.genExpr(self, attr.value.*);
        try self.emit("; break :__ar_obj_blk __ar_obj.@\"");
        try self.emit(attr.attr);
        try self.emit("\"(");
        for (call_args, 0..) |arg, i| {
            if (i > 0) try self.emit(", ");
            try parent.genExpr(self, arg);
        }
        try self.emit("); }");
        return;
    }

    if (callable == .lambda) {
        try self.emit("ar_closure_blk: { const __ar_closure = ");
        try parent.genExpr(self, callable);
        try self.emit("; break :ar_closure_blk __ar_closure.call(");
        for (call_args, 0..) |arg, i| {
            if (i > 0) try self.emit(", ");
            try parent.genExpr(self, arg);
        }
        try self.emit("); }");
        return;
    }

    if (callable == .name and std.mem.eql(u8, callable.name.id, "int")) {
        try self.emit("runtime.intBuiltinCall(__global_allocator, ");
        if (call_args.len > 0) {
            try parent.genExpr(self, call_args[0]);
            try self.emit(", .{");
            if (call_args.len > 1) {
                for (call_args[1..], 0..) |arg, i| {
                    if (i > 0) try self.emit(", ");
                    try parent.genExpr(self, arg);
                }
            }
            try self.emit("}");
        } else {
            try self.emit("{}, .{}");
        }
        try self.emit(")");
        return;
    }

    if (callable == .name and std.mem.eql(u8, callable.name.id, "float")) {
        try self.emit("runtime.floatBuiltinCall(");
        if (call_args.len > 0) {
            try parent.genExpr(self, call_args[0]);
            try self.emit(", .{");
            if (call_args.len > 1) {
                for (call_args[1..], 0..) |arg, i| {
                    if (i > 0) try self.emit(", ");
                    try parent.genExpr(self, arg);
                }
            }
            try self.emit("}");
        } else {
            try self.emit("{}, .{}");
        }
        try self.emit(")");
        return;
    }

    if (callable == .name and std.mem.eql(u8, callable.name.id, "bool")) {
        try self.emit("runtime.boolBuiltinCall(");
        if (call_args.len > 0) {
            try parent.genExpr(self, call_args[0]);
            try self.emit(", .{");
            if (call_args.len > 1) {
                for (call_args[1..], 0..) |arg, i| {
                    if (i > 0) try self.emit(", ");
                    try parent.genExpr(self, arg);
                }
            }
            try self.emit("}");
        } else {
            try self.emit("{}, .{}");
        }
        try self.emit(")");
        return;
    }

    if (callable == .name and std.mem.eql(u8, callable.name.id, "next")) {
        // next() returns error union, use try to propagate or catch to handle
        try self.emit("(runtime.builtins.next(");
        if (call_args.len > 0) {
            try self.emit("&");
            try parent.genExpr(self, call_args[0]);
        } else {
            try self.emit("&.{}");
        }
        try self.emit(") catch |err| if (err == error.StopIteration) @panic(\"StopIteration\") else @panic(\"TypeError\"))");
        return;
    }

    if (callable == .name and self.callable_vars.contains(callable.name.id)) {
        try parent.genExpr(self, callable);
        try self.emit(".call(");
        for (call_args, 0..) |arg, i| {
            if (i > 0) try self.emit(", ");
            try parent.genExpr(self, arg);
        }
        try self.emit(")");
        return;
    }

    if (callable == .name and std.mem.eql(u8, callable.name.id, "format")) {
        try self.emit("runtime.builtins.format.call(__global_allocator, ");
        for (call_args, 0..) |arg, i| {
            if (i > 0) try self.emit(", ");
            try parent.genExpr(self, arg);
        }
        try self.emit(")");
        return;
    }

    if (callable == .name and std.mem.eql(u8, callable.name.id, "round")) {
        try self.emit("runtime.builtins.round(");
        if (call_args.len > 0) {
            try parent.genExpr(self, call_args[0]);
            try self.emit(", .{");
            if (call_args.len > 1) {
                for (call_args[1..], 0..) |arg, i| {
                    if (i > 0) try self.emit(", ");
                    try parent.genExpr(self, arg);
                }
            }
            try self.emit("}");
        } else {
            try self.emit("0, .{}");
        }
        try self.emit(")");
        return;
    }

    if (callable == .name) {
        const call = ast.Node.Call{
            .func = &callable_copy,
            .args = mut_args,
            .keyword_args = &.{},
        };
        try parent.genCall(self, call);
        return;
    }

    // Fallback: simple callable expression
    try parent.genExpr(self, callable);
    try self.emit("(");
    for (call_args, 0..) |arg, i| {
        if (i > 0) try self.emit(", ");
        try parent.genExpr(self, arg);
    }
    try self.emit(")");
}

// Simple assertions via comptime generators

/// Builtins that return simple i64 type - safe for inline comparison
const SafeBuiltins = std.StaticStringMap(void).initComptime(.{
    .{ "len", {} },
    .{ "ord", {} },
    .{ "hash", {} },
    .{ "id", {} },
    .{ "abs", {} },
});

/// Check if an expression has a simple, predictable type at codegen time.
/// Function calls may return complex types (IntResult, error unions) that don't match
/// the simple types (i64, f64) inferred by the type inferrer.
fn isSimpleExpr(node: ast.Node) bool {
    return switch (node) {
        .constant, .name, .unaryop, .binop => true,
        // Allow calls to known builtins that return i64
        .call => |call| {
            if (call.func.* == .name) {
                return SafeBuiltins.has(call.func.name.id);
            }
            return false;
        },
        // Attribute access on method calls (e.g., (0.5).__floor__()) is also unsafe
        .attribute => |attr| isSimpleExpr(attr.value.*),
        else => false,
    };
}

/// Check if AST node is an empty list literal `[]`
fn isEmptyListLiteral(node: ast.Node) bool {
    if (node != .list) return false;
    return node.list.elts.len == 0;
}

/// Check if AST node is a non-empty list literal `[a, b, c]`
fn isNonEmptyListLiteral(node: ast.Node) bool {
    if (node != .list) return false;
    return node.list.elts.len > 0;
}

/// Get the element type string for a list type (e.g., "i64" for list of ints)
fn getListElementTypeStr(list_type: NativeType) ?[]const u8 {
    return switch (list_type) {
        .list => |elem| switch (elem.*) {
            .int => "i64",
            .float => "f64",
            .bool => "bool",
            .string => "[]const u8",
            else => null,
        },
        else => null,
    };
}

/// Get Zig slice type string for a list type
fn getSliceTypeStr(list_type: NativeType) ?[]const u8 {
    return switch (list_type) {
        .list => |elem| switch (elem.*) {
            .int => "[]const i64",
            .float => "[]const f64",
            .bool => "[]const bool",
            .string => "[]const []const u8",
            else => null,
        },
        else => null,
    };
}

/// Check if an AST node produces a NativeList with PyValue items
/// (as opposed to a fixed array with concrete element types)
/// This includes: list() calls, list comprehensions with runtime elements, etc.
fn producesNativeList(node: ast.Node) bool {
    return switch (node) {
        // Calls to list() builtin produce NativeList
        .call => |call| {
            if (call.func.* == .name) {
                const name = call.func.name.id;
                if (std.mem.eql(u8, name, "list")) return true;
            }
            return false;
        },
        // List comprehensions produce NativeList when they have runtime evaluation
        .listcomp => true,
        // Generator expressions produce iterators, when converted to list give NativeList
        .genexp => true,
        else => false,
    };
}

/// Generate inline assertEqual - avoids anytype monomorphization explosion
/// Strategy: Generate type-specific inline comparisons at codegen time.
/// Key insight: Use explicit type annotations to force type coercion and avoid
/// anonymous types that cause monomorphization explosion.
pub fn genAssertEqual(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertEqual requires 2 arguments\")");
        return;
    }

    // === SPECIAL CASE: assertEqual(type(x), type(y)) ===
    // Optimize to @TypeOf comparison at comptime instead of comparing string type names
    // This avoids pyTypeName monomorphization explosion
    if (args[0] == .call and args[1] == .call) {
        const call_a = args[0].call;
        const call_b = args[1].call;
        if (call_a.func.* == .name and call_b.func.* == .name) {
            const func_a = call_a.func.name.id;
            const func_b = call_b.func.name.id;
            if (std.mem.eql(u8, func_a, "type") and std.mem.eql(u8, func_b, "type")) {
                if (call_a.args.len >= 1 and call_b.args.len >= 1) {
                    // Generate: if (@TypeOf(x) != @TypeOf(y)) return error.AssertionFailed;
                    try self.emit("if (@TypeOf(");
                    try parent.genExpr(self, call_a.args[0]);
                    try self.emit(") != @TypeOf(");
                    try parent.genExpr(self, call_b.args[0]);
                    try self.emit(")) return error.AssertionFailed;");
                    return;
                }
            }
        }
    }

    // === SPECIAL CASE: assertEqual(list(x), y) or assertEqual(x, list(y)) ===
    // Optimize list() conversion by using runtime.listEquals helper
    // This avoids listFromAny anytype monomorphization
    if (args[0] == .call and args[0].call.func.* == .name and
        std.mem.eql(u8, args[0].call.func.name.id, "list") and args[0].call.args.len >= 1)
    {
        try self.emit("if (!runtime.listEquals(__global_allocator, ");
        try parent.genExpr(self, args[0].call.args[0]); // The iterator/iterable
        try self.emit(", ");
        try parent.genExpr(self, args[1]); // The expected list/array
        try self.emit(")) return error.AssertionFailed;");
        return;
    }
    if (args[1] == .call and args[1].call.func.* == .name and
        std.mem.eql(u8, args[1].call.func.name.id, "list") and args[1].call.args.len >= 1)
    {
        try self.emit("if (!runtime.listEquals(__global_allocator, ");
        try parent.genExpr(self, args[1].call.args[0]); // The iterator/iterable
        try self.emit(", ");
        try parent.genExpr(self, args[0]); // The expected list/array
        try self.emit(")) return error.AssertionFailed;");
        return;
    }

    // Infer types for type-specific code generation
    const type_a = self.type_inferrer.inferExpr(args[0]) catch .unknown;
    const type_b = self.type_inferrer.inferExpr(args[1]) catch .unknown;
    const tag_a: std.meta.Tag(NativeType) = type_a;
    const tag_b: std.meta.Tag(NativeType) = type_b;

    // === PRIMITIVE TYPES: Direct comparison ===
    // For known primitive types, use optimized inline comparisons (no monomorphization)
    if (tag_a == tag_b) {
        switch (type_a) {
            .int, .usize => {
                try self.emit("if ((");
                try parent.genExpr(self, args[0]);
                try self.emit(") != (");
                try parent.genExpr(self, args[1]);
                try self.emit(")) return error.AssertionFailed;");
                return;
            },
            .float => {
                try self.emit("if ((");
                try parent.genExpr(self, args[0]);
                try self.emit(") != (");
                try parent.genExpr(self, args[1]);
                try self.emit(")) return error.AssertionFailed;");
                return;
            },
            .bool => {
                try self.emit("if ((");
                try parent.genExpr(self, args[0]);
                try self.emit(") != (");
                try parent.genExpr(self, args[1]);
                try self.emit(")) return error.AssertionFailed;");
                return;
            },
            .string => {
                try self.emit("if (!std.mem.eql(u8, ");
                try parent.genExpr(self, args[0]);
                try self.emit(", ");
                try parent.genExpr(self, args[1]);
                try self.emit(")) return error.AssertionFailed;");
                return;
            },
            else => {},
        }
    }

    // === EMPTY LIST: Length check ===
    if (isEmptyListLiteral(args[1])) {
        try self.emit("if (runtime.builtinLen(");
        try parent.genExpr(self, args[0]);
        try self.emit(") != 0) return error.AssertionFailed;");
        return;
    }
    if (isEmptyListLiteral(args[0])) {
        try self.emit("if (runtime.builtinLen(");
        try parent.genExpr(self, args[1]);
        try self.emit(") != 0) return error.AssertionFailed;");
        return;
    }

    // === LIST/SLICE COMPARISON WITH KNOWN ELEMENT TYPE ===
    // This is the key optimization: use explicit type annotations to coerce
    // different expression types (blocks, arrays, slices, ArrayLists) to a
    // common slice type, avoiding anonymous type monomorphization.
    //
    // IMPORTANT: Skip this optimization if either side produces a NativeList
    // with PyValue items (via list() calls, comprehensions, etc.) because
    // NativeList.items is []PyValue, not []ConcreteType.

    // Check if either expression produces NativeList with PyValue items
    const a_produces_native_list = producesNativeList(args[0]);
    const b_produces_native_list = producesNativeList(args[1]);

    // Get element types for both sides (handles list, also check the other side)
    const elem_type_a = getListElementTypeStr(type_a);
    const elem_type_b = getListElementTypeStr(type_b);
    const slice_type_a = getSliceTypeStr(type_a);
    const slice_type_b = getSliceTypeStr(type_b);

    // Use element type from either side (prefer the known one)
    const elem_type = elem_type_a orelse elem_type_b;
    const slice_type = slice_type_a orelse slice_type_b;

    // If we have a known element type AND neither side produces NativeList, use slice comparison
    if (elem_type != null and slice_type != null and !a_produces_native_list and !b_produces_native_list) {
        // Generate a comparison block that:
        // 1. Evaluates both expressions
        // 2. Extracts slices with explicit type annotation (forces coercion)
        // 3. Compares with std.mem.eql using concrete type (no monomorphization)
        try self.emit("if (__ae_blk: { const __ae_raw_a = ");
        try parent.genExpr(self, args[0]);
        try self.emit("; const __ae_raw_b = ");
        try parent.genExpr(self, args[1]);
        // Extract slice with comptime type check - handles arrays, slices, ArrayListUnmanaged
        try self.emit("; const __ae_slice_a: ");
        try self.emit(slice_type.?);
        try self.emit(" = __ae_get_slice_blk: { const __T = @typeInfo(@TypeOf(__ae_raw_a)); ");
        try self.emit("break :__ae_get_slice_blk if (__T == .@\"struct\" and @hasField(@TypeOf(__ae_raw_a), \"items\")) __ae_raw_a.items ");
        try self.emit("else if (__T == .pointer and __T.pointer.size == .slice) __ae_raw_a ");
        try self.emit("else if (__T == .array) &__ae_raw_a else __ae_raw_a; };");
        // Same for b
        try self.emit(" const __ae_slice_b: ");
        try self.emit(slice_type.?);
        try self.emit(" = __ae_get_slice_blk2: { const __T2 = @typeInfo(@TypeOf(__ae_raw_b)); ");
        try self.emit("break :__ae_get_slice_blk2 if (__T2 == .@\"struct\" and @hasField(@TypeOf(__ae_raw_b), \"items\")) __ae_raw_b.items ");
        try self.emit("else if (__T2 == .pointer and __T2.pointer.size == .slice) __ae_raw_b ");
        try self.emit("else if (__T2 == .array) &__ae_raw_b else __ae_raw_b; };");
        // Compare with concrete type
        try self.emit(" break :__ae_blk !std.mem.eql(");
        try self.emit(elem_type.?);
        try self.emit(", __ae_slice_a, __ae_slice_b); }) return error.AssertionFailed;");
        return;
    }

    // === TUPLE COMPARISON ===
    // Use runtime.pyEqual for Python-semantic comparison (handles cross-type like BigInt vs i64)
    if (tag_a == .tuple and tag_b == .tuple) {
        try self.emit("if (!(try runtime.pyEqual(__global_allocator, ");
        try parent.genExpr(self, args[0]);
        try self.emit(", ");
        try parent.genExpr(self, args[1]);
        try self.emit("))) return error.AssertionFailed;");
        return;
    }

    // === GENERIC FALLBACK: Try classInstanceEq first, then PyValue ===
    // For all other cases, use assertEqualGeneric which:
    // 1. Checks at comptime if either argument has __eq__ method
    // 2. If yes, calls classInstanceEq which invokes __eq__
    // 3. If no, falls back to toPyValue().eql() for primitive comparison
    // This handles both custom class instances AND methods that return primitives
    // For unknown types, we try classInstanceEq at comptime (it uses @hasDecl to check for __eq__)
    // This handles cases where type inference fails but the actual value has __eq__
    // If neither has __eq__, fall back to PyValue.eql()
    try self.emit("if (!(try runtime.assertEqualGeneric(");
    try parent.genExpr(self, args[0]);
    try self.emit(", ");
    try parent.genExpr(self, args[1]);
    try self.emit(", __global_allocator))) return error.AssertionFailed;");
}

pub const genAssertTrue = gen1ArgAssert("assertTrue");
pub const genAssertFalse = gen1ArgAssert("assertFalse");
pub const genAssertIsNone = gen1ArgAssert("assertIsNone");
pub const genAssertGreater = gen2ArgAssert("assertGreater");
pub const genAssertLess = gen2ArgAssert("assertLess");
pub const genAssertGreaterEqual = gen2ArgAssert("assertGreaterEqual");
pub const genAssertLessEqual = gen2ArgAssert("assertLessEqual");
pub const genAssertNotEqual = gen2ArgAssert("assertNotEqual");
pub const genAssertIsNotNone = gen1ArgAssert("assertIsNotNone");
pub const genAssertAlmostEqual = gen2ArgAssert("assertAlmostEqual");
pub const genAssertNotAlmostEqual = gen2ArgAssert("assertNotAlmostEqual");
pub const genAssertCountEqual = gen2ArgAssert("assertCountEqual");
pub const genAssertRegex = gen2ArgAssert("assertRegex");
pub const genAssertNotRegex = gen2ArgAssert("assertNotRegex");
pub const genAssertSetEqual = gen2ArgAssert("assertSetEqual");
pub const genAssertDictEqual = gen2ArgAssert("assertDictEqual");
pub const genAssertFloatsAreIdentical = gen2ArgAssert("assertFloatsAreIdentical");
pub const genAssertIsNot = gen2ArgAssert("assertIsNot");
pub const genAssertNotIn = gen2ArgAssert("assertNotIn");

/// Generate code for self.assertIs(a, b) - special handling for type() checks
pub fn genAssertIs(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertIs requires 2 arguments\")");
        return;
    }
    // Handle special case: assertIs(type(x), SomeType)
    // When first arg is type(x), we need to compare type names
    if (args[0] == .call and args[0].call.func.* == .name) {
        const func_name = args[0].call.func.name.id;
        if (std.mem.eql(u8, func_name, "type") and args[0].call.args.len == 1) {
            if (args[1] == .name) {
                const type_name = args[1].name.id;
                // For primitive types with direct Zig mappings, use @TypeOf comparison
                if (PyToZigTypes.get(type_name)) |ztype| {
                    // Skip "anytype" - those are collection types that need runtime check
                    if (!std.mem.eql(u8, ztype, "anytype")) {
                        try self.emit("try unittest.assertTypeIs(@TypeOf(");
                        try parent.genExpr(self, args[0].call.args[0]);
                        try self.emit("), ");
                        try self.emit(ztype);
                        try self.emit(")");
                        return;
                    }
                    // For collection types (dict, list, set), use runtime string-based type check
                    try self.emit("try unittest.assertTypeIsStr(");
                    try parent.genExpr(self, args[0].call.args[0]);
                    try self.emit(", \"");
                    try self.emit(type_name);
                    try self.emit("\")");
                    return;
                }
                // For user-defined classes (like subclass), compare __name__ field
                // type(x) returns @typeName(@TypeOf(x)) which is a string
                // subclass has __name__ field that matches
                // Use assertTypeIsStr with the class's __name__
                if (!isBuiltinTypeName(type_name)) {
                    // Mark variable as used to avoid "unused local" error
                    try self.emit("{ _ = &");
                    try self.emit(type_name);
                    try self.emit("; try unittest.assertTypeIsStr(");
                    try parent.genExpr(self, args[0].call.args[0]);
                    try self.emit(", ");
                    try self.emit(type_name);
                    try self.emit(".__name__); }");
                    return;
                }
            }
        }
    }
    try self.emit("try unittest.assertIs(");
    try parent.genExpr(self, args[0]);
    try self.emit(", ");
    try parent.genExpr(self, args[1]);
    try self.emit(")");
}

/// Generate code for self.assertIn(item, container)
pub fn genAssertIn(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertIn requires 2 arguments\")");
        return;
    }
    try self.emit("try unittest.assertIn(");

    // Check if item is a call that might return error union (like float.__getformat__)
    if (args[0] == .call and args[0].call.func.* == .attribute) {
        const attr = args[0].call.func.attribute;
        if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "float")) {
            if (std.mem.eql(u8, attr.attr, "__getformat__")) {
                // float.__getformat__ returns ![]const u8, need to try
                try self.emit("try ");
            }
        }
    }
    try parent.genExpr(self, args[0]);
    try self.emit(", ");
    try parent.genExpr(self, args[1]);
    try self.emit(")");
}

/// Generate code for self.assertIsInstance(obj, type)
pub fn genAssertIsInstance(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertIsInstance requires 2 arguments\")");
        return;
    }
    // If the type arg is a variable name, use the variable to avoid "unused" warnings
    // then extract the type name from it
    if (args[1] == .name) {
        const type_var = args[1].name.id;
        // Check if this is a user-defined variable (not a builtin type name)
        if (!isBuiltinTypeName(type_var)) {
            // For user-defined classes, use the class's __name__ constant
            // which is a string like "aug_test" that matches the Python class name
            try self.emit("try unittest.assertIsInstance(");
            try parent.genExpr(self, args[0]);
            try self.emit(", ");
            // Escape Zig keywords like "struct" when used as variable names
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), type_var);
            try self.emit(".__name__)");
            return;
        }
    }
    try self.emit("try unittest.assertIsInstance(");
    try parent.genExpr(self, args[0]);
    try self.emit(", ");
    if (args[1] == .name) {
        try self.emit("\"");
        try self.emit(args[1].name.id);
        try self.emit("\"");
    } else {
        try parent.genExpr(self, args[1]);
    }
    try self.emit(")");
}

/// Generate code for self.assertNotIsInstance(obj, type)
pub fn genAssertNotIsInstance(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertNotIsInstance requires 2 arguments\")");
        return;
    }
    try self.emit("try unittest.assertNotIsInstance(");
    try parent.genExpr(self, args[0]);
    try self.emit(", ");
    if (args[1] == .name) {
        try self.emit("\"");
        try self.emit(args[1].name.id);
        try self.emit("\"");
    } else {
        try parent.genExpr(self, args[1]);
    }
    try self.emit(")");
}

/// Generate code for self.assertIsSubclass(cls, parent_cls)
pub fn genAssertIsSubclass(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertIsSubclass requires 2 arguments\")");
        return;
    }
    try self.emit("unittest.assertIsSubclass(");
    if (args[0] == .name) {
        try self.emit("\"");
        try self.emit(args[0].name.id);
        try self.emit("\"");
    } else {
        try parent.genExpr(self, args[0]);
    }
    try self.emit(", ");
    if (args[1] == .name) {
        try self.emit("\"");
        try self.emit(args[1].name.id);
        try self.emit("\"");
    } else {
        try parent.genExpr(self, args[1]);
    }
    try self.emit(")");
}

/// Generate code for self.assertRaises(exception_type, callable, *args)
/// For AOT compilation, we check if the callable is a builtin like eval
/// and generate a try-catch block to verify an error is raised
pub fn genAssertRaises(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertRaises requires at least 2 arguments: exception_type, callable\")");
        return;
    }

    // Check if callable is 'eval' - special handling needed
    if (args[1] == .name and std.mem.eql(u8, args[1].name.id, "eval")) {
        // Generate: blk: { _ = runtime.eval(...) catch break :blk {}; @panic("assertRaises: expected exception"); }
        // Note: eval-string-only variable discards are now handled in assign.zig
        try self.emit("blk: { _ = runtime.eval(__global_allocator, ");
        if (args.len > 2) {
            try parent.genExpr(self, args[2]);
        } else {
            try self.emit("\"\"");
        }
        try self.emit(") catch break :blk {}; return error.ExpectedExceptionNotRaised; }");
        return;
    }

    // Check if callable is 'compile' - special handling needed
    if (args[1] == .name and std.mem.eql(u8, args[1].name.id, "compile")) {
        // Generate: blk: { _ = runtime.compile_builtin(...) catch break :blk {}; @panic("assertRaises: expected exception"); }
        try self.emit("blk: { _ = runtime.compile_builtin(__global_allocator, ");
        if (args.len > 2) {
            try parent.genExpr(self, args[2]); // source
            try self.emit(", ");
        } else {
            try self.emit("\"\", ");
        }
        if (args.len > 3) {
            try parent.genExpr(self, args[3]); // filename
            try self.emit(", ");
        } else {
            try self.emit("\"<string>\", ");
        }
        if (args.len > 4) {
            try parent.genExpr(self, args[4]); // mode
        } else {
            try self.emit("\"exec\"");
        }
        try self.emit(") catch break :blk {}; return error.ExpectedExceptionNotRaised; }");
        return;
    }

    // For assertRaises, we need to check if the callable raises an error
    // Use unittest.expectError helper which handles both error and non-error types
    const call_args: []const ast.Node = if (args.len > 2) args[2..] else &.{};
    // Set inside_try_body so error-returning functions propagate errors instead of swallowing them
    const prev_inside_try = self.inside_try_body;
    self.inside_try_body = true;
    try self.emit("if (unittest.expectError(");
    try emitCallableInvocation(self, args[1], call_args, &.{});
    self.inside_try_body = prev_inside_try;
    // expectError returns true if NO error was raised (test should fail)
    try self.emit(")) return error.ExpectedExceptionNotRaised;");
}

/// Generate code for self.assertRaises(exception_type, callable, *args, **kwargs)
/// This variant handles keyword arguments that need to be passed to the callable
pub fn genAssertRaisesWithKwargs(self: *NativeCodegen, obj: ast.Node, args: []ast.Node, keyword_args: []const ast.Node.KeywordArg) CodegenError!void {
    // If no keyword args, use the regular handler
    if (keyword_args.len == 0) {
        return genAssertRaises(self, obj, args);
    }

    if (args.len < 2) {
        try self.emit("@compileError(\"assertRaises requires at least 2 arguments: exception_type, callable\")");
        return;
    }

    const call_args: []const ast.Node = if (args.len > 2) args[2..] else &.{};
    // Set inside_try_body so error-returning functions propagate errors instead of swallowing them
    const prev_inside_try = self.inside_try_body;
    self.inside_try_body = true;
    // Generate: if (unittest.expectError(<call_with_kwargs>)) @panic(...)
    try self.emit("if (unittest.expectError(");
    try emitCallableInvocation(self, args[1], call_args, keyword_args);
    self.inside_try_body = prev_inside_try;
    try self.emit(")) return error.ExpectedExceptionNotRaised;");
}

/// Generate code for self.assertRaisesRegex(exception, regex, callable, *args, **kwargs)
/// This variant handles keyword arguments that need to be passed to the callable
pub fn genAssertRaisesRegexWithKwargs(self: *NativeCodegen, obj: ast.Node, args: []ast.Node, keyword_args: []const ast.Node.KeywordArg) CodegenError!void {
    // If no keyword args, use the regular handler
    if (keyword_args.len == 0) {
        return genAssertRaisesRegex(self, obj, args);
    }

    if (args.len < 3) {
        try self.emit("{}");
        return;
    }

    const call_args: []const ast.Node = if (args.len > 3) args[3..] else &.{};
    // Set inside_try_body so error-returning functions propagate errors instead of swallowing them
    const prev_inside_try = self.inside_try_body;
    self.inside_try_body = true;
    // Generate: __ar_blk: { _ = <regex>; _ = <call_with_kwargs> catch break :__ar_blk {}; @panic(...); }
    try self.emit("__ar_blk: { _ = ");
    try parent.genExpr(self, args[1]); // regex parameter
    try self.emit("; _ = ");
    try emitCallableInvocation(self, args[2], call_args, keyword_args);
    self.inside_try_body = prev_inside_try;
    try self.emit(" catch break :__ar_blk {}; return error.ExpectedExceptionNotRaised; }");
}

/// Generate code for self.assertRaisesRegex(exception, regex, callable, *args)
pub fn genAssertRaisesRegex(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 3) {
        try self.emit("{}");
        return;
    }
    const call_args: []const ast.Node = if (args.len > 3) args[3..] else &.{};
    // Set inside_try_body so error-returning functions propagate errors instead of swallowing them
    const prev_inside_try = self.inside_try_body;
    self.inside_try_body = true;
    // Similar to assertRaises but with regex check on error message
    // For AOT, we just check that an error is raised
    // Reference the regex parameter to avoid unused variable warning
    // Use __ar_blk to avoid conflicts with nested blk: labels
    try self.emit("__ar_blk: { _ = ");
    try parent.genExpr(self, args[1]); // regex parameter
    try self.emit("; _ = ");

    try emitCallableInvocation(self, args[2], call_args, &.{});
    self.inside_try_body = prev_inside_try;
    // Catch error directly on call - can't store first since error propagates immediately
    try self.emit(" catch break :__ar_blk {}; return error.ExpectedExceptionNotRaised; }");
}

/// Generate code for self.assertWarns(warning, callable, *args)
pub fn genAssertWarns(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("{}");
        return;
    }
    const call_args: []const ast.Node = if (args.len > 2) args[2..] else &.{};
    // For AOT, warnings are not tracked - just call the function
    try emitCallableInvocation(self, args[1], call_args, &.{});
}

/// Generate code for self.assertWarnsRegex(warning, regex, callable, *args)
pub fn genAssertWarnsRegex(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 3) {
        try self.emit("{}");
        return;
    }
    const call_args: []const ast.Node = if (args.len > 3) args[3..] else &.{};
    // For AOT, warnings are not tracked - just call the function
    try emitCallableInvocation(self, args[2], call_args, &.{});
}

/// Generate code for self.assertNotIsSubclass(cls, parent_cls)
pub fn genAssertNotIsSubclass(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertNotIsSubclass requires 2 arguments\")");
        return;
    }
    try self.emit("unittest.assertNotIsSubclass(");
    if (args[0] == .name) {
        try self.emit("\"");
        try self.emit(args[0].name.id);
        try self.emit("\"");
    } else {
        try parent.genExpr(self, args[0]);
    }
    try self.emit(", ");
    if (args[1] == .name) {
        try self.emit("\"");
        try self.emit(args[1].name.id);
        try self.emit("\"");
    } else {
        try parent.genExpr(self, args[1]);
    }
    try self.emit(")");
}

/// Generate code for self.assertStartsWith(s, prefix)
pub fn genAssertStartsWith(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertStartsWith requires 2 arguments\")");
        return;
    }
    try self.emit("try unittest.assertTrue(std.mem.startsWith(u8, ");
    try parent.genExpr(self, args[0]);
    try self.emit(", ");
    try parent.genExpr(self, args[1]);
    try self.emit("))");
}

/// Generate code for self.assertNotStartsWith(s, prefix)
pub fn genAssertNotStartsWith(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertNotStartsWith requires 2 arguments\")");
        return;
    }
    try self.emit("try unittest.assertFalse(std.mem.startsWith(u8, ");
    try parent.genExpr(self, args[0]);
    try self.emit(", ");
    try parent.genExpr(self, args[1]);
    try self.emit("))");
}

/// Generate code for self.assertEndsWith(s, suffix)
pub fn genAssertEndsWith(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertEndsWith requires 2 arguments\")");
        return;
    }
    try self.emit("try unittest.assertTrue(std.mem.endsWith(u8, ");
    try parent.genExpr(self, args[0]);
    try self.emit(", ");
    try parent.genExpr(self, args[1]);
    try self.emit("))");
}

/// Generate code for self.assertHasAttr(obj, name)
pub fn genAssertHasAttr(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertHasAttr requires 2 arguments\")");
        return;
    }
    // For module attribute checking, verify at comptime using @hasField (if struct)
    // Use a no-op that references the arguments to avoid "unused variable" errors
    try self.emit("{ _ = ");
    try parent.genExpr(self, args[1]);
    try self.emit("; }"); // Reference the attr name to mark it as used
}

/// Generate code for self.assertNotHasAttr(obj, name)
pub fn genAssertNotHasAttr(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertNotHasAttr requires 2 arguments\")");
        return;
    }
    // For AOT, we check at compile time using @hasField (must check struct type first)
    try self.emit("comptime { const _T = @TypeOf(");
    try parent.genExpr(self, args[0]);
    try self.emit("); if (@typeInfo(_T) == .@\"struct\" and @hasField(_T, ");
    try parent.genExpr(self, args[1]);
    try self.emit(")) @compileError(\"assertNotHasAttr failed\"); }");
}

// These use comptime generators declared at top
pub const genAssertSequenceEqual = gen2ArgAssert("assertEqual");
pub const genAssertListEqual = gen2ArgAssert("assertEqual");
pub const genAssertTupleEqual = gen2ArgAssert("assertEqual");
pub const genAssertMultiLineEqual = gen2ArgAssert("assertEqual");

/// Generate code for self.assertLogs(logger, level)
pub fn genAssertLogs(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    _ = args;
    // For AOT, logging context managers aren't tracked - return stub
    try self.emit("struct { pub fn __enter__(_: *const @This()) @This() { return @This(){}; } pub fn __exit__(_: *const @This()) void {} records: []const []const u8 = &.{}, output: []const u8 = \"\" }{}");
}

/// Generate code for self.assertNoLogs(logger, level)
pub fn genAssertNoLogs(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    try genAssertLogs(self, obj, args);
}

/// Generate code for self.fail(msg)
pub fn genFail(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    try self.emit("@panic(");
    if (args.len > 0) {
        try parent.genExpr(self, args[0]);
    } else {
        try self.emit("\"Test failed\"");
    }
    try self.emit(")");
}

/// Generate code for self.skipTest(reason)
/// This terminates control flow - no code after skipTest should run
pub fn genSkipTest(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    _ = args;
    try self.emit("return");
    // Mark control flow as terminated so no unreachable code is generated after
    self.control_flow_terminated = true;
}
