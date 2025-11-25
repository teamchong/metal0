/// unittest assertion code generation
const std = @import("std");
const ast = @import("../../../ast.zig");
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

/// Generate code for self.assertRaises(exception_type, callable, *args)
pub fn genAssertRaises(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;
    if (args.len < 2) {
        try self.emit("@compileError(\"assertRaises requires at least 2 arguments: exception_type, callable\")");
        return;
    }
    try self.emit("runtime.unittest.assertRaises(");
    try parent.genExpr(self, args[1]); // callable
    try self.emit(", .{");
    if (args.len > 2) {
        for (args[2..], 0..) |arg, i| {
            if (i > 0) try self.emit(", ");
            try parent.genExpr(self, arg);
        }
    }
    try self.emit("})");
}
