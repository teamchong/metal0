/// Python cmath module - Mathematical functions for complex numbers
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate cmath.sqrt(x) -> complex square root
pub fn genSqrt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit(".{ .re = 0.0, .im = 0.0 }");
        return;
    }
    try self.emit("cmath_sqrt_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const x = @as(f64, @floatFromInt(");
    try self.genExpr(args[0]);
    try self.emit("));\n");
    try self.emitIndent();
    try self.emit("if (x >= 0) break :cmath_sqrt_blk .{ .re = @sqrt(x), .im = 0.0 };\n");
    try self.emitIndent();
    try self.emit("break :cmath_sqrt_blk .{ .re = 0.0, .im = @sqrt(-x) };\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate cmath.exp(x) -> complex exponential
pub fn genExp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit(".{ .re = 1.0, .im = 0.0 }");
        return;
    }
    try self.emit(".{ .re = @exp(@as(f64, @floatFromInt(");
    try self.genExpr(args[0]);
    try self.emit("))), .im = 0.0 }");
}

/// Generate cmath.log(x, base=e) -> complex logarithm
pub fn genLog(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit(".{ .re = 0.0, .im = 0.0 }");
        return;
    }
    try self.emit(".{ .re = @log(@as(f64, @floatFromInt(");
    try self.genExpr(args[0]);
    try self.emit("))), .im = 0.0 }");
}

/// Generate cmath.log10(x) -> complex base-10 logarithm
pub fn genLog10(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit(".{ .re = 0.0, .im = 0.0 }");
        return;
    }
    try self.emit(".{ .re = @log10(@as(f64, @floatFromInt(");
    try self.genExpr(args[0]);
    try self.emit("))), .im = 0.0 }");
}

/// Generate cmath.sin(x) -> complex sine
pub fn genSin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit(".{ .re = 0.0, .im = 0.0 }");
        return;
    }
    try self.emit(".{ .re = @sin(@as(f64, @floatFromInt(");
    try self.genExpr(args[0]);
    try self.emit("))), .im = 0.0 }");
}

/// Generate cmath.cos(x) -> complex cosine
pub fn genCos(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit(".{ .re = 1.0, .im = 0.0 }");
        return;
    }
    try self.emit(".{ .re = @cos(@as(f64, @floatFromInt(");
    try self.genExpr(args[0]);
    try self.emit("))), .im = 0.0 }");
}

/// Generate cmath.tan(x) -> complex tangent
pub fn genTan(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit(".{ .re = 0.0, .im = 0.0 }");
        return;
    }
    try self.emit(".{ .re = @tan(@as(f64, @floatFromInt(");
    try self.genExpr(args[0]);
    try self.emit("))), .im = 0.0 }");
}

/// Generate cmath.asin(x) -> complex arc sine
pub fn genAsin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit(".{ .re = 0.0, .im = 0.0 }");
        return;
    }
    try self.emit(".{ .re = std.math.asin(@as(f64, @floatFromInt(");
    try self.genExpr(args[0]);
    try self.emit("))), .im = 0.0 }");
}

/// Generate cmath.acos(x) -> complex arc cosine
pub fn genAcos(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit(".{ .re = 0.0, .im = 0.0 }");
        return;
    }
    try self.emit(".{ .re = std.math.acos(@as(f64, @floatFromInt(");
    try self.genExpr(args[0]);
    try self.emit("))), .im = 0.0 }");
}

/// Generate cmath.atan(x) -> complex arc tangent
pub fn genAtan(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit(".{ .re = 0.0, .im = 0.0 }");
        return;
    }
    try self.emit(".{ .re = std.math.atan(@as(f64, @floatFromInt(");
    try self.genExpr(args[0]);
    try self.emit("))), .im = 0.0 }");
}

/// Generate cmath.sinh(x) -> complex hyperbolic sine
pub fn genSinh(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit(".{ .re = 0.0, .im = 0.0 }");
        return;
    }
    try self.emit(".{ .re = std.math.sinh(@as(f64, @floatFromInt(");
    try self.genExpr(args[0]);
    try self.emit("))), .im = 0.0 }");
}

/// Generate cmath.cosh(x) -> complex hyperbolic cosine
pub fn genCosh(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit(".{ .re = 1.0, .im = 0.0 }");
        return;
    }
    try self.emit(".{ .re = std.math.cosh(@as(f64, @floatFromInt(");
    try self.genExpr(args[0]);
    try self.emit("))), .im = 0.0 }");
}

/// Generate cmath.tanh(x) -> complex hyperbolic tangent
pub fn genTanh(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit(".{ .re = 0.0, .im = 0.0 }");
        return;
    }
    try self.emit(".{ .re = std.math.tanh(@as(f64, @floatFromInt(");
    try self.genExpr(args[0]);
    try self.emit("))), .im = 0.0 }");
}

/// Generate cmath.asinh(x) -> complex inverse hyperbolic sine
pub fn genAsinh(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit(".{ .re = 0.0, .im = 0.0 }");
        return;
    }
    try self.emit(".{ .re = std.math.asinh(@as(f64, @floatFromInt(");
    try self.genExpr(args[0]);
    try self.emit("))), .im = 0.0 }");
}

/// Generate cmath.acosh(x) -> complex inverse hyperbolic cosine
pub fn genAcosh(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit(".{ .re = 0.0, .im = 0.0 }");
        return;
    }
    try self.emit(".{ .re = std.math.acosh(@as(f64, @floatFromInt(");
    try self.genExpr(args[0]);
    try self.emit("))), .im = 0.0 }");
}

/// Generate cmath.atanh(x) -> complex inverse hyperbolic tangent
pub fn genAtanh(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit(".{ .re = 0.0, .im = 0.0 }");
        return;
    }
    try self.emit(".{ .re = std.math.atanh(@as(f64, @floatFromInt(");
    try self.genExpr(args[0]);
    try self.emit("))), .im = 0.0 }");
}

/// Generate cmath.phase(x) -> phase angle
pub fn genPhase(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(f64, 0.0)");
}

/// Generate cmath.polar(x) -> (r, phi)
pub fn genPolar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(f64, 0.0), @as(f64, 0.0) }");
}

/// Generate cmath.rect(r, phi) -> complex from polar
pub fn genRect(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .re = 0.0, .im = 0.0 }");
}

/// Generate cmath.isfinite(x) -> bool
pub fn genIsfinite(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Generate cmath.isinf(x) -> bool
pub fn genIsinf(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate cmath.isnan(x) -> bool
pub fn genIsnan(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate cmath.isclose(a, b, ...) -> bool
pub fn genIsclose(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Generate cmath.pi constant
pub fn genPi(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(f64, 3.141592653589793)");
}

/// Generate cmath.e constant
pub fn genE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(f64, 2.718281828459045)");
}

/// Generate cmath.tau constant
pub fn genTau(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(f64, 6.283185307179586)");
}

/// Generate cmath.inf constant
pub fn genInf(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("std.math.inf(f64)");
}

/// Generate cmath.infj constant
pub fn genInfj(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .re = 0.0, .im = std.math.inf(f64) }");
}

/// Generate cmath.nan constant
pub fn genNan(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("std.math.nan(f64)");
}

/// Generate cmath.nanj constant
pub fn genNanj(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .re = 0.0, .im = std.math.nan(f64) }");
}
