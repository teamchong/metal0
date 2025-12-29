/// unittest test discovery code generation (subTest)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const parent = @import("../expressions.zig");

/// Generate code for self.subTest(msg="label") or self.subTest(i=value)
/// Python: with self.subTest(msg="test case 1"): ... or with self.subTest(i=0): ...
/// Zig: runtime.unittest.subTest("label") or runtime.unittest.subTestInt("i", 0)
/// Note: This is a simplified version - we don't support full context manager semantics
pub fn genSubTest(self: *NativeCodegen, obj: ast.Node, args: []ast.Node, keywords: []ast.Node.KeywordArg) CodegenError!void {
    _ = obj;
    _ = args; // positional args not commonly used

    // Check for keyword arguments (common patterns: msg="label" or i=0)
    if (keywords.len > 0) {
        const kw = keywords[0];
        // Check if value is an integer constant
        if (kw.value == .constant and kw.value.constant.value == .int) {
            // Pattern: subTest(i=0) -> subTestInt("i", 0)
            const Ctx = struct { name: []const u8, val: ast.Node };
            try self.emitCallCtx("runtime.unittest.subTestInt", Ctx{ .name = kw.name, .val = kw.value }, struct {
                pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
                    try s.emit("\"");
                    try s.emit(ctx.name);
                    try s.emit("\", ");
                    try parent.genExpr(s, ctx.val);
                }
            }.f);
            return;
        } else {
            // Pattern: subTest(msg="label") -> subTest("label")
            try self.emitCallCtx("runtime.unittest.subTest", kw.value, struct {
                pub fn f(s: *NativeCodegen, e: ast.Node) CodegenError!void {
                    try parent.genExpr(s, e);
                }
            }.f);
            return;
        }
    }

    // Default: empty label
    try self.emit("runtime.unittest.subTest(\"\")");
}
