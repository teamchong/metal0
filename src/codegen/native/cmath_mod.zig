/// Python cmath module - Mathematical functions for complex numbers
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const NativeCodegen = @import("main.zig").NativeCodegen;
const CodegenError = @import("main.zig").CodegenError;

/// Complex sqrt: sqrt(x) for real numbers, returns complex result if negative
fn genSqrt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.write(".{ .re = 0.0, .im = 0.0 }");
        const output = try b.getBodyDupe();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("cmath_sqrt", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b2 = try c.getBuilder();
            try b2.write("const __x = @as(f64, @floatFromInt(");
            const output1 = try b2.getBodyDupe();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b3 = try c.getBuilder();
                try b3.writeFmt(")); if (__x >= 0) break :{s} .{{ .re = @sqrt(__x), .im = 0.0 }}; break :{s} .{{ .re = 0.0, .im = @sqrt(-__x) }}", .{ label, label });
                const output2 = try b3.getBodyDupe();
                try c.output.appendSlice(c.allocator, output2);
            }
        }
    }.emit);
}

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "sqrt", genSqrt },
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
