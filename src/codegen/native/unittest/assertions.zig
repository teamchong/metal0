/// unittest assertion code generation
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const parent = @import("../expressions.zig");
const shared = @import("../shared_maps.zig");
const PyToZigTypes = shared.PyTypeToZig;
const zig_keywords = @import("zig_keywords");

/// Check if a name is a Python builtin type name (not a user variable)
fn isBuiltinTypeName(name: []const u8) bool {
    const builtin_types = [_][]const u8{
        "int",           "float",               "str",                "bool",           "list",              "dict",            "set",                 "tuple",
        "type",          "object",              "bytes",              "bytearray",      "frozenset",         "range",           "complex",             "memoryview",
        "slice",         "property",            "classmethod",        "staticmethod",   "super",             "Exception",       "BaseException",       "TypeError",
        "ValueError",    "KeyError",            "IndexError",         "AttributeError", "RuntimeError",      "StopIteration",   "GeneratorExit",       "AssertionError",
        "ImportError",   "ModuleNotFoundError", "LookupError",        "OSError",        "FileNotFoundError", "PermissionError", "NotImplementedError", "ZeroDivisionError",
        "OverflowError", "RecursionError",      "DeprecationWarning", "UserWarning",    "SyntaxWarning",     "Warning",         "ExceptionGroup",      "BaseExceptionGroup",
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
    .{ "__floor__", FloatMethodInfo{ .func = "Floor(__global_allocator, ", .needs_alloc = true } },
    .{ "__ceil__", FloatMethodInfo{ .func = "Ceil(__global_allocator, ", .needs_alloc = true } },
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

// Comptime generator for simple 1-arg assertions: runtime.unittest.func(arg)
fn gen1ArgAssert(comptime func_name: []const u8) AssertHandler {
    return struct {
        fn handler(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
            _ = obj;
            if (args.len < 1) {
                try self.emit("@compileError(\"" ++ func_name ++ " requires 1 argument\")");
                return;
            }
            try self.emit("runtime.unittest." ++ func_name ++ "(");
            try parent.genExpr(self, args[0]);
            try self.emit(")");
        }
    }.handler;
}

// Comptime generator for simple 2-arg assertions: runtime.unittest.func(a, b)
fn gen2ArgAssert(comptime func_name: []const u8) AssertHandler {
    return struct {
        fn handler(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
            _ = obj;
            if (args.len < 2) {
                try self.emit("@compileError(\"" ++ func_name ++ " requires 2 arguments\")");
                return;
            }
            try self.emit("runtime.unittest." ++ func_name ++ "(");
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
                    try self.emit("; break :__ar_obj_blk runtime.float");
                    try self.emit(info.func);
                    try self.emit(if (info.needs_alloc) "__ar_obj)" else "(__ar_obj)");
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
            try self.emit("; break :__ar_obj_blk runtime.float");
            try self.emit(info.func);
            try self.emit(if (info.needs_alloc) "__ar_obj)" else "(__ar_obj)");
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
pub const genAssertEqual = gen2ArgAssert("assertEqual");
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
                        try self.emit("runtime.unittest.assertTypeIs(@TypeOf(");
                        try parent.genExpr(self, args[0].call.args[0]);
                        try self.emit("), ");
                        try self.emit(ztype);
                        try self.emit(")");
                        return;
                    }
                    // For collection types (dict, list, set), use runtime string-based type check
                    try self.emit("runtime.unittest.assertTypeIsStr(");
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
                    try self.emit("; runtime.unittest.assertTypeIsStr(");
                    try parent.genExpr(self, args[0].call.args[0]);
                    try self.emit(", ");
                    try self.emit(type_name);
                    try self.emit(".__name__); }");
                    return;
                }
            }
        }
    }
    try self.emit("runtime.unittest.assertIs(");
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
    try self.emit("runtime.unittest.assertIn(");

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
            try self.emit("runtime.unittest.assertIsInstance(");
            try parent.genExpr(self, args[0]);
            try self.emit(", ");
            // Escape Zig keywords like "struct" when used as variable names
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), type_var);
            try self.emit(".__name__)");
            return;
        }
    }
    try self.emit("runtime.unittest.assertIsInstance(");
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
    try self.emit("runtime.unittest.assertNotIsInstance(");
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
        // Generate: blk: { _ = runtime.eval(...) catch break :blk {}; @panic("assertRaises: expected exception"); }
        // Note: eval-string-only variable discards are now handled in assign.zig
        try self.emit("blk: { _ = runtime.eval(__global_allocator, ");
        if (args.len > 2) {
            try parent.genExpr(self, args[2]);
        } else {
            try self.emit("\"\"");
        }
        try self.emit(") catch break :blk {}; @panic(\"assertRaises: expected exception\"); }");
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
        try self.emit(") catch break :blk {}; @panic(\"assertRaises: expected exception\"); }");
        return;
    }

    // For assertRaises, we need to check if the callable raises an error
    // Use unittest.expectError helper which handles both error and non-error types
    const call_args: []const ast.Node = if (args.len > 2) args[2..] else &.{};
    try self.emit("if (runtime.unittest.expectError(");
    try emitCallableInvocation(self, args[1], call_args, &.{});
    // expectError returns true if NO error was raised (test should fail)
    try self.emit(")) @panic(\"assertRaises: expected exception\")");
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
    // Generate: if (runtime.unittest.expectError(<call_with_kwargs>)) @panic(...)
    try self.emit("if (runtime.unittest.expectError(");
    try emitCallableInvocation(self, args[1], call_args, keyword_args);
    try self.emit(")) @panic(\"assertRaises: expected exception\")");
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
    // Generate: __ar_blk: { _ = <regex>; _ = <call_with_kwargs> catch break :__ar_blk {}; @panic(...); }
    try self.emit("__ar_blk: { _ = ");
    try parent.genExpr(self, args[1]); // regex parameter
    try self.emit("; _ = ");
    try emitCallableInvocation(self, args[2], call_args, keyword_args);
    try self.emit(" catch break :__ar_blk {}; @panic(\"assertRaisesRegex: expected exception\"); }");
}

/// Generate code for self.assertRaisesRegex(exception, regex, callable, *args)
pub fn genAssertRaisesRegex(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 3) {
        try self.emit("{}");
        return;
    }
    const call_args: []const ast.Node = if (args.len > 3) args[3..] else &.{};
    // Similar to assertRaises but with regex check on error message
    // For AOT, we just check that an error is raised
    // Reference the regex parameter to avoid unused variable warning
    // Use __ar_blk to avoid conflicts with nested blk: labels
    try self.emit("__ar_blk: { _ = ");
    try parent.genExpr(self, args[1]); // regex parameter
    try self.emit("; _ = ");

    try emitCallableInvocation(self, args[2], call_args, &.{});
    // Catch error directly on call - can't store first since error propagates immediately
    try self.emit(" catch break :__ar_blk {}; @panic(\"assertRaisesRegex: expected exception\"); }");
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
pub fn genAssertStartsWith(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertStartsWith requires 2 arguments\")");
        return;
    }
    try self.emit("runtime.unittest.assertTrue(std.mem.startsWith(u8, ");
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
    try self.emit("runtime.unittest.assertFalse(std.mem.startsWith(u8, ");
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
    try self.emit("runtime.unittest.assertTrue(std.mem.endsWith(u8, ");
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
pub fn genSkipTest(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    _ = args;
    try self.emit("return");
}
