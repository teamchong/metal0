/// Python math module - Mathematical functions
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

fn genRounding(comptime b: []const u8) h.H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len > 0) {
            const t = self.type_inferrer.inferExpr(args[0]) catch .unknown;
            if (t == .float) { try self.emit("@as(i64, @intFromFloat(" ++ b ++ "("); try self.genExpr(args[0]); try self.emit(")))"); }
            else if (t == .int) try self.genExpr(args[0])
            else { try self.emit("@as(i64, @intFromFloat(" ++ b ++ "(@as(f64, "); try self.genExpr(args[0]); try self.emit("))))"); }
        } else try self.emit("@as(i64, 0)");
    } }.f;
}

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    // Constants
    .{ "pi", h.F64(3.141592653589793) }, .{ "e", h.F64(2.718281828459045) },
    .{ "tau", h.F64(6.283185307179586) }, .{ "inf", h.c("std.math.inf(f64)") }, .{ "nan", h.c("std.math.nan(f64)") },
    // Rounding
    .{ "ceil", genRounding("@ceil") }, .{ "floor", genRounding("@floor") }, .{ "trunc", genRounding("@trunc") }, .{ "fabs", genFabs },
    // Number-theoretic
    .{ "factorial", genFactorial }, .{ "gcd", genGcd }, .{ "lcm", genLcm }, .{ "comb", genComb }, .{ "perm", genPerm },
    // Power and log
    .{ "sqrt", h.builtin1("@sqrt", "@as(f64, 0.0)") }, .{ "isqrt", genIsqrt },
    .{ "exp", h.builtin1("@exp", "@as(f64, 1.0)") }, .{ "exp2", h.builtin1("@exp2", "@as(f64, 1.0)") }, .{ "expm1", h.stdmath1("expm1", "@as(f64, 0.0)") },
    .{ "log", h.builtin1("@log", "@as(f64, 0.0)") }, .{ "log2", h.builtin1("@log2", "@as(f64, 0.0)") },
    .{ "log10", h.builtin1("@log10", "@as(f64, 0.0)") }, .{ "log1p", h.stdmath1("log1p", "@as(f64, 0.0)") }, .{ "pow", genPow },
    // Trig
    .{ "sin", h.builtin1("@sin", "@as(f64, 0.0)") }, .{ "cos", h.builtin1("@cos", "@as(f64, 1.0)") }, .{ "tan", h.builtin1("@tan", "@as(f64, 0.0)") },
    .{ "asin", h.stdmath1("asin", "@as(f64, 0.0)") }, .{ "acos", h.stdmath1("acos", "@as(f64, 0.0)") },
    .{ "atan", h.stdmath1("atan", "@as(f64, 0.0)") }, .{ "atan2", h.stdmath2("atan2", "@as(f64, 0.0)") },
    // Hyperbolic
    .{ "sinh", h.stdmath1("sinh", "@as(f64, 0.0)") }, .{ "cosh", h.stdmath1("cosh", "@as(f64, 1.0)") }, .{ "tanh", h.stdmath1("tanh", "@as(f64, 0.0)") },
    .{ "asinh", h.stdmath1("asinh", "@as(f64, 0.0)") }, .{ "acosh", h.stdmath1("acosh", "@as(f64, 0.0)") }, .{ "atanh", h.stdmath1("atanh", "@as(f64, 0.0)") },
    // Special
    .{ "erf", h.stdmath1("erf", "@as(f64, 0.0)") }, .{ "erfc", genErfc },
    .{ "gamma", h.stdmathT("gamma", "std.math.inf(f64)") }, .{ "lgamma", h.stdmathT("lgamma", "std.math.inf(f64)") },
    // Angular
    .{ "degrees", genDegrees }, .{ "radians", genRadians },
    // Float manipulation
    .{ "copysign", h.stdmath2("copysign", "@as(f64, 0.0)") }, .{ "fmod", genFmod },
    .{ "frexp", genFrexp }, .{ "ldexp", genLdexp }, .{ "modf", genModf }, .{ "remainder", genRemainder },
    // Classification
    .{ "isfinite", h.stdmath1("isFinite", "true") }, .{ "isinf", h.stdmath1("isInf", "false") },
    .{ "isnan", h.stdmath1("isNan", "false") }, .{ "isclose", genIsclose },
    // Sums
    .{ "hypot", h.stdmath2("hypot", "@as(f64, 0.0)") }, .{ "dist", genDist }, .{ "fsum", genFsum }, .{ "prod", genProd },
    .{ "nextafter", genNextafter }, .{ "ulp", genUlp },
});

fn genFabs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("@abs(@as(f64, "); try self.genExpr(args[0]); try self.emit("))"); } else try self.emit("@as(f64, 0.0)");
}
fn genFactorial(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { var n = @as(i64, "); try self.genExpr(args[0]); try self.emit("); var result: i64 = 1; while (n > 1) : (n -= 1) { result *= n; } break :blk result; }"); } else try self.emit("@as(i64, 1)");
}
fn genGcd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { var a = @abs(@as(i64, "); try self.genExpr(args[0]); try self.emit(")); var b = @abs(@as(i64, "); try self.genExpr(args[1]); try self.emit(")); while (b != 0) { const t = b; b = @mod(a, b); a = t; } break :blk a; }"); } else try self.emit("@as(i64, 0)");
}
fn genLcm(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { const a = @abs(@as(i64, "); try self.genExpr(args[0]); try self.emit(")); const b = @abs(@as(i64, "); try self.genExpr(args[1]); try self.emit(")); if (a == 0 or b == 0) break :blk @as(i64, 0); var aa = a; var bb = b; while (bb != 0) { const t = bb; bb = @mod(aa, bb); aa = t; } break :blk @divExact(a, aa) * b; }"); } else try self.emit("@as(i64, 0)");
}
fn genComb(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { const n = @as(u64, @intCast("); try self.genExpr(args[0]); try self.emit(")); const k = @as(u64, @intCast("); try self.genExpr(args[1]); try self.emit(")); if (k > n) break :blk @as(i64, 0); var result: u64 = 1; var i: u64 = 0; while (i < k) : (i += 1) { result = result * (n - i) / (i + 1); } break :blk @as(i64, @intCast(result)); }"); } else try self.emit("@as(i64, 0)");
}
fn genPerm(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 1) { try self.emit("blk: { const n = @as(u64, @intCast("); try self.genExpr(args[0]); try self.emit(")); const k = "); if (args.len >= 2) { try self.emit("@as(u64, @intCast("); try self.genExpr(args[1]); try self.emit("))"); } else try self.emit("n"); try self.emit("; if (k > n) break :blk @as(i64, 0); var result: u64 = 1; var i: u64 = 0; while (i < k) : (i += 1) { result *= (n - i); } break :blk @as(i64, @intCast(result)); }"); } else try self.emit("@as(i64, 0)");
}
fn genIsqrt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("@as(i64, @intFromFloat(@sqrt(@as(f64, @floatFromInt("); try self.genExpr(args[0]); try self.emit(")))))"); } else try self.emit("@as(i64, 0)");
}
fn genPow(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("std.math.pow(f64, @as(f64, "); try self.genExpr(args[0]); try self.emit("), @as(f64, "); try self.genExpr(args[1]); try self.emit("))"); } else try self.emit("@as(f64, 1.0)");
}
fn genErfc(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("(1.0 - std.math.erf(@as(f64, "); try self.genExpr(args[0]); try self.emit(")))"); } else try self.emit("@as(f64, 1.0)");
}
fn genDegrees(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("("); try self.genExpr(args[0]); try self.emit(" * 180.0 / 3.141592653589793)"); } else try self.emit("@as(f64, 0.0)");
}
fn genRadians(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("("); try self.genExpr(args[0]); try self.emit(" * 3.141592653589793 / 180.0)"); } else try self.emit("@as(f64, 0.0)");
}
fn genFmod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("@mod(@as(f64, "); try self.genExpr(args[0]); try self.emit("), @as(f64, "); try self.genExpr(args[1]); try self.emit("))"); } else try self.emit("@as(f64, 0.0)");
}
fn genFrexp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const val = @as(f64, "); try self.genExpr(args[0]); try self.emit("); const result = std.math.frexp(val); break :blk .{ result.significand, result.exponent }; }"); } else try self.emit(".{ @as(f64, 0.0), @as(i32, 0) }");
}
fn genLdexp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("std.math.ldexp(@as(f64, "); try self.genExpr(args[0]); try self.emit("), @as(i32, @intCast("); try self.genExpr(args[1]); try self.emit(")))"); } else try self.emit("@as(f64, 0.0)");
}
fn genModf(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const val = @as(f64, "); try self.genExpr(args[0]); try self.emit("); const frac = val - @trunc(val); break :blk .{ frac, @trunc(val) }; }"); } else try self.emit(".{ @as(f64, 0.0), @as(f64, 0.0) }");
}
fn genRemainder(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("@rem(@as(f64, "); try self.genExpr(args[0]); try self.emit("), @as(f64, "); try self.genExpr(args[1]); try self.emit("))"); } else try self.emit("@as(f64, 0.0)");
}
fn genIsclose(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("std.math.approxEqAbs(f64, @as(f64, "); try self.genExpr(args[0]); try self.emit("), @as(f64, "); try self.genExpr(args[1]); try self.emit("), 1e-9)"); } else try self.emit("false");
}
fn genDist(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { const p = "); try self.genExpr(args[0]); try self.emit("; const q = "); try self.genExpr(args[1]); try self.emit("; var sum: f64 = 0; for (p, q) |pi, qi| { const d = pi - qi; sum += d * d; } break :blk @sqrt(sum); }"); } else try self.emit("@as(f64, 0.0)");
}
fn genFsum(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { var sum: f64 = 0; for ("); try self.genExpr(args[0]); try self.emit(") |item| { sum += item; } break :blk sum; }"); } else try self.emit("@as(f64, 0.0)");
}
fn genProd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { var product: f64 = 1; for ("); try self.genExpr(args[0]); try self.emit(") |item| { product *= item; } break :blk product; }"); } else try self.emit("@as(f64, 1.0)");
}
fn genNextafter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { const x = @as(f64, "); try self.genExpr(args[0]); try self.emit("); const y = @as(f64, "); try self.genExpr(args[1]); try self.emit("); if (x < y) break :blk x + std.math.floatMin(f64) else if (x > y) break :blk x - std.math.floatMin(f64) else break :blk y; }"); } else try self.emit("@as(f64, 0.0)");
}
fn genUlp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const x = @abs(@as(f64, "); try self.genExpr(args[0]); try self.emit(")); const exp = @as(i32, @intFromFloat(@log2(x))); break :blk std.math.ldexp(@as(f64, 1.0), exp - 52); }"); } else try self.emit("std.math.floatMin(f64)");
}
