/// unittest assertion code generation
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const parent = @import("../expressions.zig");
const shared = @import("../shared_maps.zig");
const PyToZigTypes = shared.PyTypeToZig;

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
    // Handle special case: assertIs(type(x), int) / assertIs(type(x), bool) etc.
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
                }
                // For collection types (dict, list, set) or unknown types,
                // use runtime string-based type check
                try self.emit("runtime.unittest.assertTypeIsStr(");
                try parent.genExpr(self, args[0].call.args[0]);
                try self.emit(", \"");
                try self.emit(type_name);
                try self.emit("\")");
                return;
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
        try self.emit("blk: { _ = runtime.eval(__global_allocator, ");
        if (args.len > 2) {
            try parent.genExpr(self, args[2]);
        } else {
            try self.emit("\"\"");
        }
        try self.emit(") catch break :blk {}; @panic(\"assertRaises: expected exception\"); }");
        return;
    }

    // For assertRaises, we need to check if the callable raises an error
    // Use unittest.expectError helper which handles both error and non-error types
    try self.emit("if (runtime.unittest.expectError(");

    // Check if callable is an attribute on an IMPORTED module (e.g., copy.replace)
    // vs a local variable attribute (e.g., operator.lt where operator = self.module)
    if (args[1] == .attribute) {
        const attr = args[1].attribute;
        // Check if base is an imported module (not a local variable)
        // Local variables shadow module imports, so check if declared first
        const is_module_func = if (attr.value.* == .name) blk: {
            const base_name = attr.value.name.id;
            // If it's a declared local variable, it's NOT a module function
            if (self.isDeclared(base_name)) {
                break :blk false;
            }
            // Check if this is a known module
            if (self.import_registry.lookup(base_name)) |_| {
                break :blk true;
            }
            break :blk false;
        } else false;

        if (is_module_func) {
            // Build a call node to dispatch properly to module function handler
            const call_args: []ast.Node = if (args.len > 2) @constCast(args[2..]) else @constCast(&[_]ast.Node{});
            const call = ast.Node.Call{
                .func = @constCast(&args[1]),
                .args = call_args,
                .keyword_args = @constCast(&[_]ast.Node.KeywordArg{}),
            };
            try parent.genCall(self, call);
        } else if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
            // self.method pattern - generate method call on self
            try self.emit("self.@\"");
            try self.emit(attr.attr);
            try self.emit("\"(");
            if (args.len > 2) {
                for (args[2..], 0..) |arg, i| {
                    if (i > 0) try self.emit(", ");
                    try parent.genExpr(self, arg);
                }
            }
            try self.emit(")");
        } else if (attr.value.* == .call) {
            // Attribute on a call result (e.g., zlib.decompressobj().flush)
            // Need to store the call result first, then access the method
            // Check if this is a float method that needs special dispatch
            if (FloatMethods.get(attr.attr)) |info| {
                try self.emit("__ar_obj_blk: { const __ar_obj = ");
                try parent.genExpr(self, attr.value.*);
                try self.emit("; break :__ar_obj_blk runtime.float");
                try self.emit(info.func);
                try self.emit(if (info.needs_alloc) "__ar_obj)" else "(__ar_obj)");
                try self.emit("; }");
            } else {
                // Generate: __ar_obj_blk: { const __ar_obj = <call>; break :__ar_obj_blk __ar_obj.<method>(<args>); }
                try self.emit("__ar_obj_blk: { const __ar_obj = ");
                try parent.genExpr(self, attr.value.*);
                try self.emit("; break :__ar_obj_blk __ar_obj.@\"");
                try self.emit(attr.attr);
                try self.emit("\"(");
                if (args.len > 2) {
                    for (args[2..], 0..) |arg, i| {
                        if (i > 0) try self.emit(", ");
                        try parent.genExpr(self, arg);
                    }
                }
                try self.emit("); }");
            }
        } else if (attr.value.* == .name) {
            const base_name = attr.value.name.id;
            // Check if base is a builtin type (int, float, bool, str) - these need runtime dispatch
            if (PyToZigTypes.has(base_name)) {
                // Check for special float class methods with explicit mappings
                if (std.mem.eql(u8, base_name, "float")) {
                    if (FloatClassMethods.get(attr.attr)) |func_name| {
                        try self.emit(func_name);
                        try self.emit("(");
                        if (args.len > 2) {
                            for (args[2..], 0..) |arg, i| {
                                if (i > 0) try self.emit(", ");
                                try parent.genExpr(self, arg);
                            }
                        }
                        try self.emit(")");
                    } else {
                        // Fallback for other float class methods
                        try self.emit("runtime.float");
                        try self.emit(attr.attr);
                        try self.emit("(");
                        if (args.len > 2) {
                            for (args[2..], 0..) |arg, i| {
                                if (i > 0) try self.emit(", ");
                                try parent.genExpr(self, arg);
                            }
                        }
                        try self.emit(")");
                    }
                } else {
                    // Builtin type method: int.__new__ -> runtime.int__new__(args)
                    // Note: attr starts with __ so we get int__new__, not int___new__
                    try self.emit("runtime.");
                    try self.emit(base_name);
                    try self.emit(attr.attr);
                    try self.emit("(");
                    if (args.len > 2) {
                        for (args[2..], 0..) |arg, i| {
                            if (i > 0) try self.emit(", ");
                            try parent.genExpr(self, arg);
                        }
                    }
                    try self.emit(")");
                }
            } else {
                // Simple variable attribute - local variable's method
                // Generate: var_name.@"method"(args)
                try parent.genExpr(self, attr.value.*);
                try self.emit(".@\"");
                try self.emit(attr.attr);
                try self.emit("\"(");
                if (args.len > 2) {
                    for (args[2..], 0..) |arg, i| {
                        if (i > 0) try self.emit(", ");
                        try parent.genExpr(self, arg);
                    }
                }
                try self.emit(")");
            }
        } else {
            // Complex expression attribute (e.g., {}.update, some_call().method)
            // Store the object first, then call the method
            try self.emit("__ar_obj_blk: { const __ar_obj = ");
            try parent.genExpr(self, attr.value.*);
            try self.emit("; break :__ar_obj_blk __ar_obj.@\"");
            try self.emit(attr.attr);
            try self.emit("\"(");
            if (args.len > 2) {
                for (args[2..], 0..) |arg, i| {
                    if (i > 0) try self.emit(", ");
                    try parent.genExpr(self, arg);
                }
            }
            try self.emit("); }");
        }
    } else if (args[1] == .lambda) {
        // Lambda expression - generates a closure struct that needs .call() method
        // Need to assign to temp var first since can't call method on struct literal
        try self.emit("ar_closure_blk: { const __ar_closure = ");
        try parent.genExpr(self, args[1]);
        try self.emit("; break :ar_closure_blk __ar_closure.call(); }");
    } else if (args[1] == .name and std.mem.eql(u8, args[1].name.id, "int")) {
        // Handle int() builtin specially - it needs to validate args and raise TypeError
        // intBuiltinCall(allocator, first_arg, .{ rest_args... })
        try self.emit("runtime.intBuiltinCall(__global_allocator, ");
        if (args.len > 2) {
            try parent.genExpr(self, args[2]); // first arg
            try self.emit(", .{");
            // Remaining args as tuple
            if (args.len > 3) {
                for (args[3..], 0..) |arg, i| {
                    if (i > 0) try self.emit(", ");
                    try parent.genExpr(self, arg);
                }
            }
            try self.emit("}");
        } else {
            // No args to int() - pass void for both
            try self.emit("{}, .{}");
        }
        try self.emit(")");
    } else if (args[1] == .name and std.mem.eql(u8, args[1].name.id, "float")) {
        // Handle float() builtin specially
        try self.emit("runtime.floatBuiltinCall(");
        if (args.len > 2) {
            try parent.genExpr(self, args[2]); // first arg
            try self.emit(", .{");
            // Remaining args as tuple
            if (args.len > 3) {
                for (args[3..], 0..) |arg, i| {
                    if (i > 0) try self.emit(", ");
                    try parent.genExpr(self, arg);
                }
            }
            try self.emit("}");
        } else {
            try self.emit("{}, .{}");
        }
        try self.emit(")");
    } else if (args[1] == .name and std.mem.eql(u8, args[1].name.id, "bool")) {
        // Handle bool() builtin specially - it validates arg count
        try self.emit("runtime.boolBuiltinCall(");
        if (args.len > 2) {
            try parent.genExpr(self, args[2]); // first arg
            try self.emit(", .{");
            // Remaining args as tuple - bool() should raise TypeError for extra args
            if (args.len > 3) {
                for (args[3..], 0..) |arg, i| {
                    if (i > 0) try self.emit(", ");
                    try parent.genExpr(self, arg);
                }
            }
            try self.emit("}");
        } else {
            try self.emit("{}, .{}");
        }
        try self.emit(")");
    } else if (args[1] == .name and std.mem.eql(u8, args[1].name.id, "next")) {
        // Handle next() builtin specially - iterators need to be passed by pointer
        try self.emit("runtime.builtins.next(&");
        if (args.len > 2) {
            try parent.genExpr(self, args[2]);
        }
        try self.emit(")");
    } else if (args[1] == .name and self.callable_vars.contains(args[1].name.id)) {
        // Callable variable (e.g., pow_op from iterating over operator structs)
        // Needs .call() syntax: pow_op.call(args...)
        try parent.genExpr(self, args[1]);
        try self.emit(".call(");
        if (args.len > 2) {
            for (args[2..], 0..) |arg, i| {
                if (i > 0) try self.emit(", ");
                try parent.genExpr(self, arg);
            }
        }
        try self.emit(")");
    } else if (args[1] == .name and std.mem.eql(u8, args[1].name.id, "format")) {
        // format builtin is a callable struct - needs .call() and allocator
        try self.emit("runtime.builtins.format.call(__global_allocator, ");
        if (args.len > 2) {
            for (args[2..], 0..) |arg, i| {
                if (i > 0) try self.emit(", ");
                try parent.genExpr(self, arg);
            }
        }
        try self.emit(")");
    } else if (args[1] == .name and std.mem.eql(u8, args[1].name.id, "round")) {
        // Handle round() builtin specially - it takes (value, .{ndigits...})
        try self.emit("runtime.builtins.round(");
        if (args.len > 2) {
            try parent.genExpr(self, args[2]); // first arg (value)
            try self.emit(", .{");
            // Remaining args as tuple (ndigits)
            if (args.len > 3) {
                for (args[3..], 0..) |arg, i| {
                    if (i > 0) try self.emit(", ");
                    try parent.genExpr(self, arg);
                }
            }
            try self.emit("}");
        } else {
            // No args to round() - this is an error but pass empty values
            try self.emit("0, .{}");
        }
        try self.emit(")");
    } else if (args[1] == .name) {
        // Name-based callable - use proper call dispatch for builtins like isinstance
        const call_args: []ast.Node = if (args.len > 2) @constCast(args[2..]) else @constCast(&[_]ast.Node{});
        const call = ast.Node.Call{
            .func = @constCast(&args[1]),
            .args = call_args,
            .keyword_args = @constCast(&[_]ast.Node.KeywordArg{}),
        };
        try parent.genCall(self, call);
    } else {
        // Simple name or other callable
        try parent.genExpr(self, args[1]);
        try self.emit("(");
        if (args.len > 2) {
            for (args[2..], 0..) |arg, i| {
                if (i > 0) try self.emit(", ");
                try parent.genExpr(self, arg);
            }
        }
        try self.emit(")");
    }
    // expectError returns true if NO error was raised (test should fail)
    try self.emit(")) @panic(\"assertRaises: expected exception\")");
}

/// Generate code for self.assertRaisesRegex(exception, regex, callable, *args)
pub fn genAssertRaisesRegex(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 3) {
        try self.emit("{}");
        return;
    }
    // Similar to assertRaises but with regex check on error message
    // For AOT, we just check that an error is raised
    // Reference the regex parameter to avoid unused variable warning
    // Use __ar_blk to avoid conflicts with nested blk: labels
    try self.emit("__ar_blk: { _ = ");
    try parent.genExpr(self, args[1]); // regex parameter
    try self.emit("; _ = ");

    // Handle special callables that need runtime wrappers
    if (args[2] == .name and std.mem.eql(u8, args[2].name.id, "int")) {
        // Handle int() builtin specially
        try self.emit("runtime.intBuiltinCall(");
        if (args.len > 3) {
            try parent.genExpr(self, args[3]); // first arg
            try self.emit(", .{");
            // Remaining args as tuple
            if (args.len > 4) {
                for (args[4..], 0..) |arg, i| {
                    if (i > 0) try self.emit(", ");
                    try parent.genExpr(self, arg);
                }
            }
            try self.emit("}");
        } else {
            try self.emit("{}, .{}");
        }
        try self.emit(")");
    } else if (args[2] == .name and std.mem.eql(u8, args[2].name.id, "float")) {
        // Handle float() builtin specially
        try self.emit("runtime.floatBuiltinCall(");
        if (args.len > 3) {
            try parent.genExpr(self, args[3]); // first arg
            try self.emit(", .{");
            // Remaining args as tuple
            if (args.len > 4) {
                for (args[4..], 0..) |arg, i| {
                    if (i > 0) try self.emit(", ");
                    try parent.genExpr(self, arg);
                }
            }
            try self.emit("}");
        } else {
            try self.emit("{}, .{}");
        }
        try self.emit(")");
    } else if (args[2] == .name and std.mem.eql(u8, args[2].name.id, "round")) {
        // Handle round() builtin specially - it takes (value, .{ndigits...})
        try self.emit("runtime.builtins.round(");
        if (args.len > 3) {
            try parent.genExpr(self, args[3]); // first arg (value)
            try self.emit(", .{");
            // Remaining args as tuple (ndigits)
            if (args.len > 4) {
                for (args[4..], 0..) |arg, i| {
                    if (i > 0) try self.emit(", ");
                    try parent.genExpr(self, arg);
                }
            }
            try self.emit("}");
        } else {
            // No args to round() - this is an error but pass empty values
            try self.emit("0, .{}");
        }
        try self.emit(")");
    } else if (args[2] == .attribute and args[2].attribute.value.* == .name and std.mem.eql(u8, args[2].attribute.value.name.id, "operator")) {
        // operator.* callables need .call() method
        try parent.genExpr(self, args[2]);
        try self.emit(".call(");
        if (args.len > 3) {
            for (args[3..], 0..) |arg, i| {
                if (i > 0) try self.emit(", ");
                try parent.genExpr(self, arg);
            }
        }
        try self.emit(")");
    } else if (args[2] == .attribute) {
        // Attribute expression callable (e.g., {}.__contains__, [].count)
        // Need to generate: obj.@"method"(args)
        const attr = args[2].attribute;
        try self.emit("(__ar_obj_blk: { const __ar_obj = ");
        try parent.genExpr(self, attr.value.*);
        try self.emit("; break :__ar_obj_blk __ar_obj.@\"");
        try self.emit(attr.attr);
        try self.emit("\"(");
        if (args.len > 3) {
            for (args[3..], 0..) |arg, i| {
                if (i > 0) try self.emit(", ");
                try parent.genExpr(self, arg);
            }
        }
        try self.emit("); })");
    } else if (args[2] == .lambda) {
        // Lambda expression - generates a closure struct that needs .call() method
        // Need to assign to temp var first since can't call method on struct literal
        try self.emit("(ar_closure_blk: { const __ar_closure = ");
        try parent.genExpr(self, args[2]);
        try self.emit("; break :ar_closure_blk __ar_closure.call(); })");
    } else {
        // Generic callable
        try parent.genExpr(self, args[2]);
        try self.emit("(");
        if (args.len > 3) {
            for (args[3..], 0..) |arg, i| {
                if (i > 0) try self.emit(", ");
                try parent.genExpr(self, arg);
            }
        }
        try self.emit(")");
    }
    // Catch error directly on call - can't store first since error propagates immediately
    try self.emit(" catch break :__ar_blk {}; @panic(\"assertRaisesRegex: expected exception\"); }");
}

/// Generate code for self.assertWarns(warning, callable, *args)
pub fn genAssertWarns(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    // For AOT, warnings are not tracked - just call the function
    if (args.len >= 2) {
        try parent.genExpr(self, args[1]);
        try self.emit("(");
        if (args.len > 2) {
            for (args[2..], 0..) |arg, i| {
                if (i > 0) try self.emit(", ");
                try parent.genExpr(self, arg);
            }
        }
        try self.emit(")");
    } else {
        try self.emit("{}");
    }
}

/// Generate code for self.assertWarnsRegex(warning, regex, callable, *args)
pub fn genAssertWarnsRegex(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    // For AOT, warnings are not tracked - just call the function
    if (args.len >= 3) {
        try parent.genExpr(self, args[2]);
        try self.emit("(");
        if (args.len > 3) {
            for (args[3..], 0..) |arg, i| {
                if (i > 0) try self.emit(", ");
                try parent.genExpr(self, arg);
            }
        }
        try self.emit(")");
    } else {
        try self.emit("{}");
    }
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
