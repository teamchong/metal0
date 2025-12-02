/// Python cmath module - Mathematical functions for complex numbers
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "sqrt", h.wrap("cmath_sqrt_blk: { const x = @as(f64, @floatFromInt(", ")); if (x >= 0) break :cmath_sqrt_blk .{ .re = @sqrt(x), .im = 0.0 }; break :cmath_sqrt_blk .{ .re = 0.0, .im = @sqrt(-x) }; }", ".{ .re = 0.0, .im = 0.0 }") },
    .{ "exp", h.complexBuiltin("@exp", "1.0") }, .{ "log", h.complexBuiltin("@log", "0.0") }, .{ "log10", h.complexBuiltin("@log10", "0.0") },
    .{ "sin", h.complexBuiltin("@sin", "0.0") }, .{ "cos", h.complexBuiltin("@cos", "1.0") }, .{ "tan", h.complexBuiltin("@tan", "0.0") },
    .{ "asin", h.complexStdMath("asin", "0.0") }, .{ "acos", h.complexStdMath("acos", "0.0") }, .{ "atan", h.complexStdMath("atan", "0.0") },
    .{ "sinh", h.complexStdMath("sinh", "0.0") }, .{ "cosh", h.complexStdMath("cosh", "1.0") }, .{ "tanh", h.complexStdMath("tanh", "0.0") },
    .{ "asinh", h.complexStdMath("asinh", "0.0") }, .{ "acosh", h.complexStdMath("acosh", "0.0") }, .{ "atanh", h.complexStdMath("atanh", "0.0") },
    .{ "phase", h.F64(0.0) }, .{ "polar", h.c(".{ @as(f64, 0.0), @as(f64, 0.0) }") }, .{ "rect", h.c(".{ .re = 0.0, .im = 0.0 }") },
    .{ "isfinite", h.c("true") }, .{ "isinf", h.c("false") }, .{ "isnan", h.c("false") }, .{ "isclose", h.c("true") },
    .{ "pi", h.F64(3.141592653589793) }, .{ "e", h.F64(2.718281828459045) }, .{ "tau", h.F64(6.283185307179586) },
    .{ "inf", h.c("std.math.inf(f64)") }, .{ "infj", h.c(".{ .re = 0.0, .im = std.math.inf(f64) }") },
    .{ "nan", h.c("std.math.nan(f64)") }, .{ "nanj", h.c(".{ .re = 0.0, .im = std.math.nan(f64) }") },
});
