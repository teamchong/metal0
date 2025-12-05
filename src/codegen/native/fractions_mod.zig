/// Python fractions module - Rational number arithmetic
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

// Fraction init accepts i64 directly or BigInt via conversion
// For BigInt: use toInt64() which returns ?i64, fall back to 0 if too large
const FractionStruct = "struct { numerator: i64, denominator: i64, pub fn init(num: anytype, den: anytype) @This() { const n = toI64(num); const d = toI64(den); const g = gcd(if (n < 0) -n else n, if (d < 0) -d else d); const sign: i64 = if ((n < 0) != (d < 0)) -1 else 1; return @This(){ .numerator = sign * @divTrunc(if (n < 0) -n else n, g), .denominator = @divTrunc(if (d < 0) -d else d, g) }; } fn toI64(v: anytype) i64 { const T = @TypeOf(v); const info = @typeInfo(T); if (info == .int or info == .comptime_int) return @as(i64, @intCast(v)); if (info == .@\"struct\" and @hasDecl(T, \"toInt64\")) { return v.toInt64() orelse 0; } return 0; } fn gcd(a: i64, b: i64) i64 { if (b == 0) return a; return gcd(b, @mod(a, b)); } pub fn add(s: @This(), other: @This()) @This() { return @This().init(s.numerator * other.denominator + other.numerator * s.denominator, s.denominator * other.denominator); } pub fn sub(s: @This(), other: @This()) @This() { return @This().init(s.numerator * other.denominator - other.numerator * s.denominator, s.denominator * other.denominator); } pub fn mul(s: @This(), other: @This()) @This() { return @This().init(s.numerator * other.numerator, s.denominator * other.denominator); } pub fn div(s: @This(), other: @This()) @This() { return @This().init(s.numerator * other.denominator, s.denominator * other.numerator); } pub fn limit_denominator(s: @This(), max_denominator: i64) @This() { if (s.denominator <= max_denominator) return s; return @This().init(@divTrunc(s.numerator * max_denominator, s.denominator), max_denominator); } pub fn toFloat(s: @This()) f64 { return @as(f64, @floatFromInt(s.numerator)) / @as(f64, @floatFromInt(s.denominator)); } }";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Fraction", genFraction },
    .{ "gcd", h.wrap2("blk: { var _a: i64 = @intCast(", "); var _b: i64 = @intCast(", "); if (_a < 0) _a = -_a; if (_b < 0) _b = -_b; while (_b != 0) { const t = _b; _b = @mod(_a, _b); _a = t; } break :blk _a; }", "@as(i64, 1)") },
});

fn genFraction(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit(FractionStruct);
    if (args.len == 0) {
        // Type reference only (R = fractions.Fraction) - just emit the type
        // The caller (assign.zig) should handle emitting "const R = " prefix
        return;
    } else if (args.len == 1) {
        try self.emit(".init(");
        try self.genExpr(args[0]);
        try self.emit(", 1)");
    } else if (args.len >= 2) {
        try self.emit(".init(");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[1]);
        try self.emit(")");
    }
}
