/// Python cmath module - Mathematical functions for complex numbers
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "sqrt", genSqrt }, .{ "exp", genExp }, .{ "log", genLog }, .{ "log10", genLog10 },
    .{ "sin", genSin }, .{ "cos", genCos }, .{ "tan", genTan },
    .{ "asin", genAsin }, .{ "acos", genAcos }, .{ "atan", genAtan },
    .{ "sinh", genSinh }, .{ "cosh", genCosh }, .{ "tanh", genTanh },
    .{ "asinh", genAsinh }, .{ "acosh", genAcosh }, .{ "atanh", genAtanh },
    .{ "phase", genPhase }, .{ "polar", genPolar }, .{ "rect", genRect },
    .{ "isfinite", genTrue }, .{ "isinf", genFalse }, .{ "isnan", genFalse }, .{ "isclose", genTrue },
    .{ "pi", genPi }, .{ "e", genE }, .{ "tau", genTau },
    .{ "inf", genInf }, .{ "infj", genInfj }, .{ "nan", genNan }, .{ "nanj", genNanj },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }
fn genTrue(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "true"); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }
fn genPhase(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(f64, 0.0)"); }
fn genPolar(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ @as(f64, 0.0), @as(f64, 0.0) }"); }
fn genRect(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .re = 0.0, .im = 0.0 }"); }
fn genPi(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(f64, 3.141592653589793)"); }
fn genE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(f64, 2.718281828459045)"); }
fn genTau(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(f64, 6.283185307179586)"); }
fn genInf(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "std.math.inf(f64)"); }
fn genInfj(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .re = 0.0, .im = std.math.inf(f64) }"); }
fn genNan(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "std.math.nan(f64)"); }
fn genNanj(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .re = 0.0, .im = std.math.nan(f64) }"); }

// Complex helpers
fn genComplexBuiltin(self: *NativeCodegen, args: []ast.Node, builtin: []const u8, default_re: []const u8) CodegenError!void {
    if (args.len == 0) { try self.emit(".{ .re = "); try self.emit(default_re); try self.emit(", .im = 0.0 }"); return; }
    try self.emit(".{ .re = "); try self.emit(builtin); try self.emit("(@as(f64, @floatFromInt(");
    try self.genExpr(args[0]); try self.emit("))), .im = 0.0 }");
}

fn genComplexStdMath(self: *NativeCodegen, args: []ast.Node, func: []const u8, default_re: []const u8) CodegenError!void {
    if (args.len == 0) { try self.emit(".{ .re = "); try self.emit(default_re); try self.emit(", .im = 0.0 }"); return; }
    try self.emit(".{ .re = std.math."); try self.emit(func); try self.emit("(@as(f64, @floatFromInt(");
    try self.genExpr(args[0]); try self.emit("))), .im = 0.0 }");
}

// Trig functions
fn genSqrt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit(".{ .re = 0.0, .im = 0.0 }"); return; }
    try self.emit("cmath_sqrt_blk: { const x = @as(f64, @floatFromInt("); try self.genExpr(args[0]);
    try self.emit(")); if (x >= 0) break :cmath_sqrt_blk .{ .re = @sqrt(x), .im = 0.0 }; break :cmath_sqrt_blk .{ .re = 0.0, .im = @sqrt(-x) }; }");
}
fn genExp(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genComplexBuiltin(self, args, "@exp", "1.0"); }
fn genLog(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genComplexBuiltin(self, args, "@log", "0.0"); }
fn genLog10(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genComplexBuiltin(self, args, "@log10", "0.0"); }
fn genSin(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genComplexBuiltin(self, args, "@sin", "0.0"); }
fn genCos(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genComplexBuiltin(self, args, "@cos", "1.0"); }
fn genTan(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genComplexBuiltin(self, args, "@tan", "0.0"); }
fn genAsin(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genComplexStdMath(self, args, "asin", "0.0"); }
fn genAcos(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genComplexStdMath(self, args, "acos", "0.0"); }
fn genAtan(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genComplexStdMath(self, args, "atan", "0.0"); }
fn genSinh(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genComplexStdMath(self, args, "sinh", "0.0"); }
fn genCosh(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genComplexStdMath(self, args, "cosh", "1.0"); }
fn genTanh(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genComplexStdMath(self, args, "tanh", "0.0"); }
fn genAsinh(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genComplexStdMath(self, args, "asinh", "0.0"); }
fn genAcosh(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genComplexStdMath(self, args, "acosh", "0.0"); }
fn genAtanh(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genComplexStdMath(self, args, "atanh", "0.0"); }
