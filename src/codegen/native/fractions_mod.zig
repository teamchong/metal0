/// Python fractions module - Rational number arithmetic
/// MIGRATED TO ZIGBUILDER
/// Uses runtime.Fraction to avoid monomorphization explosion from inline struct emission
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Fraction", genFraction },
    .{ "gcd", h.wrap2Blk("gcd", "var _a: i64 = @intCast(__v0); var _b: i64 = @intCast(__v1); if (_a < 0) _a = -_a; if (_b < 0) _b = -_b; while (_b != 0) { const t = _b; _b = @mod(_a, _b); _a = t; }", "_a", "@as(i64, 1)") },
});

fn genFraction(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Use runtime.Fraction instead of inline struct - compiles ONCE, not per call
    if (args.len == 0) {
        // Type reference only (R = fractions.Fraction) - just emit the type
        // The caller (assign.zig) should handle emitting "const R = " prefix
        try self.emit("runtime.Fraction");
        return;
    } else if (args.len == 1) {
        try self.emitCallCtx("runtime.Fraction.init", args[0], struct {
            pub fn f(s: *NativeCodegen, e: ast.Node) CodegenError!void {
                try s.genExpr(e);
                try s.emit(", 1");
            }
        }.f);
    } else if (args.len >= 2) {
        const Ctx = struct { a0: ast.Node, a1: ast.Node };
        try self.emitCallCtx("runtime.Fraction.init", Ctx{ .a0 = args[0], .a1 = args[1] }, struct {
            pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
                try s.genExpr(ctx.a0);
                try s.emit(", ");
                try s.genExpr(ctx.a1);
            }
        }.f);
    }
}
