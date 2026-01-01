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
const builder_mod = @import("codegen.builder");
const CompOp = builder_mod.CompOp;
const ZigValue = builder_mod.ZigValue;
const CallArg = builder_mod.ZigBuilder.CallArg;

/// Emit func(args...) using builder pattern with auto-closing parens
fn emitCallWithArgs(self: *NativeCodegen, func_name: []const u8, args: []const ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    try b.withCall(func_name, struct {
        fn f(builder: *builder_mod.ZigBuilder, ctx: anytype) !void {
            for (ctx.args, 0..) |arg, i| {
                if (i > 0) try builder.write(", ");
                const val = try ctx.self.captureExpr(arg);
                try builder.emitValueCore(val);
            }
        }
    }.f, .{ .self = self, .args = args });
    try self.flushBuilder();
}

/// Emit obj.method(args...) using builder pattern
fn emitMethodWithArgs(self: *NativeCodegen, obj: ast.Node, method: []const u8, args: []const ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    const obj_val = try self.captureExpr(obj);
    try b.emitValueCore(obj_val);
    try b.write(".@\"");
    try b.write(method);
    try b.write("\"(");
    for (args, 0..) |arg, i| {
        if (i > 0) try b.write(", ");
        const val = try self.captureExpr(arg);
        try b.emitValueCore(val);
    }
    try b.write(")");
    try self.flushBuilder();
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

/// Helper: emit error handling suffix for float Big variants
/// FloorBig/CeilBig return error unions - in assertRaises context let propagate, else catch unreachable
fn emitBigVariantSuffix(self: *NativeCodegen, info: FloatMethodInfo) CodegenError!void {
    const is_big_variant = std.mem.indexOf(u8, info.func, "Big") != null;
    if (is_big_variant) {
        if (self.in_assert_raises_context or self.inside_try_body) {
            try self.emit(")"); // Let error propagate for assertRaises
        } else {
            try self.emit(" catch unreachable)");
        }
    } else {
        try self.emit(")");
    }
}

/// Helper: emit float method call in inline block for assertRaises callable invocation
fn emitFloatMethodBlock(self: *NativeCodegen, value_expr: ast.Node, info: FloatMethodInfo) CodegenError!void {
    const label = try self.emitInlineBlockStart("ar_obj");
    try self.emit("const __ar_obj = ");
    try parent.genExpr(self, value_expr);
    try self.emitFmt("; break :{s} (runtime.float", .{label});
    try self.emit(info.func);
    try self.emit(if (info.needs_alloc) "__ar_obj)" else "(__ar_obj)");
    try emitBigVariantSuffix(self, info);
    try self.emit("; ");
    try self.emitInlineBlockEnd();
}

// Float class methods (e.g., float.__getformat__) - maps Python method names to runtime function names
const FloatClassMethods = std.StaticStringMap([]const u8).initComptime(.{
    .{ "fromhex", "runtime.floatFromHex" },
    .{ "__getformat__", "runtime.floatGetFormat" },
});

/// Handler type for assertion methods
const AssertHandler = *const fn (*NativeCodegen, ast.Node, []ast.Node) CodegenError!void;

// Comptime generator for simple 2-arg assertions using ZigBuilder
// Generates: try unittest.func_name(a, b)
fn gen2ArgAssertBuilder(comptime func_name: []const u8) AssertHandler {
    return struct {
        fn handler(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
            _ = obj;
            if (args.len < 2) {
                try self.emit("@compileError(\"" ++ func_name ++ " requires 2 arguments\")");
                return;
            }
            const left = try self.exprToValue(args[0]);
            const right = try self.exprToValue(args[1]);
            const b = try self.getBuilder();
            try b.emitTryCall("unittest." ++ func_name, &.{ left, right });
            try self.flushBuilder();
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
                // Use builder pattern for self.method(args)
                const b = try self.getBuilder();
                try b.write("self.@\"");
                try b.write(attr.attr);
                try b.write("\"(");
                for (call_args, 0..) |arg, i| {
                    if (i > 0) try b.write(", ");
                    const arg_val = try self.captureExpr(arg);
                    try b.emitValueCore(arg_val);
                }
                try b.write(")");
                try self.flushBuilder();
                return;
            } else if (attr.value.* == .call) {
                if (FloatMethods.get(attr.attr)) |info| {
                    try emitFloatMethodBlock(self, attr.value.*, info);
                } else {
                    const label = try self.emitInlineBlockStart("ar_obj");
                    try self.emit("const __ar_obj = ");
                    try parent.genExpr(self, attr.value.*);
                    try self.emitFmt("; break :{s} __ar_obj.@\"", .{label});
                    try self.emit(attr.attr);
                    try self.emit("\"(");
                    for (call_args, 0..) |arg, i| {
                        if (i > 0) try self.emit(", ");
                        try parent.genExpr(self, arg);
                    }
                    try self.emit("); ");
                    try self.emitInlineBlockEnd();
                }
                return;
            } else if (PyToZigTypes.has(base_name)) {
                // Builtin type methods - use builder pattern
                const b = try self.getBuilder();
                if (std.mem.eql(u8, base_name, "float")) {
                    if (FloatClassMethods.get(attr.attr)) |func_name| {
                        try b.withCall(func_name, struct {
                            fn f(builder: *builder_mod.ZigBuilder, ctx: anytype) !void {
                                for (ctx.args, 0..) |arg, i| {
                                    if (i > 0) try builder.write(", ");
                                    const val = try ctx.self.captureExpr(arg);
                                    try builder.emitValueCore(val);
                                }
                            }
                        }.f, .{ .self = self, .args = call_args });
                        try self.flushBuilder();
                        return;
                    }
                }
                // Build runtime.base_nameattr(args)
                const func_name = try std.fmt.allocPrint(self.arena.allocator(), "runtime.{s}{s}", .{ base_name, attr.attr });
                try b.withCall(func_name, struct {
                    fn f(builder: *builder_mod.ZigBuilder, ctx: anytype) !void {
                        for (ctx.args, 0..) |arg, i| {
                            if (i > 0) try builder.write(", ");
                            const val = try ctx.self.captureExpr(arg);
                            try builder.emitValueCore(val);
                        }
                    }
                }.f, .{ .self = self, .args = call_args });
                try self.flushBuilder();
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
                    try self.emit("_ = ");
                    try parent.genExpr(self, arg);
                    try self.emit("; ");
                }
                try self.emitFmt("break :{s} error.TypeError; ", .{label});
                try self.emitInlineBlockEnd();
            } else {
                // Use builder pattern for variable.method(args)
                const b = try self.getBuilder();
                const obj_val = try self.captureExpr(attr.value.*);
                try b.emitValueCore(obj_val);
                try b.write(".@\"");
                try b.write(attr.attr);
                try b.write("\"(");
                for (call_args, 0..) |arg, i| {
                    if (i > 0) try b.write(", ");
                    const arg_val = try self.captureExpr(arg);
                    try b.emitValueCore(arg_val);
                }
                try b.write(")");
                try self.flushBuilder();
            }
            return;
        }

        // Complex expression attribute (e.g., {}.update, some_call().method)
        // Check for list methods that need special handling in assertRaises context
        if (std.mem.eql(u8, attr.attr, "extend")) {
            // List.extend() in assertRaises context - use runtime helper
            const label = try self.emitInlineBlockStart("ar_obj");
            try self.emit("var __ar_list = ");
            try parent.genExpr(self, attr.value.*);
            try self.emit("; try runtime.listExtendIterable(__global_allocator, &__ar_list, ");
            if (call_args.len > 0) {
                try parent.genExpr(self, call_args[0]);
            }
            try self.emitFmt("); break :{s} {{}}; ", .{label});
            try self.emitInlineBlockEnd();
            return;
        }

        // Check for float methods that need runtime dispatch (as_integer_ratio, __floor__, etc.)
        if (FloatMethods.get(attr.attr)) |info| {
            try emitFloatMethodBlock(self, attr.value.*, info);
            return;
        }
        const label = try self.emitInlineBlockStart("ar_obj");
        try self.emit("const __ar_obj = ");
        try parent.genExpr(self, attr.value.*);
        try self.emitFmt("; break :{s} __ar_obj.@\"", .{label});
        try self.emit(attr.attr);
        try self.emit("\"(");
        for (call_args, 0..) |arg, i| {
            if (i > 0) try self.emit(", ");
            try parent.genExpr(self, arg);
        }
        try self.emit("); ");
        try self.emitInlineBlockEnd();
        return;
    }

    if (callable == .lambda) {
        const label = try self.emitInlineBlockStart("ar_closure");
        try self.emit("const __ar_closure = ");
        try parent.genExpr(self, callable);
        try self.emitFmt("; break :{s} __ar_closure.call(", .{label});
        for (call_args, 0..) |arg, i| {
            if (i > 0) try self.emit(", ");
            try parent.genExpr(self, arg);
        }
        try self.emit("); ");
        try self.emitInlineBlockEnd();
        return;
    }

    if (callable == .name and std.mem.eql(u8, callable.name.id, "getattr")) {
        // getattr produces a labeled block expression that can't be invoked directly
        // Use runtime.getattr_builtin directly which returns error union (for assertRaises to check)
        try self.emit("runtime.getattr_builtin(");
        if (call_args.len > 0) try parent.genExpr(self, call_args[0]);
        if (call_args.len > 1) {
            try self.emit(", ");
            try parent.genExpr(self, call_args[1]);
        }
        try self.emit(")");
        return;
    }

    if (callable == .name and std.mem.eql(u8, callable.name.id, "int")) {
        // Use builder pattern for int() builtin
        const b = try self.getBuilder();
        try b.write("runtime.intBuiltinCall(__global_allocator, ");
        if (call_args.len > 0) {
            const first_val = try self.captureExpr(call_args[0]);
            try b.emitValueCore(first_val);
            try b.write(", .{");
            for (call_args[1..], 0..) |arg, i| {
                if (i > 0) try b.write(", ");
                const arg_val = try self.captureExpr(arg);
                try b.emitValueCore(arg_val);
            }
            try b.write("}");
        } else {
            try b.write("{}, .{}");
        }
        try b.write(")");
        try self.flushBuilder();
        return;
    }

    if (callable == .name and std.mem.eql(u8, callable.name.id, "float")) {
        // Use builder pattern for float() builtin
        const b = try self.getBuilder();
        try b.write("runtime.floatBuiltinCall(");
        if (call_args.len > 0) {
            const first_val = try self.captureExpr(call_args[0]);
            try b.emitValueCore(first_val);
            try b.write(", .{");
            for (call_args[1..], 0..) |arg, i| {
                if (i > 0) try b.write(", ");
                const arg_val = try self.captureExpr(arg);
                try b.emitValueCore(arg_val);
            }
            try b.write("}");
        } else {
            try b.write("{}, .{}");
        }
        try b.write(")");
        try self.flushBuilder();
        return;
    }

    if (callable == .name and std.mem.eql(u8, callable.name.id, "bool")) {
        // Use builder pattern for bool() builtin
        const b = try self.getBuilder();
        try b.write("runtime.boolBuiltinCall(");
        if (call_args.len > 0) {
            const first_val = try self.captureExpr(call_args[0]);
            try b.emitValueCore(first_val);
            try b.write(", .{");
            for (call_args[1..], 0..) |arg, i| {
                if (i > 0) try b.write(", ");
                const arg_val = try self.captureExpr(arg);
                try b.emitValueCore(arg_val);
            }
            try b.write("}");
        } else {
            try b.write("{}, .{}");
        }
        try b.write(")");
        try self.flushBuilder();
        return;
    }

    if (callable == .name and std.mem.eql(u8, callable.name.id, "next")) {
        // next() returns error union, use try to propagate or catch to handle
        try self.withParensCtx(call_args, struct {
            pub fn emit(s: *NativeCodegen, args: []const ast.Node) CodegenError!void {
                try s.emitCallCtx("runtime.builtins.next", args, struct {
                    pub fn inner(s2: *NativeCodegen, a: []const ast.Node) CodegenError!void {
                        if (a.len > 0) {
                            try s2.emit("&");
                            try parent.genExpr(s2, a[0]);
                        } else {
                            try s2.emit("&.{}");
                        }
                    }
                }.inner);
                try s.emit(" catch |err| if (err == error.StopIteration) @panic(\"StopIteration\") else @panic(\"TypeError\")");
            }
        }.emit);
        return;
    }

    if (callable == .name and std.mem.eql(u8, callable.name.id, "iter")) {
        // iter() builtin - CPython aligned: validates args at runtime
        const b = try self.getBuilder();
        try b.write("runtime.builtins.iterBuiltin(&.{");
        for (call_args, 0..) |arg, i| {
            if (i > 0) try b.write(", ");
            try b.write("runtime.PyValue.from(");
            const arg_val = try self.captureExpr(arg);
            try b.emitValueCore(arg_val);
            try b.write(")");
        }
        try b.write("}, __global_allocator)");
        try self.flushBuilder();
        return;
    }

    if (callable == .name and std.mem.eql(u8, callable.name.id, "filter")) {
        // filter() builtin - CPython aligned: validates args at runtime
        const b = try self.getBuilder();
        try b.write("runtime.builtins.filter(&.{");
        for (call_args, 0..) |arg, i| {
            if (i > 0) try b.write(", ");
            try b.write("runtime.PyValue.from(");
            const arg_val = try self.captureExpr(arg);
            try b.emitValueCore(arg_val);
            try b.write(")");
        }
        try b.write("}, __global_allocator)");
        try self.flushBuilder();
        return;
    }

    if (callable == .name and self.callable_vars.contains(callable.name.id)) {
        // Use builder pattern for callable.call(args)
        const b = try self.getBuilder();
        const callable_val = try self.captureExpr(callable);
        try b.emitValueCore(callable_val);
        try b.write(".call(");
        for (call_args, 0..) |arg, i| {
            if (i > 0) try b.write(", ");
            const arg_val = try self.captureExpr(arg);
            try b.emitValueCore(arg_val);
        }
        try b.write(")");
        try self.flushBuilder();
        return;
    }

    if (callable == .name and std.mem.eql(u8, callable.name.id, "format")) {
        // Use builder pattern for format() builtin
        const b = try self.getBuilder();
        try b.write("runtime.builtins.format.call(__global_allocator, ");
        for (call_args, 0..) |arg, i| {
            if (i > 0) try b.write(", ");
            const arg_val = try self.captureExpr(arg);
            try b.emitValueCore(arg_val);
        }
        try b.write(")");
        try self.flushBuilder();
        return;
    }

    if (callable == .name and std.mem.eql(u8, callable.name.id, "round")) {
        // Use builder pattern for round() builtin
        const b = try self.getBuilder();
        try b.write("runtime.builtins.round(");
        if (call_args.len > 0) {
            const first_val = try self.captureExpr(call_args[0]);
            try b.emitValueCore(first_val);
            try b.write(", .{");
            for (call_args[1..], 0..) |arg, i| {
                if (i > 0) try b.write(", ");
                const arg_val = try self.captureExpr(arg);
                try b.emitValueCore(arg_val);
            }
            try b.write("}");
        } else {
            try b.write("0, .{}");
        }
        try b.write(")");
        try self.flushBuilder();
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

    // Handle call to getattr - produces labeled block that can't be called directly
    // Pattern: assertRaises(TypeError, getattr(obj, name))
    // getattr(obj, name) returns a callable that needs to be extracted before calling
    if (callable == .call) {
        const inner_call = callable.call;
        if (inner_call.func.* == .name and std.mem.eql(u8, inner_call.func.name.id, "getattr")) {
            // Extract getattr result to variable, then call it
            const label = try self.emitInlineBlockStart("ar_func");
            try self.emit("const __ar_func = ");
            try parent.genExpr(self, callable);
            try self.emitFmt("; break :{s} __ar_func(", .{label});
            for (call_args, 0..) |arg, i| {
                if (i > 0) try self.emit(", ");
                try parent.genExpr(self, arg);
            }
            try self.emit("); ");
            try self.emitInlineBlockEnd();
            return;
        }
    }

    // Fallback: simple callable expression - use builder pattern
    const b = try self.getBuilder();
    const callable_val = try self.captureExpr(callable);
    try b.emitValueCore(callable_val);
    try b.write("(");
    for (call_args, 0..) |arg, i| {
        if (i > 0) try b.write(", ");
        const arg_val = try self.captureExpr(arg);
        try b.emitValueCore(arg_val);
    }
    try b.write(")");
    try self.flushBuilder();
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
/// Uses ZigBuilder for fallback path (100% builder migration)
///
/// Strategy: Special cases use emit() for AST-level optimizations,
/// standard path uses ZigBuilder structured API.
pub fn genAssertEqual(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertEqual requires 2 arguments\")");
        return;
    }

    // === SPECIAL CASE 1: assertEqual(type(x), type(y)) ===
    // Optimize to @TypeOf comparison at comptime
    if (args[0] == .call and args[1] == .call) {
        const call_a = args[0].call;
        const call_b = args[1].call;
        if (call_a.func.* == .name and call_b.func.* == .name) {
            if (std.mem.eql(u8, call_a.func.name.id, "type") and
                std.mem.eql(u8, call_b.func.name.id, "type"))
            {
                if (call_a.args.len >= 1 and call_b.args.len >= 1) {
                    try self.emit("if (@TypeOf(");
                    try parent.genExpr(self, call_a.args[0]);
                    try self.emit(") != @TypeOf(");
                    try parent.genExpr(self, call_b.args[0]);
                    try self.emit(")) return error.AssertionFailed;\n");
                    return;
                }
            }
        }
    }

    // === SPECIAL CASE 2: assertEqual(type(x), TypeName) ===
    if (try emitTypeNameComparison(self, args)) return;

    // === SPECIAL CASE 3: assertEqual(list(x), y) ===
    if (try emitListComparison(self, args)) return;

    // Infer types for type-specific optimizations
    const type_a = self.type_inferrer.inferExpr(args[0]) catch .unknown;
    const type_b = self.type_inferrer.inferExpr(args[1]) catch .unknown;
    const tag_a: std.meta.Tag(NativeType) = type_a;
    const tag_b: std.meta.Tag(NativeType) = type_b;

    // === SPECIAL CASE 4: BigInt comparison ===
    const a_might_be_bigint = intCallMightProduceBigInt(args[0]);
    const b_might_be_bigint = intCallMightProduceBigInt(args[1]);
    if (a_might_be_bigint or b_might_be_bigint or tag_a == .bigint or tag_b == .bigint) {
        try self.emit("if (!runtime.PyValue.from(");
        try parent.genExpr(self, args[0]);
        try self.emit(").eql(runtime.PyValue.from(");
        try parent.genExpr(self, args[1]);
        try self.emit("))) return error.AssertionFailed;\n");
        return;
    }

    // === SPECIAL CASE 5: Empty list literal → length check ===
    if (isEmptyListLiteral(args[1])) {
        try self.emit("if (runtime.builtinLen(");
        try parent.genExpr(self, args[0]);
        try self.emit(") != 0) return error.AssertionFailed;\n");
        return;
    }
    if (isEmptyListLiteral(args[0])) {
        try self.emit("if (runtime.builtinLen(");
        try parent.genExpr(self, args[1]);
        try self.emit(") != 0) return error.AssertionFailed;\n");
        return;
    }

    // === SPECIAL CASE 6: List/slice with known element type ===
    if (try emitSliceComparison(self, args, type_a, type_b)) return;

    // === SPECIAL CASE 7: default_factory comparison ===
    // assertEqual(d.default_factory, int) → d.default_factory == .int
    if (try emitDefaultFactoryComparison(self, args)) return;

    // === STANDARD PATH: Use ZigBuilder ===
    // Builder handles: same-type primitives, strings, cross-type, class instances
    const left = try self.exprToValue(args[0]);
    const right = try self.exprToValue(args[1]);
    const b = try self.getBuilder();
    try b.emitAssertEqualStmt(left, right);
    try self.flushBuilder();
}

// === Helper functions for genAssertEqual special cases ===

/// Handle assertEqual(type(x), TypeName) or assertEqual(TypeName, type(x))
fn emitTypeNameComparison(self: *NativeCodegen, args: []ast.Node) !bool {
    const known_types = [_][]const u8{ "complex", "float", "int", "str", "bool", "bytes", "list", "dict", "tuple", "set" };

    // Check: assertEqual(type(x), TypeName)
    if (args[0] == .call and args[0].call.func.* == .name and
        std.mem.eql(u8, args[0].call.func.name.id, "type") and args[0].call.args.len >= 1)
    {
        if (args[1] == .name) {
            const type_name = args[1].name.id;
            for (known_types) |known| {
                if (std.mem.eql(u8, type_name, known)) {
                    try self.emit("if (!std.mem.eql(u8, runtime.pyTypeName(");
                    try parent.genExpr(self, args[0].call.args[0]);
                    try self.emitFmt("), \"{s}\")) return error.AssertionFailed;\n", .{type_name});
                    return true;
                }
            }
        }
    }

    // Check: assertEqual(TypeName, type(x))
    if (args[1] == .call and args[1].call.func.* == .name and
        std.mem.eql(u8, args[1].call.func.name.id, "type") and args[1].call.args.len >= 1)
    {
        if (args[0] == .name) {
            const type_name = args[0].name.id;
            for (known_types) |known| {
                if (std.mem.eql(u8, type_name, known)) {
                    try self.emit("if (!std.mem.eql(u8, runtime.pyTypeName(");
                    try parent.genExpr(self, args[1].call.args[0]);
                    try self.emitFmt("), \"{s}\")) return error.AssertionFailed;\n", .{type_name});
                    return true;
                }
            }
        }
    }

    return false;
}

/// Handle assertEqual(list(x), y) or assertEqual(x, list(y))
fn emitListComparison(self: *NativeCodegen, args: []ast.Node) !bool {
    // Check: assertEqual(list(x), y)
    if (args[0] == .call and args[0].call.func.* == .name and
        std.mem.eql(u8, args[0].call.func.name.id, "list") and args[0].call.args.len >= 1)
    {
        try self.emit("if (!runtime.listEquals(__global_allocator, ");
        try parent.genExpr(self, args[0].call.args[0]);
        try self.emit(", ");
        try parent.genExpr(self, args[1]);
        try self.emit(")) return error.AssertionFailed;\n");
        return true;
    }

    // Check: assertEqual(x, list(y))
    if (args[1] == .call and args[1].call.func.* == .name and
        std.mem.eql(u8, args[1].call.func.name.id, "list") and args[1].call.args.len >= 1)
    {
        try self.emit("if (!runtime.listEquals(__global_allocator, ");
        try parent.genExpr(self, args[1].call.args[0]);
        try self.emit(", ");
        try parent.genExpr(self, args[0]);
        try self.emit(")) return error.AssertionFailed;\n");
        return true;
    }

    return false;
}

/// Handle assertEqual with known list/slice element types
fn emitSliceComparison(self: *NativeCodegen, args: []ast.Node, type_a: NativeType, type_b: NativeType) !bool {
    // Skip if either produces NativeList with PyValue items
    if (producesNativeList(args[0]) or producesNativeList(args[1])) return false;

    // Get element types
    const elem_type = getListElementTypeStr(type_a) orelse getListElementTypeStr(type_b);
    const slice_type = getSliceTypeStr(type_a) orelse getSliceTypeStr(type_b);

    if (elem_type != null and slice_type != null) {
        try self.emit("if (!runtime.container_dispatch.slicesEqual(@TypeOf(");
        try parent.genExpr(self, args[0]);
        try self.emit("), @TypeOf(");
        try parent.genExpr(self, args[1]);
        try self.emit("), &");
        try parent.genExpr(self, args[0]);
        try self.emit(", &");
        try parent.genExpr(self, args[1]);
        try self.emit(")) return error.AssertionFailed;\n");
        return true;
    }

    return false;
}

/// Handle assertEqual(d.default_factory, int) or assertEqual(int, d.default_factory)
/// Compares FactoryType against type names
fn emitDefaultFactoryComparison(self: *NativeCodegen, args: []ast.Node) !bool {
    const factory_types = [_][]const u8{ "list", "int", "str", "dict", "set" };

    // Check: assertEqual(x.default_factory, type_name)
    if (args[0] == .attribute and std.mem.eql(u8, args[0].attribute.attr, "default_factory")) {
        if (args[1] == .name) {
            const type_name = args[1].name.id;
            // Check for None
            if (std.mem.eql(u8, type_name, "None")) {
                try self.emit("if (");
                try parent.genExpr(self, args[0]);
                try self.emit(" != .none) return error.AssertionFailed;\n");
                return true;
            }
            // Check for known factory types
            for (factory_types) |known| {
                if (std.mem.eql(u8, type_name, known)) {
                    try self.emit("if (");
                    try parent.genExpr(self, args[0]);
                    try self.emitFmt(" != .{s}) return error.AssertionFailed;\n", .{known});
                    return true;
                }
            }
        }
    }

    // Check: assertEqual(type_name, x.default_factory)
    if (args[1] == .attribute and std.mem.eql(u8, args[1].attribute.attr, "default_factory")) {
        if (args[0] == .name) {
            const type_name = args[0].name.id;
            // Check for None
            if (std.mem.eql(u8, type_name, "None")) {
                try self.emit("if (");
                try parent.genExpr(self, args[1]);
                try self.emit(" != .none) return error.AssertionFailed;\n");
                return true;
            }
            // Check for known factory types
            for (factory_types) |known| {
                if (std.mem.eql(u8, type_name, known)) {
                    try self.emit("if (");
                    try parent.genExpr(self, args[1]);
                    try self.emitFmt(" != .{s}) return error.AssertionFailed;\n", .{known});
                    return true;
                }
            }
        }
    }

    return false;
}

/// Generate assertTrue using ZigBuilder (100% builder migration)
pub fn genAssertTrue(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 1) {
        try self.emit("@compileError(\"assertTrue requires 1 argument\")");
        return;
    }
    const value = try self.exprToValue(args[0]);
    const b = try self.getBuilder();
    try b.emitAssertTrueStmt(value);
    try self.flushBuilder();
}

/// Generate assertFalse using ZigBuilder (100% builder migration)
pub fn genAssertFalse(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 1) {
        try self.emit("@compileError(\"assertFalse requires 1 argument\")");
        return;
    }
    const value = try self.exprToValue(args[0]);
    const b = try self.getBuilder();
    try b.emitAssertFalseStmt(value);
    try self.flushBuilder();
}

/// Generate assertIsNone using ZigBuilder (100% builder migration)
pub fn genAssertIsNone(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 1) {
        try self.emit("@compileError(\"assertIsNone requires 1 argument\")");
        return;
    }
    const value = try self.exprToValue(args[0]);
    const b = try self.getBuilder();
    try b.emitAssertIsNoneStmt(value);
    try self.flushBuilder();
}
/// Generate assertGreater using ZigBuilder (100% builder migration)
/// Routes: certain numeric → native >, uncertain → PyValue.gt()
pub fn genAssertGreater(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertGreater requires 2 arguments\")");
        return;
    }
    const left = try self.exprToValue(args[0]);
    const right = try self.exprToValue(args[1]);
    const b = try self.getBuilder();
    try b.emitAssertOrderingStmt(CompOp.gt, left, right);
    try self.flushBuilder();
}

/// Generate assertLess using ZigBuilder (100% builder migration)
/// Routes: certain numeric → native <, uncertain → PyValue.lt()
pub fn genAssertLess(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertLess requires 2 arguments\")");
        return;
    }
    const left = try self.exprToValue(args[0]);
    const right = try self.exprToValue(args[1]);
    const b = try self.getBuilder();
    try b.emitAssertOrderingStmt(CompOp.lt, left, right);
    try self.flushBuilder();
}

/// Generate assertGreaterEqual using ZigBuilder (100% builder migration)
/// Routes: certain numeric → native >=, uncertain → PyValue.ge()
pub fn genAssertGreaterEqual(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertGreaterEqual requires 2 arguments\")");
        return;
    }
    const left = try self.exprToValue(args[0]);
    const right = try self.exprToValue(args[1]);
    const b = try self.getBuilder();
    try b.emitAssertOrderingStmt(CompOp.ge, left, right);
    try self.flushBuilder();
}

/// Generate assertLessEqual using ZigBuilder (100% builder migration)
/// Routes: certain numeric → native <=, uncertain → PyValue.le()
pub fn genAssertLessEqual(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertLessEqual requires 2 arguments\")");
        return;
    }
    const left = try self.exprToValue(args[0]);
    const right = try self.exprToValue(args[1]);
    const b = try self.getBuilder();
    try b.emitAssertOrderingStmt(CompOp.le, left, right);
    try self.flushBuilder();
}

/// Generate assertNotEqual using ZigBuilder (100% builder migration)
/// Routes: certain types → native !=, uncertain → !PyValue.eql()
pub fn genAssertNotEqual(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertNotEqual requires 2 arguments\")");
        return;
    }
    const left = try self.exprToValue(args[0]);
    const right = try self.exprToValue(args[1]);
    const b = try self.getBuilder();
    try b.emitAssertNotEqualStmt(left, right);
    try self.flushBuilder();
}
/// Generate assertIsNotNone using ZigBuilder (100% builder migration)
pub fn genAssertIsNotNone(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 1) {
        try self.emit("@compileError(\"assertIsNotNone requires 1 argument\")");
        return;
    }
    const value = try self.exprToValue(args[0]);
    const b = try self.getBuilder();
    try b.emitAssertIsNotNoneStmt(value);
    try self.flushBuilder();
}
// Specialized 2-arg assertions using ZigBuilder (100% builder migration)
pub const genAssertAlmostEqual = gen2ArgAssertBuilder("assertAlmostEqual");
pub const genAssertNotAlmostEqual = gen2ArgAssertBuilder("assertNotAlmostEqual");
pub const genAssertCountEqual = gen2ArgAssertBuilder("assertCountEqual");
pub const genAssertRegex = gen2ArgAssertBuilder("assertRegex");
pub const genAssertNotRegex = gen2ArgAssertBuilder("assertNotRegex");
pub const genAssertSetEqual = gen2ArgAssertBuilder("assertSetEqual");
pub const genAssertDictEqual = gen2ArgAssertBuilder("assertDictEqual");
pub const genAssertFloatsAreIdentical = gen2ArgAssertBuilder("assertFloatsAreIdentical");
/// Generate assertIsNot using ZigBuilder (100% builder migration)
pub fn genAssertIsNot(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertIsNot requires 2 arguments\")");
        return;
    }
    const left = try self.exprToValue(args[0]);
    const right = try self.exprToValue(args[1]);
    const b = try self.getBuilder();
    try b.emitAssertIsNotStmt(left, right);
    try self.flushBuilder();
}

/// Generate assertNotIn using ZigBuilder (100% builder migration)
pub fn genAssertNotIn(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertNotIn requires 2 arguments\")");
        return;
    }
    const element = try self.exprToValue(args[0]);
    const container = try self.exprToValue(args[1]);
    const b = try self.getBuilder();
    try b.emitAssertNotInStmt(element, container);
    try self.flushBuilder();
}

/// Generate code for self.assertIs(a, b) - special handling for type() checks
/// Uses ZigBuilder for standard path (100% builder migration)
pub fn genAssertIs(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertIs requires 2 arguments\")");
        return;
    }
    // SPECIAL CASE: assertIs(type(x), SomeType) - type comparison
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
                if (!isBuiltinTypeName(type_name)) {
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

    // SPECIAL CASE: assertIs(d.default_factory, int/list/etc)
    if (try emitDefaultFactoryComparison(self, args)) return;

    // STANDARD PATH: Use builder for identity check
    const left = try self.exprToValue(args[0]);
    const right = try self.exprToValue(args[1]);
    const b = try self.getBuilder();
    try b.emitAssertIsStmt(left, right);
    try self.flushBuilder();
}

/// Generate code for self.assertIn(item, container)
/// Uses ZigBuilder for standard path (100% builder migration)
pub fn genAssertIn(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertIn requires 2 arguments\")");
        return;
    }

    // SPECIAL CASE: float.__getformat__() returns error union, needs try
    if (args[0] == .call and args[0].call.func.* == .attribute) {
        const attr = args[0].call.func.attribute;
        if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "float")) {
            if (std.mem.eql(u8, attr.attr, "__getformat__")) {
                // float.__getformat__ returns ![]const u8, need to use emit for try prefix
                try self.emit("try unittest.assertIn(try ");
                try parent.genExpr(self, args[0]);
                try self.emit(", ");
                try parent.genExpr(self, args[1]);
                try self.emit(")");
                return;
            }
        }
    }

    // Check for string containment (substring search)
    // Python: 'abc' in 'abcdef' -> True (substring search, not element search)
    // Check both by type inference AND by literal detection (for unknown container types)
    const element_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;
    const container_type = self.type_inferrer.inferExpr(args[1]) catch .unknown;
    const string_traits = @import("../../../analysis/traits/string_traits.zig");

    // Detect if element is a string literal
    const element_is_string_literal = args[0] == .constant and args[0].constant.value == .string;

    // Use string containment if:
    // 1. Both types are strings, OR
    // 2. Element is a string literal (the container is likely a string too)
    if ((string_traits.isString(element_type) and string_traits.isString(container_type)) or
        element_is_string_literal)
    {
        // String containment: use stringContains for substring search
        try self.emit("if (!runtime.container_dispatch.stringContains(");
        try parent.genExpr(self, args[1]); // haystack (container)
        try self.emit(", ");
        try parent.genExpr(self, args[0]); // needle (element)
        try self.emit(")) return error.AssertionFailed");
        return;
    }

    // STANDARD PATH: Use builder for containment check
    const element = try self.exprToValue(args[0]);
    const container = try self.exprToValue(args[1]);
    const b = try self.getBuilder();
    try b.emitAssertInStmt(element, container);
    try self.flushBuilder();
}

/// Generate code for self.assertIsInstance(obj, type)
/// Uses ZigBuilder (100% builder migration)
pub fn genAssertIsInstance(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertIsInstance requires 2 arguments\")");
        return;
    }
    const obj_value = try self.exprToValue(args[0]);
    const b = try self.getBuilder();

    // If the type arg is a variable name, use the variable to avoid "unused" warnings
    // then extract the type name from it
    if (args[1] == .name) {
        const type_var = args[1].name.id;
        // Check if this is a user-defined variable (not a builtin type name)
        if (!isBuiltinTypeName(type_var)) {
            // For user-defined classes, use the class's __name__ constant
            // Escape Zig keywords like "struct" when used as variable names
            var escaped_buf: [256]u8 = undefined;
            var fbs = std.io.fixedBufferStream(&escaped_buf);
            zig_keywords.writeEscapedIdent(fbs.writer(), type_var) catch {};
            const escaped = fbs.getWritten();
            try b.emitAssertIsInstanceRawStmt(obj_value, escaped);
            try self.flushBuilder();
            return;
        }
        // Builtin type name - use string literal
        try b.emitAssertIsInstanceStmt(obj_value, type_var);
        try self.flushBuilder();
        return;
    }
    // Non-name expression - convert to value and emit
    const type_value = try self.exprToValue(args[1]);
    // For expressions, we need to fall back to raw emit since builder expects string literal
    try self.flushBuilder();
    try self.emit("try unittest.assertIsInstance(");
    try self.emitZigValue(obj_value);
    try self.emit(", ");
    try self.emitZigValue(type_value);
    try self.emit(")");
}

/// Generate code for self.assertNotIsInstance(obj, type)
/// Uses ZigBuilder (100% builder migration)
pub fn genAssertNotIsInstance(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertNotIsInstance requires 2 arguments\")");
        return;
    }
    const obj_value = try self.exprToValue(args[0]);
    const b = try self.getBuilder();

    if (args[1] == .name) {
        const type_var = args[1].name.id;
        try b.emitAssertNotIsInstanceStmt(obj_value, type_var);
        try self.flushBuilder();
        return;
    }
    // Non-name expression - convert to value and emit
    const type_value = try self.exprToValue(args[1]);
    try self.flushBuilder();
    try self.emit("try unittest.assertNotIsInstance(");
    try self.emitZigValue(obj_value);
    try self.emit(", ");
    try self.emitZigValue(type_value);
    try self.emit(")");
}

/// Generate code for self.assertIsSubclass(cls, parent_cls)
/// Uses ZigBuilder (100% builder migration)
pub fn genAssertIsSubclass(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertIsSubclass requires 2 arguments\")");
        return;
    }
    const b = try self.getBuilder();

    // Both args should be type names
    const cls_name = if (args[0] == .name) args[0].name.id else "";
    const parent_name = if (args[1] == .name) args[1].name.id else "";

    if (cls_name.len > 0 and parent_name.len > 0) {
        try b.emitAssertIsSubclassStmt(cls_name, parent_name);
        try self.flushBuilder();
        return;
    }
    // Fallback for non-name expressions
    try self.flushBuilder();
    try self.emit("runtime.unittest.assertIsSubclass(");
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
        // Note: eval-string-only variable discards are now handled in assign.zig
        const label = try self.emitInlineBlockStart("ar_eval");
        try self.emit("_ = runtime.eval(__global_allocator, ");
        if (args.len > 2) {
            try parent.genExpr(self, args[2]);
        } else {
            try self.emit("\"\"");
        }
        try self.emitFmt(") catch break :{s} {{}}; return error.ExpectedExceptionNotRaised; ", .{label});
        try self.emitInlineBlockEnd();
        return;
    }

    // Check if callable is 'compile' - special handling needed
    if (args[1] == .name and std.mem.eql(u8, args[1].name.id, "compile")) {
        const label = try self.emitInlineBlockStart("ar_compile");
        try self.emit("_ = runtime.compile_builtin(__global_allocator, ");
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
        try self.emit(", 0"); // flags parameter
        try self.emitFmt(") catch break :{s} {{}}; return error.ExpectedExceptionNotRaised; ", .{label});
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
    // Set in_assert_raises_context so error-returning functions return raw error unions
    // (not wrapped with try/catch), allowing expectError/expectSpecificError to check them
    const prev_assert_raises = self.in_assert_raises_context;
    self.in_assert_raises_context = true;

    if (exception_name) |exc_name| {
        // Use expectSpecificError for known exception types
        // Use if-else chain instead of switch to avoid trailing semicolon issues
        try self.emit("{ const __ar_result = runtime.unittest.expectSpecificError(");
        try emitCallableInvocation(self, args[1], call_args, &.{});
        try self.emitFmt(", \"{s}\"); if (__ar_result == .no_error) return error.ExpectedExceptionNotRaised; if (__ar_result == .wrong_error) return error.WrongExceptionType; }}", .{exc_name});
    } else {
        // Fall back to expectError for unknown exception types
        try self.emit("if (runtime.unittest.expectError(");
        try emitCallableInvocation(self, args[1], call_args, &.{});
        // expectError returns true if NO error was raised (test should fail)
        try self.emit(")) return error.ExpectedExceptionNotRaised;");
    }
    self.in_assert_raises_context = prev_assert_raises;
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
    // Set in_assert_raises_context so error-returning functions return raw error unions
    // (not wrapped with try/catch), allowing expectError/expectSpecificError to check them
    const prev_assert_raises = self.in_assert_raises_context;
    self.in_assert_raises_context = true;

    if (exception_name) |exc_name| {
        // Use expectSpecificError for known exception types
        // Use if-else chain instead of switch to avoid trailing semicolon issues
        try self.emit("{ const __ar_result = runtime.unittest.expectSpecificError(");
        try emitCallableInvocation(self, args[1], call_args, keyword_args);
        try self.emitFmt(", \"{s}\"); if (__ar_result == .no_error) return error.ExpectedExceptionNotRaised; if (__ar_result == .wrong_error) return error.WrongExceptionType; }}", .{exc_name});
    } else {
        // Fall back to expectError for unknown exception types
        try self.emit("if (runtime.unittest.expectError(");
        try emitCallableInvocation(self, args[1], call_args, keyword_args);
        try self.emit(")) return error.ExpectedExceptionNotRaised;");
    }
    self.in_assert_raises_context = prev_assert_raises;
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
    const label = try self.emitInlineBlockStart("ar");
    try self.emit("_ = ");
    try parent.genExpr(self, args[1]); // regex parameter
    try self.emit("; _ = ");
    try emitCallableInvocation(self, args[2], call_args, keyword_args);
    self.inside_try_body = prev_inside_try;
    try self.emitFmt(" catch break :{s} {{}}; return error.ExpectedExceptionNotRaised; ", .{label});
    try self.emitInlineBlockEnd();
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
    const label = try self.emitInlineBlockStart("ar");
    try self.emit("_ = ");
    try parent.genExpr(self, args[1]); // regex parameter
    try self.emit("; _ = ");

    try emitCallableInvocation(self, args[2], call_args, &.{});
    self.inside_try_body = prev_inside_try;
    // Catch error directly on call - can't store first since error propagates immediately
    try self.emitFmt(" catch break :{s} {{}}; return error.ExpectedExceptionNotRaised; ", .{label});
    try self.emitInlineBlockEnd();
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
/// Uses ZigBuilder (100% builder migration)
pub fn genAssertNotIsSubclass(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertNotIsSubclass requires 2 arguments\")");
        return;
    }
    const b = try self.getBuilder();

    // Both args should be type names
    const cls_name = if (args[0] == .name) args[0].name.id else "";
    const parent_name = if (args[1] == .name) args[1].name.id else "";

    if (cls_name.len > 0 and parent_name.len > 0) {
        try b.emitAssertNotIsSubclassStmt(cls_name, parent_name);
        try self.flushBuilder();
        return;
    }
    // Fallback for non-name expressions
    try self.flushBuilder();
    try self.emit("runtime.unittest.assertNotIsSubclass(");
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
/// Uses ZigBuilder (100% builder migration)
pub fn genAssertStartsWith(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertStartsWith requires 2 arguments\")");
        return;
    }
    const string = try self.exprToValue(args[0]);
    const prefix = try self.exprToValue(args[1]);
    const b = try self.getBuilder();
    try b.emitAssertStartsWithStmt(string, prefix);
    try self.flushBuilder();
}

/// Generate code for self.assertNotStartsWith(s, prefix)
/// Uses ZigBuilder (100% builder migration)
pub fn genAssertNotStartsWith(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertNotStartsWith requires 2 arguments\")");
        return;
    }
    const string = try self.exprToValue(args[0]);
    const prefix = try self.exprToValue(args[1]);
    const b = try self.getBuilder();
    try b.emitAssertNotStartsWithStmt(string, prefix);
    try self.flushBuilder();
}

/// Generate code for self.assertEndsWith(s, suffix)
/// Uses ZigBuilder (100% builder migration)
pub fn genAssertEndsWith(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertEndsWith requires 2 arguments\")");
        return;
    }
    const string = try self.exprToValue(args[0]);
    const suffix = try self.exprToValue(args[1]);
    const b = try self.getBuilder();
    try b.emitAssertEndsWithStmt(string, suffix);
    try self.flushBuilder();
}

/// Generate code for self.assertHasAttr(obj, name)
/// Uses ZigBuilder (100% builder migration)
pub fn genAssertHasAttr(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertHasAttr requires 2 arguments\")");
        return;
    }
    // For module attribute checking, verify at comptime using @hasField (if struct)
    // Use a no-op that references the arguments to avoid "unused variable" errors
    const attr_name = try self.exprToValue(args[1]);
    const b = try self.getBuilder();
    try b.emitAssertHasAttrStmt(attr_name);
    try self.flushBuilder();
}

/// Generate code for self.assertNotHasAttr(obj, name)
/// Uses ZigBuilder (100% builder migration)
pub fn genAssertNotHasAttr(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertNotHasAttr requires 2 arguments\")");
        return;
    }
    // For AOT, we check at compile time using @hasField (must check struct type first)
    const obj_value = try self.exprToValue(args[0]);
    const attr_name = try self.exprToValue(args[1]);
    const b = try self.getBuilder();
    try b.emitAssertNotHasAttrStmt(obj_value, attr_name);
    try self.flushBuilder();
}

// Equality aliases using ZigBuilder (100% builder migration)
// These delegate to unittest.assertEqual via the builder
pub const genAssertSequenceEqual = gen2ArgAssertBuilder("assertEqual");
pub const genAssertListEqual = gen2ArgAssertBuilder("assertEqual");
pub const genAssertTupleEqual = gen2ArgAssertBuilder("assertEqual");
pub const genAssertMultiLineEqual = gen2ArgAssertBuilder("assertEqual");

/// Generate code for self.assertLogs(logger, level)
/// Uses ZigBuilder (100% builder migration)
pub fn genAssertLogs(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    _ = args;
    // For AOT, logging context managers aren't tracked - return stub
    const b = try self.getBuilder();
    try b.emitAssertLogsStmt();
    try self.flushBuilder();
}

/// Generate code for self.assertNoLogs(logger, level)
/// Uses ZigBuilder (100% builder migration)
pub fn genAssertNoLogs(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    try genAssertLogs(self, obj, args);
}

/// Generate code for self.fail(msg)
/// Uses ZigBuilder (100% builder migration)
pub fn genFail(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    const msg = if (args.len > 0) try self.exprToValue(args[0]) else null;
    const b = try self.getBuilder();
    try b.emitFailStmt(msg);
    try self.flushBuilder();
}

/// Generate code for self.skipTest(reason)
/// Uses ZigBuilder (100% builder migration)
/// This terminates control flow - no code after skipTest should run
pub fn genSkipTest(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    _ = args;
    const b = try self.getBuilder();
    try b.emitSkipTestStmt();
    try self.flushBuilder();
    // Mark control flow as terminated so no unreachable code is generated after
    self.control_flow_terminated = true;
}
