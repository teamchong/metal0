/// Python fractions module - Rational number arithmetic
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate fractions.Fraction(numerator=0, denominator=1) -> Fraction
pub fn genFraction(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("numerator: i64,\n");
    try self.emitIndent();
    try self.emit("denominator: i64,\n");
    try self.emitIndent();
    try self.emit("pub fn init(num: i64, den: i64) @This() {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const g = gcd(if (num < 0) -num else num, if (den < 0) -den else den);\n");
    try self.emitIndent();
    try self.emit("const sign: i64 = if ((num < 0) != (den < 0)) -1 else 1;\n");
    try self.emitIndent();
    try self.emit("return @This(){ .numerator = sign * @divTrunc(if (num < 0) -num else num, g), .denominator = @divTrunc(if (den < 0) -den else den, g) };\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("fn gcd(a: i64, b: i64) i64 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (b == 0) return a;\n");
    try self.emitIndent();
    try self.emit("return gcd(b, @mod(a, b));\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn add(self: @This(), other: @This()) @This() {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("return init(self.numerator * other.denominator + other.numerator * self.denominator, self.denominator * other.denominator);\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn sub(self: @This(), other: @This()) @This() {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("return init(self.numerator * other.denominator - other.numerator * self.denominator, self.denominator * other.denominator);\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn mul(self: @This(), other: @This()) @This() {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("return init(self.numerator * other.numerator, self.denominator * other.denominator);\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn div(self: @This(), other: @This()) @This() {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("return init(self.numerator * other.denominator, self.denominator * other.numerator);\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn limit_denominator(self: @This(), max_denominator: i64) @This() {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (self.denominator <= max_denominator) return self;\n");
    try self.emitIndent();
    try self.emit("return init(@divTrunc(self.numerator * max_denominator, self.denominator), max_denominator);\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn toFloat(self: @This()) f64 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("return @as(f64, @floatFromInt(self.numerator)) / @as(f64, @floatFromInt(self.denominator));\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();

    // Initialize based on args
    if (args.len == 0) {
        try self.emit("}.init(0, 1)");
    } else if (args.len == 1) {
        try self.emit("}.init(");
        try self.genExpr(args[0]);
        try self.emit(", 1)");
    } else {
        try self.emit("}.init(");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[1]);
        try self.emit(")");
    }
}

/// Generate fractions.gcd(a, b) -> greatest common divisor (deprecated, use math.gcd)
pub fn genGcd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("@as(i64, 1)");
        return;
    }

    try self.emit("fractions_gcd_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var _a = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _b = ");
    try self.genExpr(args[1]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("if (_a < 0) _a = -_a;\n");
    try self.emitIndent();
    try self.emit("if (_b < 0) _b = -_b;\n");
    try self.emitIndent();
    try self.emit("while (_b != 0) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const t = _b;\n");
    try self.emitIndent();
    try self.emit("_b = @mod(_a, _b);\n");
    try self.emitIndent();
    try self.emit("_a = t;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :fractions_gcd_blk _a;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}
