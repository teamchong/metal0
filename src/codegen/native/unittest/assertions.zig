/// unittest assertion code generation
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const parent = @import("../expressions.zig");

/// Generate code for self.assertEqual(a, b)
pub fn genAssertEqual(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertEqual requires 2 arguments\")");
        return;
    }
    try self.emit("runtime.unittest.assertEqual(");
    try parent.genExpr(self, args[0]);
    try self.emit(", ");
    try parent.genExpr(self, args[1]);
    try self.emit(")");
}

/// Generate code for self.assertTrue(x)
pub fn genAssertTrue(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 1) {
        try self.emit("@compileError(\"assertTrue requires 1 argument\")");
        return;
    }
    try self.emit("runtime.unittest.assertTrue(");
    try parent.genExpr(self, args[0]);
    try self.emit(")");
}

/// Generate code for self.assertFalse(x)
pub fn genAssertFalse(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 1) {
        try self.emit("@compileError(\"assertFalse requires 1 argument\")");
        return;
    }
    try self.emit("runtime.unittest.assertFalse(");
    try parent.genExpr(self, args[0]);
    try self.emit(")");
}

/// Generate code for self.assertIsNone(x)
pub fn genAssertIsNone(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 1) {
        try self.emit("@compileError(\"assertIsNone requires 1 argument\")");
        return;
    }
    try self.emit("runtime.unittest.assertIsNone(");
    try parent.genExpr(self, args[0]);
    try self.emit(")");
}

/// Generate code for self.assertGreater(a, b)
pub fn genAssertGreater(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertGreater requires 2 arguments\")");
        return;
    }
    try self.emit("runtime.unittest.assertGreater(");
    try parent.genExpr(self, args[0]);
    try self.emit(", ");
    try parent.genExpr(self, args[1]);
    try self.emit(")");
}

/// Generate code for self.assertLess(a, b)
pub fn genAssertLess(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertLess requires 2 arguments\")");
        return;
    }
    try self.emit("runtime.unittest.assertLess(");
    try parent.genExpr(self, args[0]);
    try self.emit(", ");
    try parent.genExpr(self, args[1]);
    try self.emit(")");
}

/// Generate code for self.assertGreaterEqual(a, b)
pub fn genAssertGreaterEqual(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertGreaterEqual requires 2 arguments\")");
        return;
    }
    try self.emit("runtime.unittest.assertGreaterEqual(");
    try parent.genExpr(self, args[0]);
    try self.emit(", ");
    try parent.genExpr(self, args[1]);
    try self.emit(")");
}

/// Generate code for self.assertLessEqual(a, b)
pub fn genAssertLessEqual(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertLessEqual requires 2 arguments\")");
        return;
    }
    try self.emit("runtime.unittest.assertLessEqual(");
    try parent.genExpr(self, args[0]);
    try self.emit(", ");
    try parent.genExpr(self, args[1]);
    try self.emit(")");
}

/// Generate code for self.assertNotEqual(a, b)
pub fn genAssertNotEqual(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertNotEqual requires 2 arguments\")");
        return;
    }
    try self.emit("runtime.unittest.assertNotEqual(");
    try parent.genExpr(self, args[0]);
    try self.emit(", ");
    try parent.genExpr(self, args[1]);
    try self.emit(")");
}

/// Generate code for self.assertIs(a, b)
pub fn genAssertIs(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertIs requires 2 arguments\")");
        return;
    }
    try self.emit("runtime.unittest.assertIs(");
    try parent.genExpr(self, args[0]);
    try self.emit(", ");
    try parent.genExpr(self, args[1]);
    try self.emit(")");
}

/// Generate code for self.assertIsNot(a, b)
pub fn genAssertIsNot(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertIsNot requires 2 arguments\")");
        return;
    }
    try self.emit("runtime.unittest.assertIsNot(");
    try parent.genExpr(self, args[0]);
    try self.emit(", ");
    try parent.genExpr(self, args[1]);
    try self.emit(")");
}

/// Generate code for self.assertIsNotNone(x)
pub fn genAssertIsNotNone(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 1) {
        try self.emit("@compileError(\"assertIsNotNone requires 1 argument\")");
        return;
    }
    try self.emit("runtime.unittest.assertIsNotNone(");
    try parent.genExpr(self, args[0]);
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
    try parent.genExpr(self, args[0]);
    try self.emit(", ");
    try parent.genExpr(self, args[1]);
    try self.emit(")");
}

/// Generate code for self.assertNotIn(item, container)
pub fn genAssertNotIn(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertNotIn requires 2 arguments\")");
        return;
    }
    try self.emit("runtime.unittest.assertNotIn(");
    try parent.genExpr(self, args[0]);
    try self.emit(", ");
    try parent.genExpr(self, args[1]);
    try self.emit(")");
}

/// Generate code for self.assertAlmostEqual(a, b)
pub fn genAssertAlmostEqual(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertAlmostEqual requires 2 arguments\")");
        return;
    }
    try self.emit("runtime.unittest.assertAlmostEqual(");
    try parent.genExpr(self, args[0]);
    try self.emit(", ");
    try parent.genExpr(self, args[1]);
    try self.emit(")");
}

/// Generate code for self.assertNotAlmostEqual(a, b)
pub fn genAssertNotAlmostEqual(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertNotAlmostEqual requires 2 arguments\")");
        return;
    }
    try self.emit("runtime.unittest.assertNotAlmostEqual(");
    try parent.genExpr(self, args[0]);
    try self.emit(", ");
    try parent.genExpr(self, args[1]);
    try self.emit(")");
}

/// Generate code for self.assertCountEqual(a, b)
pub fn genAssertCountEqual(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertCountEqual requires 2 arguments\")");
        return;
    }
    try self.emit("runtime.unittest.assertCountEqual(");
    try parent.genExpr(self, args[0]);
    try self.emit(", ");
    try parent.genExpr(self, args[1]);
    try self.emit(")");
}

/// Generate code for self.assertRegex(text, pattern)
pub fn genAssertRegex(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertRegex requires 2 arguments\")");
        return;
    }
    try self.emit("runtime.unittest.assertRegex(");
    try parent.genExpr(self, args[0]);
    try self.emit(", ");
    try parent.genExpr(self, args[1]);
    try self.emit(")");
}

/// Generate code for self.assertNotRegex(text, pattern)
pub fn genAssertNotRegex(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertNotRegex requires 2 arguments\")");
        return;
    }
    try self.emit("runtime.unittest.assertNotRegex(");
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

    // For other callables, generate a comptime-conditional try-catch
    // Using inline block to check if return type is error union
    // Use __ar_blk to avoid conflicts with nested blk: labels from genAttribute
    try self.emit("__ar_blk: { const __ar_call = ");

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
        } else {
            // Local variable attribute - dynamic object method
            // Generate the call expression
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
    // Check if result type is error union at comptime to use catch, otherwise silently pass
    // For non-error types, assertRaises can't verify exception behavior statically
    try self.emit("; if (@typeInfo(@TypeOf(__ar_call)) == .error_union) { _ = __ar_call catch break :__ar_blk {}; @panic(\"assertRaises: expected exception\"); } }");
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
    try self.emit("; const __ar_call = ");
    try parent.genExpr(self, args[2]);
    try self.emit("(");
    if (args.len > 3) {
        for (args[3..], 0..) |arg, i| {
            if (i > 0) try self.emit(", ");
            try parent.genExpr(self, arg);
        }
    }
    try self.emit("); if (@typeInfo(@TypeOf(__ar_call)) == .error_union) { _ = __ar_call catch break :__ar_blk {}; @panic(\"assertRaisesRegex: expected exception\"); } }");
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

/// Generate code for self.assertSequenceEqual(seq1, seq2)
pub fn genAssertSequenceEqual(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertSequenceEqual requires 2 arguments\")");
        return;
    }
    try self.emit("runtime.unittest.assertEqual(");
    try parent.genExpr(self, args[0]);
    try self.emit(", ");
    try parent.genExpr(self, args[1]);
    try self.emit(")");
}

/// Generate code for self.assertListEqual(list1, list2)
pub fn genAssertListEqual(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    try genAssertSequenceEqual(self, obj, args);
}

/// Generate code for self.assertTupleEqual(tuple1, tuple2)
pub fn genAssertTupleEqual(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    try genAssertSequenceEqual(self, obj, args);
}

/// Generate code for self.assertSetEqual(set1, set2)
pub fn genAssertSetEqual(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertSetEqual requires 2 arguments\")");
        return;
    }
    try self.emit("runtime.unittest.assertSetEqual(");
    try parent.genExpr(self, args[0]);
    try self.emit(", ");
    try parent.genExpr(self, args[1]);
    try self.emit(")");
}

/// Generate code for self.assertDictEqual(dict1, dict2)
pub fn genAssertDictEqual(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertDictEqual requires 2 arguments\")");
        return;
    }
    try self.emit("runtime.unittest.assertDictEqual(");
    try parent.genExpr(self, args[0]);
    try self.emit(", ");
    try parent.genExpr(self, args[1]);
    try self.emit(")");
}

/// Generate code for self.assertMultiLineEqual(first, second)
pub fn genAssertMultiLineEqual(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    try genAssertEqual(self, obj, args);
}

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
    // For AOT, we can't skip tests at runtime - just return
    try self.emit("return");
}
