/// Python math module - Mathematical functions
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

// Helper for formatted output
fn emitFmtConst(self: *NativeCodegen, comptime fmt: []const u8, args: anytype) CodegenError!void {
    const b = try self.getBuilder();
    try b.writeFmt(fmt, args);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genRounding(comptime blt: []const u8) h.H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len > 0) {
            const t = self.type_inferrer.inferExpr(args[0]) catch .unknown;
            if (t == .float) {
                try emitConst(self, "@as(i64, @intFromFloat(" ++ blt ++ "(");
                try self.genExpr(args[0]);
                try emitConst(self, ")))");
            } else if (t == .int) {
                try self.genExpr(args[0]);
            } else {
                try emitConst(self, "@as(i64, @intFromFloat(" ++ blt ++ "(@as(f64, ");
                try self.genExpr(args[0]);
                try emitConst(self, "))))");
            }
        } else try emitConst(self, "@as(i64, 0)");
    } }.f;
}

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    // Constants
    .{ "pi", h.F64(3.141592653589793) }, .{ "e", h.F64(2.718281828459045) },
    .{ "tau", h.F64(6.283185307179586) }, .{ "inf", h.c("std.math.inf(f64)") }, .{ "nan", h.c("std.math.nan(f64)") },
    // Rounding
    .{ "ceil", genRounding("@ceil") }, .{ "floor", genRounding("@floor") }, .{ "trunc", genRounding("@trunc") },
    .{ "fabs", h.wrap("@abs(@as(f64, ", "))", "@as(f64, 0.0)") },
    // Number-theoretic
    .{ "factorial", genFactorial }, .{ "gcd", genGcd }, .{ "lcm", genLcm }, .{ "comb", genComb }, .{ "perm", genPerm },
    // Power and log
    .{ "sqrt", h.builtin1("@sqrt", "@as(f64, 0.0)") },
    .{ "isqrt", h.wrap("@as(i64, @intFromFloat(@sqrt(@as(f64, @floatFromInt(", ")))))", "@as(i64, 0)") },
    .{ "exp", h.builtin1("@exp", "@as(f64, 1.0)") }, .{ "exp2", h.builtin1("@exp2", "@as(f64, 1.0)") }, .{ "expm1", h.stdmath1("expm1", "@as(f64, 0.0)") },
    .{ "log", h.builtin1("@log", "@as(f64, 0.0)") }, .{ "log2", h.builtin1("@log2", "@as(f64, 0.0)") },
    .{ "log10", h.builtin1("@log10", "@as(f64, 0.0)") }, .{ "log1p", h.stdmath1("log1p", "@as(f64, 0.0)") },
    .{ "pow", h.wrap2("std.math.pow(f64, @as(f64, ", "), @as(f64, ", "))", "@as(f64, 1.0)") },
    // Trig
    .{ "sin", h.builtin1("@sin", "@as(f64, 0.0)") }, .{ "cos", h.builtin1("@cos", "@as(f64, 1.0)") }, .{ "tan", h.builtin1("@tan", "@as(f64, 0.0)") },
    .{ "asin", h.stdmath1("asin", "@as(f64, 0.0)") }, .{ "acos", h.stdmath1("acos", "@as(f64, 0.0)") },
    .{ "atan", h.stdmath1("atan", "@as(f64, 0.0)") }, .{ "atan2", h.stdmath2("atan2", "@as(f64, 0.0)") },
    // Hyperbolic
    .{ "sinh", h.stdmath1("sinh", "@as(f64, 0.0)") }, .{ "cosh", h.stdmath1("cosh", "@as(f64, 1.0)") }, .{ "tanh", h.stdmath1("tanh", "@as(f64, 0.0)") },
    .{ "asinh", h.stdmath1("asinh", "@as(f64, 0.0)") }, .{ "acosh", h.stdmath1("acosh", "@as(f64, 0.0)") }, .{ "atanh", h.stdmath1("atanh", "@as(f64, 0.0)") },
    // Special
    .{ "erf", h.stdmath1("erf", "@as(f64, 0.0)") },
    .{ "erfc", h.wrap("(1.0 - std.math.erf(@as(f64, ", ")))", "@as(f64, 1.0)") },
    .{ "gamma", h.stdmathT("gamma", "std.math.inf(f64)") }, .{ "lgamma", h.stdmathT("lgamma", "std.math.inf(f64)") },
    // Angular
    .{ "degrees", h.wrap("(", " * 180.0 / 3.141592653589793)", "@as(f64, 0.0)") },
    .{ "radians", h.wrap("(", " * 3.141592653589793 / 180.0)", "@as(f64, 0.0)") },
    // Float manipulation - use runtime.math.copysign to handle PyPowResult
    .{ "copysign", genCopysign },
    .{ "fmod", h.wrap2("@mod(@as(f64, ", "), @as(f64, ", "))", "@as(f64, 0.0)") },
    .{ "frexp", genFrexp }, .{ "modf", genModf },
    .{ "ldexp", h.wrap2("std.math.ldexp(@as(f64, ", "), @as(i32, @intCast(", ")))", "@as(f64, 0.0)") },
    .{ "remainder", h.wrap2("@rem(@as(f64, ", "), @as(f64, ", "))", "@as(f64, 0.0)") },
    // Classification - use runtime.math.* to handle PyPowResult union type
    .{ "isfinite", genIsFinite }, .{ "isinf", genIsInf },
    .{ "isnan", genIsNan },
    .{ "isclose", h.wrap2("std.math.approxEqAbs(f64, @as(f64, ", "), @as(f64, ", "), 1e-9)", "false") },
    // Sums
    .{ "hypot", h.stdmath2("hypot", "@as(f64, 0.0)") }, .{ "dist", genDist }, .{ "fsum", genFsum }, .{ "prod", genProd },
    .{ "nextafter", genNextafter }, .{ "ulp", genUlp },
});

const genFactorial = h.wrapBlk("fact", "var _n = @as(i64, @intCast(__v)); var _result: i64 = 1; while (_n > 1) : (_n -= 1) { _result *= _n; }", "_result", "@as(i64, 1)");

const genGcd = h.wrap2Blk("gcd", "var _a = @abs(@as(i64, @intCast(__v0))); var _b = @abs(@as(i64, @intCast(__v1))); while (_b != 0) { const _t = _b; _b = @mod(_a, _b); _a = _t; }", "_a", "@as(i64, 0)");
const genLcm = h.wrap2Blk("lcm", "const _a = @abs(@as(i64, @intCast(__v0))); const _b = @abs(@as(i64, @intCast(__v1))); var _aa = _a; var _bb = _b; while (_bb != 0) { const _t = _bb; _bb = @mod(_aa, _bb); _aa = _t; }", "if (_a == 0 or _b == 0) @as(i64, 0) else @divExact(_a, _aa) * _b", "@as(i64, 0)");
const genComb = h.wrap2Blk("comb", "const _n = @as(u64, @intCast(__v0)); const _k = @as(u64, @intCast(__v1)); var _result: u64 = 1; var _i: u64 = 0; while (_i < _k) : (_i += 1) { _result = _result * (_n - _i) / (_i + 1); }", "if (_k > _n) @as(i64, 0) else @as(i64, @intCast(_result))", "@as(i64, 0)");

fn genPerm(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 1) {
        try self.withInlineBlock("perm", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const n = @as(u64, @intCast(");
                try c.genExpr(a[0]);
                try emitConst(c, ")); const k = ");
                if (a.len >= 2) {
                    try emitConst(c, "@as(u64, @intCast(");
                    try c.genExpr(a[1]);
                    try emitConst(c, "))");
                } else {
                    try emitConst(c, "n");
                }
                try emitFmtConst(c, "; if (k > n) break :{s} @as(i64, 0); var result: u64 = 1; var i: u64 = 0; while (i < k) : (i += 1) {{ result *= (n - i); }} break :{s} @as(i64, @intCast(result))", .{ label, label });
            }
        }.emit);
    } else {
        try emitConst(self, "@as(i64, 0)");
    }
}
const genFrexp = h.wrapBlk("frexp", "const _val = @as(f64, __v); const _res = std.math.frexp(_val);", ".{ _res.significand, _res.exponent }", ".{ @as(f64, 0.0), @as(i32, 0) }");
const genModf = h.wrapBlk("modf", "const _val = @as(f64, __v); const _frac = _val - @trunc(_val);", ".{ _frac, @trunc(_val) }", ".{ @as(f64, 0.0), @as(f64, 0.0) }");

const genDist = h.wrap2Blk("dist", "var _sum: f64 = 0; for (__v0, __v1) |_pi, _qi| { const _d = _pi - _qi; _sum += _d * _d; }", "@sqrt(_sum)", "@as(f64, 0.0)");

const genFsum = h.wrapBlk("fsum", "var _sum: f64 = 0; for (__v) |_item| { _sum += _item; }", "_sum", "@as(f64, 0.0)");
const genProd = h.wrapBlk("prod", "var _product: f64 = 1; for (__v) |_item| { _product *= _item; }", "_product", "@as(f64, 1.0)");

const genNextafter = h.wrap2("math.nextafter(@as(f64, ", "), @as(f64, ", "), null)", "@as(f64, 0.0)");
const genUlp = h.wrapBlk("ulp", "const _x = @abs(@as(f64, __v)); const _exp = @as(i32, @intFromFloat(@log2(_x)));", "std.math.ldexp(@as(f64, 1.0), _exp - 52)", "std.math.floatMin(f64)");

// Classification functions that handle PyPowResult union type via runtime.math.*
// Note: std.math uses camelCase (isNan, isInf, isFinite)
fn genIsNan(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try emitConst(self, "runtime.math.isNan(");
        try self.genExpr(args[0]);
        try emitConst(self, ")");
    } else {
        try emitConst(self, "false");
    }
}

fn genIsInf(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try emitConst(self, "runtime.math.isInf(");
        try self.genExpr(args[0]);
        try emitConst(self, ")");
    } else {
        try emitConst(self, "false");
    }
}

fn genIsFinite(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try emitConst(self, "runtime.math.isFinite(");
        try self.genExpr(args[0]);
        try emitConst(self, ")");
    } else {
        try emitConst(self, "true");
    }
}

fn genCopysign(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try emitConst(self, "runtime.math.copysign(");
        try self.genExpr(args[0]);
        try emitConst(self, ", ");
        try self.genExpr(args[1]);
        try emitConst(self, ")");
    } else {
        try emitConst(self, "@as(f64, 0.0)");
    }
}
