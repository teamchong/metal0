/// unittest module code generation
const std = @import("std");
const ast = @import("../../ast.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate code for unittest.main()
/// Initializes test runner and runs all test methods
pub fn genUnittestMain(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args; // unused for now

    // Initialize unittest runner
    try self.output.appendSlice(self.allocator, "runtime.unittest.main(allocator) catch |err| { std.debug.print(\"Test init failed: {}\\n\", .{err}); return err; }");
}

/// Generate code for unittest.finalize() - called at end of tests
pub fn genUnittestFinalize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.output.appendSlice(self.allocator, "runtime.unittest.finalize()");
}

/// Generate code for self.assertEqual(a, b)
pub fn genAssertEqual(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj; // We ignore `self` - it's just a marker

    if (args.len < 2) {
        try self.output.appendSlice(self.allocator, "@compileError(\"assertEqual requires 2 arguments\")");
        return;
    }

    const parent = @import("expressions.zig");
    try self.output.appendSlice(self.allocator, "runtime.unittest.assertEqual(");
    try parent.genExpr(self, args[0]);
    try self.output.appendSlice(self.allocator, ", ");
    try parent.genExpr(self, args[1]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for self.assertTrue(x)
pub fn genAssertTrue(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;

    if (args.len < 1) {
        try self.output.appendSlice(self.allocator, "@compileError(\"assertTrue requires 1 argument\")");
        return;
    }

    const parent = @import("expressions.zig");
    try self.output.appendSlice(self.allocator, "runtime.unittest.assertTrue(");
    try parent.genExpr(self, args[0]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for self.assertFalse(x)
pub fn genAssertFalse(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;

    if (args.len < 1) {
        try self.output.appendSlice(self.allocator, "@compileError(\"assertFalse requires 1 argument\")");
        return;
    }

    const parent = @import("expressions.zig");
    try self.output.appendSlice(self.allocator, "runtime.unittest.assertFalse(");
    try parent.genExpr(self, args[0]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for self.assertIsNone(x)
pub fn genAssertIsNone(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj;

    if (args.len < 1) {
        try self.output.appendSlice(self.allocator, "@compileError(\"assertIsNone requires 1 argument\")");
        return;
    }

    const parent = @import("expressions.zig");
    try self.output.appendSlice(self.allocator, "runtime.unittest.assertIsNone(");
    try parent.genExpr(self, args[0]);
    try self.output.appendSlice(self.allocator, ")");
}
