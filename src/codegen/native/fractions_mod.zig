/// Python fractions module - Rational number arithmetic
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Fraction", genFraction }, .{ "gcd", genGcd },
});

const FractionStruct = "struct { numerator: i64, denominator: i64, pub fn init(num: i64, den: i64) @This() { const g = gcd(if (num < 0) -num else num, if (den < 0) -den else den); const sign: i64 = if ((num < 0) != (den < 0)) -1 else 1; return @This(){ .numerator = sign * @divTrunc(if (num < 0) -num else num, g), .denominator = @divTrunc(if (den < 0) -den else den, g) }; } fn gcd(a: i64, b: i64) i64 { if (b == 0) return a; return gcd(b, @mod(a, b)); } pub fn add(s: @This(), other: @This()) @This() { return @This().init(s.numerator * other.denominator + other.numerator * s.denominator, s.denominator * other.denominator); } pub fn sub(s: @This(), other: @This()) @This() { return @This().init(s.numerator * other.denominator - other.numerator * s.denominator, s.denominator * other.denominator); } pub fn mul(s: @This(), other: @This()) @This() { return @This().init(s.numerator * other.numerator, s.denominator * other.denominator); } pub fn div(s: @This(), other: @This()) @This() { return @This().init(s.numerator * other.denominator, s.denominator * other.numerator); } pub fn limit_denominator(s: @This(), max_denominator: i64) @This() { if (s.denominator <= max_denominator) return s; return @This().init(@divTrunc(s.numerator * max_denominator, s.denominator), max_denominator); } pub fn toFloat(s: @This()) f64 { return @as(f64, @floatFromInt(s.numerator)) / @as(f64, @floatFromInt(s.denominator)); } }";

fn genFraction(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit(FractionStruct);
    if (args.len == 1) { try self.emit(".init("); try self.genExpr(args[0]); try self.emit(", 1)"); }
    else if (args.len >= 2) { try self.emit(".init("); try self.genExpr(args[0]); try self.emit(", "); try self.genExpr(args[1]); try self.emit(")"); }
}

fn genGcd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("@as(i64, 1)"); return; }
    try self.emit("blk: { var _a = "); try self.genExpr(args[0]); try self.emit("; var _b = "); try self.genExpr(args[1]);
    try self.emit("; if (_a < 0) _a = -_a; if (_b < 0) _b = -_b; while (_b != 0) { const t = _b; _b = @mod(_a, _b); _a = t; } break :blk _a; }");
}
