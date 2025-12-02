/// Python cmath module - Mathematical functions for complex numbers
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}
fn genComplexBuiltin(comptime builtin: []const u8, comptime default_re: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) { try self.emit(".{ .re = " ++ default_re ++ ", .im = 0.0 }"); return; }
        try self.emit(".{ .re = " ++ builtin ++ "(@as(f64, @floatFromInt("); try self.genExpr(args[0]); try self.emit("))), .im = 0.0 }");
    } }.f;
}
fn genComplexStdMath(comptime func: []const u8, comptime default_re: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) { try self.emit(".{ .re = " ++ default_re ++ ", .im = 0.0 }"); return; }
        try self.emit(".{ .re = std.math." ++ func ++ "(@as(f64, @floatFromInt("); try self.genExpr(args[0]); try self.emit("))), .im = 0.0 }");
    } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "sqrt", genSqrt },
    .{ "exp", genComplexBuiltin("@exp", "1.0") }, .{ "log", genComplexBuiltin("@log", "0.0") }, .{ "log10", genComplexBuiltin("@log10", "0.0") },
    .{ "sin", genComplexBuiltin("@sin", "0.0") }, .{ "cos", genComplexBuiltin("@cos", "1.0") }, .{ "tan", genComplexBuiltin("@tan", "0.0") },
    .{ "asin", genComplexStdMath("asin", "0.0") }, .{ "acos", genComplexStdMath("acos", "0.0") }, .{ "atan", genComplexStdMath("atan", "0.0") },
    .{ "sinh", genComplexStdMath("sinh", "0.0") }, .{ "cosh", genComplexStdMath("cosh", "1.0") }, .{ "tanh", genComplexStdMath("tanh", "0.0") },
    .{ "asinh", genComplexStdMath("asinh", "0.0") }, .{ "acosh", genComplexStdMath("acosh", "0.0") }, .{ "atanh", genComplexStdMath("atanh", "0.0") },
    .{ "phase", genConst("@as(f64, 0.0)") }, .{ "polar", genConst(".{ @as(f64, 0.0), @as(f64, 0.0) }") }, .{ "rect", genConst(".{ .re = 0.0, .im = 0.0 }") },
    .{ "isfinite", genConst("true") }, .{ "isinf", genConst("false") }, .{ "isnan", genConst("false") }, .{ "isclose", genConst("true") },
    .{ "pi", genConst("@as(f64, 3.141592653589793)") }, .{ "e", genConst("@as(f64, 2.718281828459045)") }, .{ "tau", genConst("@as(f64, 6.283185307179586)") },
    .{ "inf", genConst("std.math.inf(f64)") }, .{ "infj", genConst(".{ .re = 0.0, .im = std.math.inf(f64) }") },
    .{ "nan", genConst("std.math.nan(f64)") }, .{ "nanj", genConst(".{ .re = 0.0, .im = std.math.nan(f64) }") },
});

fn genSqrt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit(".{ .re = 0.0, .im = 0.0 }"); return; }
    try self.emit("cmath_sqrt_blk: { const x = @as(f64, @floatFromInt("); try self.genExpr(args[0]);
    try self.emit(")); if (x >= 0) break :cmath_sqrt_blk .{ .re = @sqrt(x), .im = 0.0 }; break :cmath_sqrt_blk .{ .re = 0.0, .im = @sqrt(-x) }; }");
}
