/// Python cmath module - Mathematical functions for complex numbers
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

fn genComplexBuiltin(comptime builtin: []const u8, comptime default_re: []const u8) h.H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) { try self.emit(".{ .re = " ++ default_re ++ ", .im = 0.0 }"); return; }
        try self.emit(".{ .re = " ++ builtin ++ "(@as(f64, @floatFromInt("); try self.genExpr(args[0]); try self.emit("))), .im = 0.0 }");
    } }.f;
}
fn genComplexStdMath(comptime func: []const u8, comptime default_re: []const u8) h.H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) { try self.emit(".{ .re = " ++ default_re ++ ", .im = 0.0 }"); return; }
        try self.emit(".{ .re = std.math." ++ func ++ "(@as(f64, @floatFromInt("); try self.genExpr(args[0]); try self.emit("))), .im = 0.0 }");
    } }.f;
}

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "sqrt", genSqrt },
    .{ "exp", genComplexBuiltin("@exp", "1.0") }, .{ "log", genComplexBuiltin("@log", "0.0") }, .{ "log10", genComplexBuiltin("@log10", "0.0") },
    .{ "sin", genComplexBuiltin("@sin", "0.0") }, .{ "cos", genComplexBuiltin("@cos", "1.0") }, .{ "tan", genComplexBuiltin("@tan", "0.0") },
    .{ "asin", genComplexStdMath("asin", "0.0") }, .{ "acos", genComplexStdMath("acos", "0.0") }, .{ "atan", genComplexStdMath("atan", "0.0") },
    .{ "sinh", genComplexStdMath("sinh", "0.0") }, .{ "cosh", genComplexStdMath("cosh", "1.0") }, .{ "tanh", genComplexStdMath("tanh", "0.0") },
    .{ "asinh", genComplexStdMath("asinh", "0.0") }, .{ "acosh", genComplexStdMath("acosh", "0.0") }, .{ "atanh", genComplexStdMath("atanh", "0.0") },
    .{ "phase", h.F64(0.0) }, .{ "polar", h.c(".{ @as(f64, 0.0), @as(f64, 0.0) }") }, .{ "rect", h.c(".{ .re = 0.0, .im = 0.0 }") },
    .{ "isfinite", h.c("true") }, .{ "isinf", h.c("false") }, .{ "isnan", h.c("false") }, .{ "isclose", h.c("true") },
    .{ "pi", h.F64(3.141592653589793) }, .{ "e", h.F64(2.718281828459045) }, .{ "tau", h.F64(6.283185307179586) },
    .{ "inf", h.c("std.math.inf(f64)") }, .{ "infj", h.c(".{ .re = 0.0, .im = std.math.inf(f64) }") },
    .{ "nan", h.c("std.math.nan(f64)") }, .{ "nanj", h.c(".{ .re = 0.0, .im = std.math.nan(f64) }") },
});

fn genSqrt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit(".{ .re = 0.0, .im = 0.0 }"); return; }
    try self.emit("cmath_sqrt_blk: { const x = @as(f64, @floatFromInt("); try self.genExpr(args[0]);
    try self.emit(")); if (x >= 0) break :cmath_sqrt_blk .{ .re = @sqrt(x), .im = 0.0 }; break :cmath_sqrt_blk .{ .re = 0.0, .im = @sqrt(-x) }; }");
}
