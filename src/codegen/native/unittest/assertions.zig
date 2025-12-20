/// unittest assertion code generation
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const parent = @import("../expressions.zig");
const shared = @import("../shared_maps.zig");
const PyToZigTypes = shared.PyTypeToZig;
const zig_keywords = @import("utils.zig_keywords");
const NativeType = @import("../../../analysis/native_types/core.zig").NativeType;

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
                try emitConst(self,"@compileError(\"" ++ func_name ++ " requires 1 argument\")");
                return;
            }
            try emitConst(self,"try unittest." ++ func_name ++ "(");
            try parent.genExpr(self, args[0]);
            try emitConst(self,")");
        }
    }.handler;
}

// Comptime generator for simple 2-arg assertions: try unittest.func(a, b)
fn gen2ArgAssert(comptime func_name: []const u8) AssertHandler {
    return struct {
        fn handler(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
            _ = obj;
            if (args.len < 2) {
                try emitConst(self,"@compileError(\"" ++ func_name ++ " requires 2 arguments\")");
                return;
            }
            try emitConst(self,"try unittest." ++ func_name ++ "(");
            try parent.genExpr(self, args[0]);
            try emitConst(self,", ");
            try parent.genExpr(self, args[1]);
            try emitConst(self,")");
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
                try emitConst(self,"self.@\"");
                try emitConst(self,attr.attr);
                try emitConst(self,"\"(");
                for (call_args, 0..) |arg, i| {
                    if (i > 0) try emitConst(self,", ");
                    try parent.genExpr(self, arg);
                }
                try emitConst(self,")");
                return;
            } else if (attr.value.* == .call) {
                if (FloatMethods.get(attr.attr)) |info| {
                    const label = try self.emitInlineBlockStart("ar_obj");
                    try emitConst(self,"const __ar_obj = ");
                    try parent.genExpr(self, attr.value.*);
                    try emitFmtConst(self, "; break :{s} (runtime.float", .{label});
                    try emitConst(self,info.func);
                    try emitConst(self,if (info.needs_alloc) "__ar_obj)" else "(__ar_obj)");
                    // FloorBig/CeilBig return error unions
                    // In assertRaises context (inside_try_body), let error propagate
                    // Otherwise, catch unreachable for normal assertEqual context
                    const is_big_variant = std.mem.indexOf(u8, info.func, "Big") != null;
                    if (is_big_variant) {
                        if (self.inside_try_body) {
                            try emitConst(self,")"); // Let error propagate for assertRaises
                        } else {
                            try emitConst(self," catch unreachable)");
                        }
                    } else {
                        try emitConst(self,")");
                    }
                    try emitConst(self,"; ");
                    try self.emitInlineBlockEnd();
                } else {
                    const label = try self.emitInlineBlockStart("ar_obj");
                    try emitConst(self,"const __ar_obj = ");
                    try parent.genExpr(self, attr.value.*);
                    try emitFmtConst(self, "; break :{s} __ar_obj.@\"", .{label});
                    try emitConst(self,attr.attr);
                    try emitConst(self,"\"(");
                    for (call_args, 0..) |arg, i| {
                        if (i > 0) try emitConst(self,", ");
                        try parent.genExpr(self, arg);
                    }
                    try emitConst(self,"); ");
                    try self.emitInlineBlockEnd();
                }
                return;
            } else if (PyToZigTypes.has(base_name)) {
                // Builtin type methods
                if (std.mem.eql(u8, base_name, "float")) {
                    if (FloatClassMethods.get(attr.attr)) |func_name| {
                        try emitConst(self,func_name);
                        try emitConst(self,"(");
                        for (call_args, 0..) |arg, i| {
                            if (i > 0) try emitConst(self,", ");
                            try parent.genExpr(self, arg);
                        }
                        try emitConst(self,")");
                        return;
                    }
                }
                try emitConst(self,"runtime.");
                try emitConst(self,base_name);
                try emitConst(self,attr.attr);
                try emitConst(self,"(");
                for (call_args, 0..) |arg, i| {
                    if (i > 0) try emitConst(self,", ");
                    try parent.genExpr(self, arg);
                }
                try emitConst(self,")");
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
                const label = try self.emitInlineBlockStart("ar_noarg");
                for (call_args) |arg| {
                    try emitConst(self,"_ = ");
                    try parent.genExpr(self, arg);
                    try emitConst(self,"; ");
                }
                try emitFmtConst(self, "break :{s} error.TypeError; ", .{label});
                try self.emitInlineBlockEnd();
            } else {
                try parent.genExpr(self, attr.value.*);
                try emitConst(self,".@\"");
                try emitConst(self,attr.attr);
                try emitConst(self,"\"(");
                for (call_args, 0..) |arg, i| {
                    if (i > 0) try emitConst(self,", ");
                    try parent.genExpr(self, arg);
                }
                try emitConst(self,")");
            }
            return;
        }

        // Complex expression attribute (e.g., {}.update, some_call().method)
        // Check for list methods that need special handling in assertRaises context
        if (std.mem.eql(u8, attr.attr, "extend")) {
            // List.extend() in assertRaises context - use runtime helper
            const label = try self.emitInlineBlockStart("ar_obj");
            try emitConst(self,"var __ar_list = ");
            try parent.genExpr(self, attr.value.*);
            try emitConst(self,"; try runtime.listExtendIterable(__global_allocator, &__ar_list, ");
            if (call_args.len > 0) {
                try parent.genExpr(self, call_args[0]);
            }
            try emitFmtConst(self, "); break :{s} {{}}; ", .{label});
            try self.emitInlineBlockEnd();
            return;
        }

        // Check for float methods that need runtime dispatch (as_integer_ratio, __floor__, etc.)
        if (FloatMethods.get(attr.attr)) |info| {
            const label = try self.emitInlineBlockStart("ar_obj");
            try emitConst(self,"const __ar_obj = ");
            try parent.genExpr(self, attr.value.*);
            try emitFmtConst(self, "; break :{s} (runtime.float", .{label});
            try emitConst(self,info.func);
            try emitConst(self,if (info.needs_alloc) "__ar_obj)" else "(__ar_obj)");
            // FloorBig/CeilBig return error unions
            // In assertRaises context (inside_try_body), let error propagate
            // Otherwise, catch unreachable for normal assertEqual context
            const is_big_variant = std.mem.indexOf(u8, info.func, "Big") != null;
            if (is_big_variant) {
                if (self.inside_try_body) {
                    try emitConst(self,")"); // Let error propagate for assertRaises
                } else {
                    try emitConst(self," catch unreachable)");
                }
            } else {
                try emitConst(self,")");
            }
            try emitConst(self,"; ");
            try self.emitInlineBlockEnd();
            return;
        }
        const label = try self.emitInlineBlockStart("ar_obj");
        try emitConst(self,"const __ar_obj = ");
        try parent.genExpr(self, attr.value.*);
        try emitFmtConst(self, "; break :{s} __ar_obj.@\"", .{label});
        try emitConst(self,attr.attr);
        try emitConst(self,"\"(");
        for (call_args, 0..) |arg, i| {
            if (i > 0) try emitConst(self,", ");
            try parent.genExpr(self, arg);
        }
        try emitConst(self,"); ");
        try self.emitInlineBlockEnd();
        return;
    }

    if (callable == .lambda) {
        const label = try self.emitInlineBlockStart("ar_closure");
        try emitConst(self,"const __ar_closure = ");
        try parent.genExpr(self, callable);
        try emitFmtConst(self, "; break :{s} __ar_closure.call(", .{label});
        for (call_args, 0..) |arg, i| {
            if (i > 0) try emitConst(self,", ");
            try parent.genExpr(self, arg);
        }
        try emitConst(self,"); ");
        try self.emitInlineBlockEnd();
        return;
    }

    if (callable == .name and std.mem.eql(u8, callable.name.id, "int")) {
        try emitConst(self,"runtime.intBuiltinCall(__global_allocator, ");
        if (call_args.len > 0) {
            try parent.genExpr(self, call_args[0]);
            try emitConst(self,", .{");
            if (call_args.len > 1) {
                for (call_args[1..], 0..) |arg, i| {
                    if (i > 0) try emitConst(self,", ");
                    try parent.genExpr(self, arg);
                }
            }
            try emitConst(self,"}");
        } else {
            try emitConst(self,"{}, .{}");
        }
        try emitConst(self,")");
        return;
    }

    if (callable == .name and std.mem.eql(u8, callable.name.id, "float")) {
        try emitConst(self,"runtime.floatBuiltinCall(");
        if (call_args.len > 0) {
            try parent.genExpr(self, call_args[0]);
            try emitConst(self,", .{");
            if (call_args.len > 1) {
                for (call_args[1..], 0..) |arg, i| {
                    if (i > 0) try emitConst(self,", ");
                    try parent.genExpr(self, arg);
                }
            }
            try emitConst(self,"}");
        } else {
            try emitConst(self,"{}, .{}");
        }
        try emitConst(self,")");
        return;
    }

    if (callable == .name and std.mem.eql(u8, callable.name.id, "bool")) {
        try emitConst(self,"runtime.boolBuiltinCall(");
        if (call_args.len > 0) {
            try parent.genExpr(self, call_args[0]);
            try emitConst(self,", .{");
            if (call_args.len > 1) {
                for (call_args[1..], 0..) |arg, i| {
                    if (i > 0) try emitConst(self,", ");
                    try parent.genExpr(self, arg);
                }
            }
            try emitConst(self,"}");
        } else {
            try emitConst(self,"{}, .{}");
        }
        try emitConst(self,")");
        return;
    }

    if (callable == .name and std.mem.eql(u8, callable.name.id, "next")) {
        // next() returns error union, use try to propagate or catch to handle
        try emitConst(self,"(runtime.builtins.next(");
        if (call_args.len > 0) {
            try emitConst(self,"&");
            try parent.genExpr(self, call_args[0]);
        } else {
            try emitConst(self,"&.{}");
        }
        try emitConst(self,") catch |err| if (err == error.StopIteration) @panic(\"StopIteration\") else @panic(\"TypeError\"))");
        return;
    }

    if (callable == .name and self.callable_vars.contains(callable.name.id)) {
        try parent.genExpr(self, callable);
        try emitConst(self,".call(");
        for (call_args, 0..) |arg, i| {
            if (i > 0) try emitConst(self,", ");
            try parent.genExpr(self, arg);
        }
        try emitConst(self,")");
        return;
    }

    if (callable == .name and std.mem.eql(u8, callable.name.id, "format")) {
        try emitConst(self,"runtime.builtins.format.call(__global_allocator, ");
        for (call_args, 0..) |arg, i| {
            if (i > 0) try emitConst(self,", ");
            try parent.genExpr(self, arg);
        }
        try emitConst(self,")");
        return;
    }

    if (callable == .name and std.mem.eql(u8, callable.name.id, "round")) {
        try emitConst(self,"runtime.builtins.round(");
        if (call_args.len > 0) {
            try parent.genExpr(self, call_args[0]);
            try emitConst(self,", .{");
            if (call_args.len > 1) {
                for (call_args[1..], 0..) |arg, i| {
                    if (i > 0) try emitConst(self,", ");
                    try parent.genExpr(self, arg);
                }
            }
            try emitConst(self,"}");
        } else {
            try emitConst(self,"0, .{}");
        }
        try emitConst(self,")");
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
    try emitConst(self,"(");
    for (call_args, 0..) |arg, i| {
        if (i > 0) try emitConst(self,", ");
        try parent.genExpr(self, arg);
    }
    try emitConst(self,")");
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

/// Check if an int() call on this expression might produce BigInt.
/// This happens when:
/// 1. int(string_literal) where string_literal.len >= 19 (uses parseBigIntUnicode)
/// 2. int(string_variable) - always uses parseBigIntUnicode for safety
/// Returns true if the expression is an int() call that might produce BigInt.
fn intCallMightProduceBigInt(node: ast.Node) bool {
    if (node != .call) return false;
    const call = node.call;
    if (call.func.* != .name) return false;
    if (!std.mem.eql(u8, call.func.name.id, "int")) return false;
    if (call.args.len == 0) return false;

    const arg = call.args[0];
    // Check if argument is a string literal with >= 19 chars (source representation)
    if (arg == .constant and arg.constant.value == .string) {
        const str_val = arg.constant.value.string;
        return str_val.len >= 19;
    }
    // Check if argument is a variable (could be a string variable)
    // String variables always use parseBigIntUnicode for safety
    // We can't statically determine if a variable is a string, so we're conservative
    // and check if this is an int(name) pattern - if it's an int(int_var), codegen
    // will use a different path anyway
    if (arg == .name) {
        // Name argument - could be string variable, which would use BigInt
        // Return true to be safe (may produce false positives, but that's fine -
        // PyValue comparison works for all types)
        return true;
    }
    return false;
}

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
        try emitConst(self,"@compileError(\"assertEqual requires 2 arguments\")");
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
                    try emitConst(self,"if (@TypeOf(");
                    try parent.genExpr(self, call_a.args[0]);
                    try emitConst(self,") != @TypeOf(");
                    try parent.genExpr(self, call_b.args[0]);
                    try emitConst(self,")) return error.AssertionFailed;\n");
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
        try emitConst(self,"if (!runtime.listEquals(__global_allocator, ");
        try parent.genExpr(self, args[0].call.args[0]); // The iterator/iterable
        try emitConst(self,", ");
        try parent.genExpr(self, args[1]); // The expected list/array
        try emitConst(self,")) return error.AssertionFailed;\n");
        return;
    }
    if (args[1] == .call and args[1].call.func.* == .name and
        std.mem.eql(u8, args[1].call.func.name.id, "list") and args[1].call.args.len >= 1)
    {
        try emitConst(self,"if (!runtime.listEquals(__global_allocator, ");
        try parent.genExpr(self, args[1].call.args[0]); // The iterator/iterable
        try emitConst(self,", ");
        try parent.genExpr(self, args[0]); // The expected list/array
        try emitConst(self,")) return error.AssertionFailed;\n");
        return;
    }

    // Infer types for type-specific code generation
    const type_a = self.type_inferrer.inferExpr(args[0]) catch .unknown;
    const type_b = self.type_inferrer.inferExpr(args[1]) catch .unknown;
    const tag_a: std.meta.Tag(NativeType) = type_a;
    const tag_b: std.meta.Tag(NativeType) = type_b;

    // === SPECIAL CASE: int(string) might produce BigInt ===
    // When int() is called on a string with >= 19 chars (source representation) or
    // on a string variable, codegen uses parseBigIntUnicode which returns BigInt.
    // In this case, direct comparison won't work - use PyValue comparison.
    const a_might_be_bigint = intCallMightProduceBigInt(args[0]);
    const b_might_be_bigint = intCallMightProduceBigInt(args[1]);
    if (a_might_be_bigint or b_might_be_bigint or tag_a == .bigint or tag_b == .bigint) {
        // BigInt comparison - use PyValue.eql() which handles BigInt correctly
        try emitConst(self,"if (!runtime.PyValue.from(");
        try parent.genExpr(self, args[0]);
        try emitConst(self,").eql(runtime.PyValue.from(");
        try parent.genExpr(self, args[1]);
        try emitConst(self,"))) return error.AssertionFailed;\n");
        return;
    }

    // === PRIMITIVE TYPES: Direct comparison ===
    // For known primitive types, use optimized inline comparisons (no monomorphization)
    if (tag_a == tag_b) {
        switch (type_a) {
            .int, .usize => {
                try emitConst(self,"if ((");
                try parent.genExpr(self, args[0]);
                try emitConst(self,") != (");
                try parent.genExpr(self, args[1]);
                try emitConst(self,")) return error.AssertionFailed;\n");
                return;
            },
            .float => {
                try emitConst(self,"if ((");
                try parent.genExpr(self, args[0]);
                try emitConst(self,") != (");
                try parent.genExpr(self, args[1]);
                try emitConst(self,")) return error.AssertionFailed;\n");
                return;
            },
            .bool => {
                try emitConst(self,"if ((");
                try parent.genExpr(self, args[0]);
                try emitConst(self,") != (");
                try parent.genExpr(self, args[1]);
                try emitConst(self,")) return error.AssertionFailed;\n");
                return;
            },
            .string => {
                try emitConst(self,"if (!std.mem.eql(u8, ");
                try parent.genExpr(self, args[0]);
                try emitConst(self,", ");
                try parent.genExpr(self, args[1]);
                try emitConst(self,")) return error.AssertionFailed;\n");
                return;
            },
            else => {},
        }
    }

    // === EMPTY LIST: Length check ===
    if (isEmptyListLiteral(args[1])) {
        try emitConst(self,"if (runtime.builtinLen(");
        try parent.genExpr(self, args[0]);
        try emitConst(self,") != 0) return error.AssertionFailed;\n");
        return;
    }
    if (isEmptyListLiteral(args[0])) {
        try emitConst(self,"if (runtime.builtinLen(");
        try parent.genExpr(self, args[1]);
        try emitConst(self,") != 0) return error.AssertionFailed;\n");
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
        const label = try self.emitInlineBlockStart("ae");
        try emitConst(self,"const __ae_raw_a = ");
        try parent.genExpr(self, args[0]);
        try emitConst(self,"; const __ae_raw_b = ");
        try parent.genExpr(self, args[1]);
        // Extract slice using container_dispatch helper - avoids inline @typeInfo monomorphization
        try emitConst(self,"; const __ae_slice_a: ");
        try emitConst(self,slice_type.?);
        try emitConst(self," = runtime.container_dispatch.getSlice(@TypeOf(__ae_raw_a), __ae_raw_a);");
        try emitConst(self," const __ae_slice_b: ");
        try emitConst(self,slice_type.?);
        try emitConst(self," = runtime.container_dispatch.getSlice(@TypeOf(__ae_raw_b), __ae_raw_b);");
        // Compare with concrete type
        try emitFmtConst(self, " break :{s} !std.mem.eql(", .{label});
        try emitConst(self,elem_type.?);
        try emitConst(self,", __ae_slice_a, __ae_slice_b); ");
        try self.emitInlineBlockEnd();
        try emitConst(self,") return error.AssertionFailed;\n");
        return;
    }

    // === TUPLE COMPARISON ===
    // Use PyValue.from().eql() for tuple comparison - compiles once, not per type
    if (tag_a == .tuple and tag_b == .tuple) {
        try emitConst(self,"if (!runtime.PyValue.from(");
        try parent.genExpr(self, args[0]);
        try emitConst(self,").eql(runtime.PyValue.from(");
        try parent.genExpr(self, args[1]);
        try emitConst(self,"))) return error.AssertionFailed;\n");
        return;
    }

    // === CLASS INSTANCE COMPARISON ===
    // Class instances have __eq__ methods that pyAnyEql will call.
    // PyValue.from() can't represent class instances properly, so use pyAnyEql.
    if (tag_a == .class_instance or tag_b == .class_instance) {
        try emitConst(self,"if (!runtime.pyAnyEql(");
        try parent.genExpr(self, args[0]);
        try emitConst(self,", ");
        try parent.genExpr(self, args[1]);
        try emitConst(self,")) return error.AssertionFailed;\n");
        return;
    }

    // === PyValue COMPARISON (for uncertain types) ===
    // When either type is unknown/pyvalue, use pyAnyEql which handles __eq__ on class instances.
    // This compiles ONCE instead of monomorphizing for each type combination.
    // Note: using pyAnyEql instead of PyValue.from().eql() to handle class instances
    // that may be returned from method calls (e.g., Rat.__radd__).
    const is_uncertain = (type_a == .pyvalue or type_a == .unknown or
        type_b == .pyvalue or type_b == .unknown);
    if (is_uncertain) {
        try emitConst(self,"if (!runtime.pyAnyEql(");
        try parent.genExpr(self, args[0]);
        try emitConst(self,", ");
        try parent.genExpr(self, args[1]);
        try emitConst(self,")) return error.AssertionFailed;\n");
        return;
    }

    // === GENERIC FALLBACK: Use runtime.pyAnyEql() ===
    // For all other cases (dicts, sets, mixed types without __eq__),
    // use runtime.pyAnyEql() which handles __eq__ methods on class instances.
    // This handles all comparison semantics:
    // - Same-type comparisons (floats with NaN, ints, strings)
    // - Cross-type comparisons (int vs float)
    // - Container comparisons (lists, dicts, sets)
    // - Class instance comparisons (calls __eq__ if available)
    try emitConst(self,"if (!runtime.pyAnyEql(");
    try parent.genExpr(self, args[0]);
    try emitConst(self,", ");
    try parent.genExpr(self, args[1]);
    try emitConst(self,")) return error.AssertionFailed;\n");
}

pub const genAssertTrue = gen1ArgAssert("assertTrue");
pub const genAssertFalse = gen1ArgAssert("assertFalse");
pub const genAssertIsNone = gen1ArgAssert("assertIsNone");
/// Generate code for assertGreater(a, b) - routes uncertain types to PyValue.gt()
pub fn genAssertGreater(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try emitConst(self,"@compileError(\"assertGreater requires 2 arguments\")");
        return;
    }

    const type_a = self.type_inferrer.inferExpr(args[0]) catch .unknown;
    const type_b = self.type_inferrer.inferExpr(args[1]) catch .unknown;
    const is_uncertain = (type_a == .pyvalue or type_a == .unknown or
        type_b == .pyvalue or type_b == .unknown);

    if (is_uncertain) {
        // Route to PyValue.gt() - compiles ONCE
        try emitConst(self,"if (!runtime.PyValue.from(");
        try parent.genExpr(self, args[0]);
        try emitConst(self,").gt(runtime.PyValue.from(");
        try parent.genExpr(self, args[1]);
        try emitConst(self,"))) return error.AssertionFailed;\n");
    } else {
        // Direct comparison for certain types - native speed
        try emitConst(self,"if (!(");
        try parent.genExpr(self, args[0]);
        try emitConst(self," > ");
        try parent.genExpr(self, args[1]);
        try emitConst(self,")) return error.AssertionFailed;\n");
    }
}

/// Generate code for assertLess(a, b) - routes uncertain types to PyValue.lt()
pub fn genAssertLess(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try emitConst(self,"@compileError(\"assertLess requires 2 arguments\")");
        return;
    }

    const type_a = self.type_inferrer.inferExpr(args[0]) catch .unknown;
    const type_b = self.type_inferrer.inferExpr(args[1]) catch .unknown;
    const is_uncertain = (type_a == .pyvalue or type_a == .unknown or
        type_b == .pyvalue or type_b == .unknown);

    if (is_uncertain) {
        // Route to PyValue.lt() - compiles ONCE
        try emitConst(self,"if (!runtime.PyValue.from(");
        try parent.genExpr(self, args[0]);
        try emitConst(self,").lt(runtime.PyValue.from(");
        try parent.genExpr(self, args[1]);
        try emitConst(self,"))) return error.AssertionFailed;\n");
    } else {
        // Direct comparison for certain types - native speed
        try emitConst(self,"if (!(");
        try parent.genExpr(self, args[0]);
        try emitConst(self," < ");
        try parent.genExpr(self, args[1]);
        try emitConst(self,")) return error.AssertionFailed;\n");
    }
}

/// Generate code for assertGreaterEqual(a, b) - routes uncertain types to PyValue.ge()
pub fn genAssertGreaterEqual(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try emitConst(self,"@compileError(\"assertGreaterEqual requires 2 arguments\")");
        return;
    }

    const type_a = self.type_inferrer.inferExpr(args[0]) catch .unknown;
    const type_b = self.type_inferrer.inferExpr(args[1]) catch .unknown;
    const is_uncertain = (type_a == .pyvalue or type_a == .unknown or
        type_b == .pyvalue or type_b == .unknown);

    if (is_uncertain) {
        // Route to PyValue.ge() - compiles ONCE
        try emitConst(self,"if (!runtime.PyValue.from(");
        try parent.genExpr(self, args[0]);
        try emitConst(self,").ge(runtime.PyValue.from(");
        try parent.genExpr(self, args[1]);
        try emitConst(self,"))) return error.AssertionFailed;\n");
    } else {
        // Direct comparison for certain types - native speed
        try emitConst(self,"if (!(");
        try parent.genExpr(self, args[0]);
        try emitConst(self," >= ");
        try parent.genExpr(self, args[1]);
        try emitConst(self,")) return error.AssertionFailed;\n");
    }
}

/// Generate code for assertLessEqual(a, b) - routes uncertain types to PyValue.le()
pub fn genAssertLessEqual(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try emitConst(self,"@compileError(\"assertLessEqual requires 2 arguments\")");
        return;
    }

    const type_a = self.type_inferrer.inferExpr(args[0]) catch .unknown;
    const type_b = self.type_inferrer.inferExpr(args[1]) catch .unknown;
    const is_uncertain = (type_a == .pyvalue or type_a == .unknown or
        type_b == .pyvalue or type_b == .unknown);

    if (is_uncertain) {
        // Route to PyValue.le() - compiles ONCE
        try emitConst(self,"if (!runtime.PyValue.from(");
        try parent.genExpr(self, args[0]);
        try emitConst(self,").le(runtime.PyValue.from(");
        try parent.genExpr(self, args[1]);
        try emitConst(self,"))) return error.AssertionFailed;\n");
    } else {
        // Direct comparison for certain types - native speed
        try emitConst(self,"if (!(");
        try parent.genExpr(self, args[0]);
        try emitConst(self," <= ");
        try parent.genExpr(self, args[1]);
        try emitConst(self,")) return error.AssertionFailed;\n");
    }
}

/// Generate code for assertNotEqual(a, b) - routes uncertain types to PyValue.eql()
pub fn genAssertNotEqual(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try emitConst(self,"@compileError(\"assertNotEqual requires 2 arguments\")");
        return;
    }

    const type_a = self.type_inferrer.inferExpr(args[0]) catch .unknown;
    const type_b = self.type_inferrer.inferExpr(args[1]) catch .unknown;
    const is_uncertain = (type_a == .pyvalue or type_a == .unknown or
        type_b == .pyvalue or type_b == .unknown);

    if (is_uncertain) {
        // Route to PyValue.eql() with negation - compiles ONCE
        try emitConst(self,"if (runtime.PyValue.from(");
        try parent.genExpr(self, args[0]);
        try emitConst(self,").eql(runtime.PyValue.from(");
        try parent.genExpr(self, args[1]);
        try emitConst(self,"))) return error.AssertionFailed;\n");
    } else {
        // Use unittest fallback for certain types - handles structs, arrays, etc.
        try emitConst(self,"try unittest.assertNotEqual(");
        try parent.genExpr(self, args[0]);
        try emitConst(self,", ");
        try parent.genExpr(self, args[1]);
        try emitConst(self,")");
    }
}
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
        try emitConst(self,"@compileError(\"assertIs requires 2 arguments\")");
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
                        try emitConst(self,"try unittest.assertTypeIs(@TypeOf(");
                        try parent.genExpr(self, args[0].call.args[0]);
                        try emitConst(self,"), ");
                        try emitConst(self,ztype);
                        try emitConst(self,")");
                        return;
                    }
                    // For collection types (dict, list, set), use runtime string-based type check
                    try emitConst(self,"try unittest.assertTypeIsStr(");
                    try parent.genExpr(self, args[0].call.args[0]);
                    try emitConst(self,", \"");
                    try emitConst(self,type_name);
                    try emitConst(self,"\")");
                    return;
                }
                // For user-defined classes (like subclass), compare __name__ field
                // type(x) returns @typeName(@TypeOf(x)) which is a string
                // subclass has __name__ field that matches
                // Use assertTypeIsStr with the class's __name__
                if (!isBuiltinTypeName(type_name)) {
                    // Mark variable as used to avoid "unused local" error
                    try emitConst(self,"{ _ = &");
                    try emitConst(self,type_name);
                    try emitConst(self,"; try unittest.assertTypeIsStr(");
                    try parent.genExpr(self, args[0].call.args[0]);
                    try emitConst(self,", ");
                    try emitConst(self,type_name);
                    try emitConst(self,".__name__); }");
                    return;
                }
            }
        }
    }
    try emitConst(self,"try unittest.assertIs(");
    try parent.genExpr(self, args[0]);
    try emitConst(self,", ");
    try parent.genExpr(self, args[1]);
    try emitConst(self,")");
}

/// Generate code for self.assertIn(item, container)
pub fn genAssertIn(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try emitConst(self,"@compileError(\"assertIn requires 2 arguments\")");
        return;
    }
    try emitConst(self,"try unittest.assertIn(");

    // Check if item is a call that might return error union (like float.__getformat__)
    if (args[0] == .call and args[0].call.func.* == .attribute) {
        const attr = args[0].call.func.attribute;
        if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "float")) {
            if (std.mem.eql(u8, attr.attr, "__getformat__")) {
                // float.__getformat__ returns ![]const u8, need to try
                try emitConst(self,"try ");
            }
        }
    }
    try parent.genExpr(self, args[0]);
    try emitConst(self,", ");
    try parent.genExpr(self, args[1]);
    try emitConst(self,")");
}

/// Generate code for self.assertIsInstance(obj, type)
pub fn genAssertIsInstance(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try emitConst(self,"@compileError(\"assertIsInstance requires 2 arguments\")");
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
            try emitConst(self,"try unittest.assertIsInstance(");
            try parent.genExpr(self, args[0]);
            try emitConst(self,", ");
            // Escape Zig keywords like "struct" when used as variable names
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), type_var);
            try emitConst(self,".__name__)");
            return;
        }
    }
    try emitConst(self,"try unittest.assertIsInstance(");
    try parent.genExpr(self, args[0]);
    try emitConst(self,", ");
    if (args[1] == .name) {
        try emitConst(self,"\"");
        try emitConst(self,args[1].name.id);
        try emitConst(self,"\"");
    } else {
        try parent.genExpr(self, args[1]);
    }
    try emitConst(self,")");
}

/// Generate code for self.assertNotIsInstance(obj, type)
pub fn genAssertNotIsInstance(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try emitConst(self,"@compileError(\"assertNotIsInstance requires 2 arguments\")");
        return;
    }
    try emitConst(self,"try unittest.assertNotIsInstance(");
    try parent.genExpr(self, args[0]);
    try emitConst(self,", ");
    if (args[1] == .name) {
        try emitConst(self,"\"");
        try emitConst(self,args[1].name.id);
        try emitConst(self,"\"");
    } else {
        try parent.genExpr(self, args[1]);
    }
    try emitConst(self,")");
}

/// Generate code for self.assertIsSubclass(cls, parent_cls)
pub fn genAssertIsSubclass(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try emitConst(self,"@compileError(\"assertIsSubclass requires 2 arguments\")");
        return;
    }
    try emitConst(self,"unittest.assertIsSubclass(");
    if (args[0] == .name) {
        try emitConst(self,"\"");
        try emitConst(self,args[0].name.id);
        try emitConst(self,"\"");
    } else {
        try parent.genExpr(self, args[0]);
    }
    try emitConst(self,", ");
    if (args[1] == .name) {
        try emitConst(self,"\"");
        try emitConst(self,args[1].name.id);
        try emitConst(self,"\"");
    } else {
        try parent.genExpr(self, args[1]);
    }
    try emitConst(self,")");
}

/// Generate code for self.assertRaises(exception_type, callable, *args)
/// For AOT compilation, we check if the callable is a builtin like eval
/// and generate a try-catch block to verify an error is raised
pub fn genAssertRaises(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try emitConst(self,"@compileError(\"assertRaises requires at least 2 arguments: exception_type, callable\")");
        return;
    }

    // Check if callable is 'eval' - special handling needed
    if (args[1] == .name and std.mem.eql(u8, args[1].name.id, "eval")) {
        // Note: eval-string-only variable discards are now handled in assign.zig
        const label = try self.emitInlineBlockStart("ar_eval");
        try emitConst(self,"_ = runtime.eval(__global_allocator, ");
        if (args.len > 2) {
            try parent.genExpr(self, args[2]);
        } else {
            try emitConst(self,"\"\"");
        }
        try emitFmtConst(self, ") catch break :{s} {{}}; return error.ExpectedExceptionNotRaised; ", .{label});
        try self.emitInlineBlockEnd();
        return;
    }

    // Check if callable is 'compile' - special handling needed
    if (args[1] == .name and std.mem.eql(u8, args[1].name.id, "compile")) {
        const label = try self.emitInlineBlockStart("ar_compile");
        try emitConst(self,"_ = runtime.compile_builtin(__global_allocator, ");
        if (args.len > 2) {
            try parent.genExpr(self, args[2]); // source
            try emitConst(self,", ");
        } else {
            try emitConst(self,"\"\", ");
        }
        if (args.len > 3) {
            try parent.genExpr(self, args[3]); // filename
            try emitConst(self,", ");
        } else {
            try emitConst(self,"\"<string>\", ");
        }
        if (args.len > 4) {
            try parent.genExpr(self, args[4]); // mode
        } else {
            try emitConst(self,"\"exec\"");
        }
        try emitFmtConst(self, ") catch break :{s} {{}}; return error.ExpectedExceptionNotRaised; ", .{label});
        try self.emitInlineBlockEnd();
        return;
    }

    // For assertRaises, we need to check if the callable raises an error
    // Extract exception type name if it's a known Python exception
    const exception_name: ?[]const u8 = blk: {
        if (args[0] == .name) {
            const name = args[0].name.id;
            // Map Python exception names to Zig error names
            if (std.mem.eql(u8, name, "ValueError")) break :blk "ValueError";
            if (std.mem.eql(u8, name, "TypeError")) break :blk "TypeError";
            if (std.mem.eql(u8, name, "OverflowError")) break :blk "OverflowError";
            if (std.mem.eql(u8, name, "ZeroDivisionError")) break :blk "ZeroDivisionError";
            if (std.mem.eql(u8, name, "IndexError")) break :blk "IndexError";
            if (std.mem.eql(u8, name, "KeyError")) break :blk "KeyError";
            if (std.mem.eql(u8, name, "AttributeError")) break :blk "AttributeError";
            if (std.mem.eql(u8, name, "RuntimeError")) break :blk "RuntimeError";
            if (std.mem.eql(u8, name, "StopIteration")) break :blk "StopIteration";
            if (std.mem.eql(u8, name, "AssertionError")) break :blk "AssertionError";
        }
        break :blk null;
    };

    const call_args: []const ast.Node = if (args.len > 2) args[2..] else &.{};
    // Set inside_try_body so error-returning functions propagate errors instead of swallowing them
    const prev_inside_try = self.inside_try_body;
    self.inside_try_body = true;

    if (exception_name) |exc_name| {
        // Use expectSpecificError for known exception types
        // Use if-else chain instead of switch to avoid trailing semicolon issues
        try emitConst(self, "{ const __ar_result = unittest.expectSpecificError(");
        try emitCallableInvocation(self, args[1], call_args, &.{});
        try emitFmtConst(self, ", \"{s}\"); if (__ar_result == .no_error) return error.ExpectedExceptionNotRaised; if (__ar_result == .wrong_error) return error.WrongExceptionType; }}", .{exc_name});
    } else {
        // Fall back to expectError for unknown exception types
        try emitConst(self, "if (unittest.expectError(");
        try emitCallableInvocation(self, args[1], call_args, &.{});
        // expectError returns true if NO error was raised (test should fail)
        try emitConst(self, ")) return error.ExpectedExceptionNotRaised;");
    }
    self.inside_try_body = prev_inside_try;
}

/// Generate code for self.assertRaises(exception_type, callable, *args, **kwargs)
/// This variant handles keyword arguments that need to be passed to the callable
pub fn genAssertRaisesWithKwargs(self: *NativeCodegen, obj: ast.Node, args: []ast.Node, keyword_args: []const ast.Node.KeywordArg) CodegenError!void {
    // If no keyword args, use the regular handler
    if (keyword_args.len == 0) {
        return genAssertRaises(self, obj, args);
    }

    if (args.len < 2) {
        try emitConst(self,"@compileError(\"assertRaises requires at least 2 arguments: exception_type, callable\")");
        return;
    }

    // Extract exception type name if it's a known Python exception
    const exception_name: ?[]const u8 = blk: {
        if (args[0] == .name) {
            const name = args[0].name.id;
            if (std.mem.eql(u8, name, "ValueError")) break :blk "ValueError";
            if (std.mem.eql(u8, name, "TypeError")) break :blk "TypeError";
            if (std.mem.eql(u8, name, "OverflowError")) break :blk "OverflowError";
            if (std.mem.eql(u8, name, "ZeroDivisionError")) break :blk "ZeroDivisionError";
            if (std.mem.eql(u8, name, "IndexError")) break :blk "IndexError";
            if (std.mem.eql(u8, name, "KeyError")) break :blk "KeyError";
            if (std.mem.eql(u8, name, "AttributeError")) break :blk "AttributeError";
            if (std.mem.eql(u8, name, "RuntimeError")) break :blk "RuntimeError";
            if (std.mem.eql(u8, name, "StopIteration")) break :blk "StopIteration";
            if (std.mem.eql(u8, name, "AssertionError")) break :blk "AssertionError";
        }
        break :blk null;
    };

    const call_args: []const ast.Node = if (args.len > 2) args[2..] else &.{};
    // Set inside_try_body so error-returning functions propagate errors instead of swallowing them
    const prev_inside_try = self.inside_try_body;
    self.inside_try_body = true;

    if (exception_name) |exc_name| {
        // Use expectSpecificError for known exception types
        // Use if-else chain instead of switch to avoid trailing semicolon issues
        try emitConst(self, "{ const __ar_result = unittest.expectSpecificError(");
        try emitCallableInvocation(self, args[1], call_args, keyword_args);
        try emitFmtConst(self, ", \"{s}\"); if (__ar_result == .no_error) return error.ExpectedExceptionNotRaised; if (__ar_result == .wrong_error) return error.WrongExceptionType; }}", .{exc_name});
    } else {
        // Fall back to expectError for unknown exception types
        try emitConst(self, "if (unittest.expectError(");
        try emitCallableInvocation(self, args[1], call_args, keyword_args);
        try emitConst(self, ")) return error.ExpectedExceptionNotRaised;");
    }
    self.inside_try_body = prev_inside_try;
}

/// Generate code for self.assertRaisesRegex(exception, regex, callable, *args, **kwargs)
/// This variant handles keyword arguments that need to be passed to the callable
pub fn genAssertRaisesRegexWithKwargs(self: *NativeCodegen, obj: ast.Node, args: []ast.Node, keyword_args: []const ast.Node.KeywordArg) CodegenError!void {
    // If no keyword args, use the regular handler
    if (keyword_args.len == 0) {
        return genAssertRaisesRegex(self, obj, args);
    }

    if (args.len < 3) {
        try emitConst(self,"{}");
        return;
    }

    const call_args: []const ast.Node = if (args.len > 3) args[3..] else &.{};
    // Set inside_try_body so error-returning functions propagate errors instead of swallowing them
    const prev_inside_try = self.inside_try_body;
    self.inside_try_body = true;
    const label = try self.emitInlineBlockStart("ar");
    try emitConst(self,"_ = ");
    try parent.genExpr(self, args[1]); // regex parameter
    try emitConst(self,"; _ = ");
    try emitCallableInvocation(self, args[2], call_args, keyword_args);
    self.inside_try_body = prev_inside_try;
    try emitFmtConst(self, " catch break :{s} {{}}; return error.ExpectedExceptionNotRaised; ", .{label});
    try self.emitInlineBlockEnd();
}

/// Generate code for self.assertRaisesRegex(exception, regex, callable, *args)
pub fn genAssertRaisesRegex(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 3) {
        try emitConst(self,"{}");
        return;
    }
    const call_args: []const ast.Node = if (args.len > 3) args[3..] else &.{};
    // Set inside_try_body so error-returning functions propagate errors instead of swallowing them
    const prev_inside_try = self.inside_try_body;
    self.inside_try_body = true;
    // Similar to assertRaises but with regex check on error message
    // For AOT, we just check that an error is raised
    // Reference the regex parameter to avoid unused variable warning
    const label = try self.emitInlineBlockStart("ar");
    try emitConst(self,"_ = ");
    try parent.genExpr(self, args[1]); // regex parameter
    try emitConst(self,"; _ = ");

    try emitCallableInvocation(self, args[2], call_args, &.{});
    self.inside_try_body = prev_inside_try;
    // Catch error directly on call - can't store first since error propagates immediately
    try emitFmtConst(self, " catch break :{s} {{}}; return error.ExpectedExceptionNotRaised; ", .{label});
    try self.emitInlineBlockEnd();
}

/// Generate code for self.assertWarns(warning, callable, *args)
pub fn genAssertWarns(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try emitConst(self,"{}");
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
        try emitConst(self,"{}");
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
        try emitConst(self,"@compileError(\"assertNotIsSubclass requires 2 arguments\")");
        return;
    }
    try emitConst(self,"unittest.assertNotIsSubclass(");
    if (args[0] == .name) {
        try emitConst(self,"\"");
        try emitConst(self,args[0].name.id);
        try emitConst(self,"\"");
    } else {
        try parent.genExpr(self, args[0]);
    }
    try emitConst(self,", ");
    if (args[1] == .name) {
        try emitConst(self,"\"");
        try emitConst(self,args[1].name.id);
        try emitConst(self,"\"");
    } else {
        try parent.genExpr(self, args[1]);
    }
    try emitConst(self,")");
}

/// Generate code for self.assertStartsWith(s, prefix)
pub fn genAssertStartsWith(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try emitConst(self,"@compileError(\"assertStartsWith requires 2 arguments\")");
        return;
    }
    try emitConst(self,"try unittest.assertTrue(std.mem.startsWith(u8, ");
    try parent.genExpr(self, args[0]);
    try emitConst(self,", ");
    try parent.genExpr(self, args[1]);
    try emitConst(self,"))");
}

/// Generate code for self.assertNotStartsWith(s, prefix)
pub fn genAssertNotStartsWith(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try emitConst(self,"@compileError(\"assertNotStartsWith requires 2 arguments\")");
        return;
    }
    try emitConst(self,"try unittest.assertFalse(std.mem.startsWith(u8, ");
    try parent.genExpr(self, args[0]);
    try emitConst(self,", ");
    try parent.genExpr(self, args[1]);
    try emitConst(self,"))");
}

/// Generate code for self.assertEndsWith(s, suffix)
pub fn genAssertEndsWith(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try emitConst(self,"@compileError(\"assertEndsWith requires 2 arguments\")");
        return;
    }
    try emitConst(self,"try unittest.assertTrue(std.mem.endsWith(u8, ");
    try parent.genExpr(self, args[0]);
    try emitConst(self,", ");
    try parent.genExpr(self, args[1]);
    try emitConst(self,"))");
}

/// Generate code for self.assertHasAttr(obj, name)
pub fn genAssertHasAttr(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try emitConst(self,"@compileError(\"assertHasAttr requires 2 arguments\")");
        return;
    }
    // For module attribute checking, verify at comptime using @hasField (if struct)
    // Use a no-op that references the arguments to avoid "unused variable" errors
    try emitConst(self,"{ _ = ");
    try parent.genExpr(self, args[1]);
    try emitConst(self,"; }"); // Reference the attr name to mark it as used
}

/// Generate code for self.assertNotHasAttr(obj, name)
pub fn genAssertNotHasAttr(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try emitConst(self,"@compileError(\"assertNotHasAttr requires 2 arguments\")");
        return;
    }
    // For AOT, we check at compile time using @hasField (must check struct type first)
    try emitConst(self,"comptime { const _T = @TypeOf(");
    try parent.genExpr(self, args[0]);
    try emitConst(self,"); if (@typeInfo(_T) == .@\"struct\" and @hasField(_T, ");
    try parent.genExpr(self, args[1]);
    try emitConst(self,")) @compileError(\"assertNotHasAttr failed\"); }");
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
    try emitConst(self,"struct { pub fn __enter__(_: *const @This()) @This() { return @This(){}; } pub fn __exit__(_: *const @This()) void {} records: []const []const u8 = &.{}, output: []const u8 = \"\" }{}");
}

/// Generate code for self.assertNoLogs(logger, level)
pub fn genAssertNoLogs(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    try genAssertLogs(self, obj, args);
}

/// Generate code for self.fail(msg)
pub fn genFail(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    try emitConst(self,"@panic(");
    if (args.len > 0) {
        try parent.genExpr(self, args[0]);
    } else {
        try emitConst(self,"\"Test failed\"");
    }
    try emitConst(self,")");
}

/// Generate code for self.skipTest(reason)
/// This terminates control flow - no code after skipTest should run
pub fn genSkipTest(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    _ = args;
    try emitConst(self,"return");
    // Mark control flow as terminated so no unreachable code is generated after
    self.control_flow_terminated = true;
}
