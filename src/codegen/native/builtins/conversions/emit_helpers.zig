/// Shared emit helpers for conversion builtins
/// DRY: Consolidates duplicate helpers from int_conv.zig, str_conv.zig
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../../main.zig").CodegenError;
const NativeCodegen = @import("../../main.zig").NativeCodegen;

/// Helper: emit (expr.method()) with guaranteed bracket matching
pub fn emitMethodCallWrapped(self: *NativeCodegen, expr: ast.Node, method: []const u8) CodegenError!void {
    const Ctx = struct { e: ast.Node, m: []const u8 };
    try self.withParensCtx(Ctx{ .e = expr, .m = method }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.genExpr(ctx.e);
            try s.emit(".");
            try s.emit(ctx.m);
            try s.emit("()");
        }
    }.f);
}

/// Helper: emit (expr.method() catch fallback) with guaranteed bracket matching
pub fn emitMethodCallCatch(self: *NativeCodegen, expr: ast.Node, method: []const u8, fallback: []const u8) CodegenError!void {
    const Ctx = struct { e: ast.Node, m: []const u8, fb: []const u8 };
    try self.withParensCtx(Ctx{ .e = expr, .m = method, .fb = fallback }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.genExpr(ctx.e);
            try s.emit(".");
            try s.emit(ctx.m);
            try s.emit("() catch ");
            try s.emit(ctx.fb);
        }
    }.f);
}

/// Helper: emit (try expr.method()) with guaranteed bracket matching
pub fn emitTryMethodCall(self: *NativeCodegen, expr: ast.Node, method: []const u8) CodegenError!void {
    const Ctx = struct { e: ast.Node, m: []const u8 };
    try self.withParensCtx(Ctx{ .e = expr, .m = method }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.emit("try ");
            try s.genExpr(ctx.e);
            try s.emit(".");
            try s.emit(ctx.m);
            try s.emit("()");
        }
    }.f);
}
