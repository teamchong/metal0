/// Python math module - Mathematical functions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

// Constants
pub fn genPi(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(f64, 3.141592653589793)");
}

pub fn genE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(f64, 2.718281828459045)");
}

pub fn genTau(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(f64, 6.283185307179586)");
}

pub fn genInf(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("std.math.inf(f64)");
}

pub fn genNan(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("std.math.nan(f64)");
}

// Number-theoretic functions
pub fn genCeil(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        // Check argument type - if float, no conversion needed
        const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;
        if (arg_type == .float) {
            try self.emit("@as(i64, @intFromFloat(@ceil(");
            try self.genExpr(args[0]);
            try self.emit(")))");
        } else if (arg_type == .int) {
            // Integer input - return as-is since ceil of int is the int itself
            try self.genExpr(args[0]);
        } else {
            // Unknown - assume float
            try self.emit("@as(i64, @intFromFloat(@ceil(@as(f64, ");
            try self.genExpr(args[0]);
            try self.emit("))))");
        }
    } else {
        try self.emit("@as(i64, 0)");
    }
}

pub fn genFloor(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        // Check argument type - if float, no conversion needed
        const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;
        if (arg_type == .float) {
            try self.emit("@as(i64, @intFromFloat(@floor(");
            try self.genExpr(args[0]);
            try self.emit(")))");
        } else if (arg_type == .int) {
            // Integer input - return as-is since floor of int is the int itself
            try self.genExpr(args[0]);
        } else {
            // Unknown - assume float
            try self.emit("@as(i64, @intFromFloat(@floor(@as(f64, ");
            try self.genExpr(args[0]);
            try self.emit("))))");
        }
    } else {
        try self.emit("@as(i64, 0)");
    }
}

pub fn genTrunc(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        // Check argument type - if float, no conversion needed
        const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;
        if (arg_type == .float) {
            try self.emit("@as(i64, @intFromFloat(@trunc(");
            try self.genExpr(args[0]);
            try self.emit(")))");
        } else if (arg_type == .int) {
            // Integer input - return as-is since trunc of int is the int itself
            try self.genExpr(args[0]);
        } else {
            // Unknown - assume float
            try self.emit("@as(i64, @intFromFloat(@trunc(@as(f64, ");
            try self.genExpr(args[0]);
            try self.emit("))))");
        }
    } else {
        try self.emit("@as(i64, 0)");
    }
}

pub fn genFabs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@abs(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(f64, 0.0)");
    }
}

pub fn genFactorial(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { var n = @as(i64, ");
        try self.genExpr(args[0]);
        try self.emit("); var result: i64 = 1; while (n > 1) : (n -= 1) { result *= n; } break :blk result; }");
    } else {
        try self.emit("@as(i64, 1)");
    }
}

pub fn genGcd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("blk: { var a = @abs(@as(i64, ");
        try self.genExpr(args[0]);
        try self.emit(")); var b = @abs(@as(i64, ");
        try self.genExpr(args[1]);
        try self.emit(")); while (b != 0) { const t = b; b = @mod(a, b); a = t; } break :blk a; }");
    } else {
        try self.emit("@as(i64, 0)");
    }
}

pub fn genLcm(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("blk: { const a = @abs(@as(i64, ");
        try self.genExpr(args[0]);
        try self.emit(")); const b = @abs(@as(i64, ");
        try self.genExpr(args[1]);
        try self.emit(")); if (a == 0 or b == 0) break :blk @as(i64, 0); var aa = a; var bb = b; while (bb != 0) { const t = bb; bb = @mod(aa, bb); aa = t; } break :blk @divExact(a, aa) * b; }");
    } else {
        try self.emit("@as(i64, 0)");
    }
}

pub fn genComb(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("blk: { const n = @as(u64, @intCast(");
        try self.genExpr(args[0]);
        try self.emit(")); const k = @as(u64, @intCast(");
        try self.genExpr(args[1]);
        try self.emit(")); if (k > n) break :blk @as(i64, 0); var result: u64 = 1; var i: u64 = 0; while (i < k) : (i += 1) { result = result * (n - i) / (i + 1); } break :blk @as(i64, @intCast(result)); }");
    } else {
        try self.emit("@as(i64, 0)");
    }
}

pub fn genPerm(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 1) {
        try self.emit("blk: { const n = @as(u64, @intCast(");
        try self.genExpr(args[0]);
        try self.emit(")); const k = ");
        if (args.len >= 2) {
            try self.emit("@as(u64, @intCast(");
            try self.genExpr(args[1]);
            try self.emit("))");
        } else {
            try self.emit("n");
        }
        try self.emit("; if (k > n) break :blk @as(i64, 0); var result: u64 = 1; var i: u64 = 0; while (i < k) : (i += 1) { result *= (n - i); } break :blk @as(i64, @intCast(result)); }");
    } else {
        try self.emit("@as(i64, 0)");
    }
}

// Power and logarithmic functions
pub fn genSqrt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@sqrt(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(f64, 0.0)");
    }
}

pub fn genIsqrt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(i64, @intFromFloat(@sqrt(@as(f64, @floatFromInt(");
        try self.genExpr(args[0]);
        try self.emit(")))))");
    } else {
        try self.emit("@as(i64, 0)");
    }
}

pub fn genExp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@exp(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(f64, 1.0)");
    }
}

pub fn genExp2(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@exp2(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(f64, 1.0)");
    }
}

pub fn genExpm1(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("std.math.expm1(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(f64, 0.0)");
    }
}

pub fn genLog(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@log(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(f64, 0.0)");
    }
}

pub fn genLog2(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@log2(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(f64, 0.0)");
    }
}

pub fn genLog10(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@log10(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(f64, 0.0)");
    }
}

pub fn genLog1p(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("std.math.log1p(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(f64, 0.0)");
    }
}

pub fn genPow(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("std.math.pow(f64, @as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("), @as(f64, ");
        try self.genExpr(args[1]);
        try self.emit("))");
    } else {
        try self.emit("@as(f64, 1.0)");
    }
}

// Trigonometric functions
pub fn genSin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@sin(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(f64, 0.0)");
    }
}

pub fn genCos(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@cos(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(f64, 1.0)");
    }
}

pub fn genTan(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@tan(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(f64, 0.0)");
    }
}

pub fn genAsin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("std.math.asin(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(f64, 0.0)");
    }
}

pub fn genAcos(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("std.math.acos(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(f64, 0.0)");
    }
}

pub fn genAtan(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("std.math.atan(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(f64, 0.0)");
    }
}

pub fn genAtan2(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("std.math.atan2(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("), @as(f64, ");
        try self.genExpr(args[1]);
        try self.emit("))");
    } else {
        try self.emit("@as(f64, 0.0)");
    }
}

// Hyperbolic functions
pub fn genSinh(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("std.math.sinh(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(f64, 0.0)");
    }
}

pub fn genCosh(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("std.math.cosh(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(f64, 1.0)");
    }
}

pub fn genTanh(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("std.math.tanh(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(f64, 0.0)");
    }
}

pub fn genAsinh(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("std.math.asinh(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(f64, 0.0)");
    }
}

pub fn genAcosh(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("std.math.acosh(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(f64, 0.0)");
    }
}

pub fn genAtanh(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("std.math.atanh(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(f64, 0.0)");
    }
}

// Special functions
pub fn genErf(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("std.math.erf(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(f64, 0.0)");
    }
}

pub fn genErfc(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("(1.0 - std.math.erf(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit(")))");
    } else {
        try self.emit("@as(f64, 1.0)");
    }
}

pub fn genGamma(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("std.math.gamma(f64, @as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("std.math.inf(f64)");
    }
}

pub fn genLgamma(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("std.math.lgamma(f64, @as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("std.math.inf(f64)");
    }
}

// Angular conversion
pub fn genDegrees(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("(");
        try self.genExpr(args[0]);
        try self.emit(" * 180.0 / 3.141592653589793)");
    } else {
        try self.emit("@as(f64, 0.0)");
    }
}

pub fn genRadians(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("(");
        try self.genExpr(args[0]);
        try self.emit(" * 3.141592653589793 / 180.0)");
    } else {
        try self.emit("@as(f64, 0.0)");
    }
}

// Floating point manipulation
pub fn genCopysign(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("std.math.copysign(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("), @as(f64, ");
        try self.genExpr(args[1]);
        try self.emit("))");
    } else {
        try self.emit("@as(f64, 0.0)");
    }
}

pub fn genFmod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("@mod(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("), @as(f64, ");
        try self.genExpr(args[1]);
        try self.emit("))");
    } else {
        try self.emit("@as(f64, 0.0)");
    }
}

pub fn genFrexp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const val = @as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("); const result = std.math.frexp(val); break :blk .{ result.significand, result.exponent }; }");
    } else {
        try self.emit(".{ @as(f64, 0.0), @as(i32, 0) }");
    }
}

pub fn genLdexp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("std.math.ldexp(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("), @as(i32, @intCast(");
        try self.genExpr(args[1]);
        try self.emit(")))");
    } else {
        try self.emit("@as(f64, 0.0)");
    }
}

pub fn genModf(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const val = @as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("); const frac = val - @trunc(val); break :blk .{ frac, @trunc(val) }; }");
    } else {
        try self.emit(".{ @as(f64, 0.0), @as(f64, 0.0) }");
    }
}

pub fn genRemainder(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("@rem(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("), @as(f64, ");
        try self.genExpr(args[1]);
        try self.emit("))");
    } else {
        try self.emit("@as(f64, 0.0)");
    }
}

// Classification functions
pub fn genIsfinite(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("std.math.isFinite(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("true");
    }
}

pub fn genIsinf(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("std.math.isInf(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("false");
    }
}

pub fn genIsnan(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("std.math.isNan(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("false");
    }
}

pub fn genIsclose(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("std.math.approxEqAbs(f64, @as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("), @as(f64, ");
        try self.genExpr(args[1]);
        try self.emit("), 1e-9)");
    } else {
        try self.emit("false");
    }
}

// Sums and products
pub fn genHypot(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("std.math.hypot(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("), @as(f64, ");
        try self.genExpr(args[1]);
        try self.emit("))");
    } else {
        try self.emit("@as(f64, 0.0)");
    }
}

pub fn genDist(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Euclidean distance - simplified for 2D
    if (args.len >= 2) {
        try self.emit("blk: { const p = ");
        try self.genExpr(args[0]);
        try self.emit("; const q = ");
        try self.genExpr(args[1]);
        try self.emit("; var sum: f64 = 0; for (p, q) |pi, qi| { const d = pi - qi; sum += d * d; } break :blk @sqrt(sum); }");
    } else {
        try self.emit("@as(f64, 0.0)");
    }
}

pub fn genFsum(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { var sum: f64 = 0; for (");
        try self.genExpr(args[0]);
        try self.emit(") |item| { sum += item; } break :blk sum; }");
    } else {
        try self.emit("@as(f64, 0.0)");
    }
}

pub fn genProd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { var product: f64 = 1; for (");
        try self.genExpr(args[0]);
        try self.emit(") |item| { product *= item; } break :blk product; }");
    } else {
        try self.emit("@as(f64, 1.0)");
    }
}

pub fn genNextafter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("blk: { const x = @as(f64, ");
        try self.genExpr(args[0]);
        try self.emit("); const y = @as(f64, ");
        try self.genExpr(args[1]);
        try self.emit("); if (x < y) break :blk x + std.math.floatMin(f64) else if (x > y) break :blk x - std.math.floatMin(f64) else break :blk y; }");
    } else {
        try self.emit("@as(f64, 0.0)");
    }
}

pub fn genUlp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const x = @abs(@as(f64, ");
        try self.genExpr(args[0]);
        try self.emit(")); const exp = @as(i32, @intFromFloat(@log2(x))); break :blk std.math.ldexp(@as(f64, 1.0), exp - 52); }");
    } else {
        try self.emit("std.math.floatMin(f64)");
    }
}
