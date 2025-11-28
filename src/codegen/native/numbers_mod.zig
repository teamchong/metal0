/// Python numbers module - Numeric abstract base classes
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate numbers.Number - Root of numeric hierarchy (ABC)
pub fn genNumber(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { _is_number: bool = true }{}");
}

/// Generate numbers.Complex - Complex numbers (ABC)
pub fn genComplex(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("real: f64 = 0.0,\n");
    try self.emitIndent();
    try self.emit("imag: f64 = 0.0,\n");
    try self.emitIndent();
    try self.emit("pub fn conjugate(self: @This()) @This() { return .{ .real = self.real, .imag = -self.imag }; }\n");
    try self.emitIndent();
    try self.emit("pub fn __abs__(self: @This()) f64 { return @sqrt(self.real * self.real + self.imag * self.imag); }\n");
    try self.emitIndent();
    try self.emit("pub fn __add__(self: @This(), other: @This()) @This() { return .{ .real = self.real + other.real, .imag = self.imag + other.imag }; }\n");
    try self.emitIndent();
    try self.emit("pub fn __sub__(self: @This(), other: @This()) @This() { return .{ .real = self.real - other.real, .imag = self.imag - other.imag }; }\n");
    try self.emitIndent();
    try self.emit("pub fn __mul__(self: @This(), other: @This()) @This() { return .{ .real = self.real * other.real - self.imag * other.imag, .imag = self.real * other.imag + self.imag * other.real }; }\n");
    try self.emitIndent();
    try self.emit("pub fn __neg__(self: @This()) @This() { return .{ .real = -self.real, .imag = -self.imag }; }\n");
    try self.emitIndent();
    try self.emit("pub fn __pos__(self: @This()) @This() { return self; }\n");
    try self.emitIndent();
    try self.emit("pub fn __eq__(self: @This(), other: @This()) bool { return self.real == other.real and self.imag == other.imag; }\n");
    try self.emitIndent();
    try self.emit("pub fn __bool__(self: @This()) bool { return self.real != 0.0 or self.imag != 0.0; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate numbers.Real - Real numbers (ABC)
pub fn genReal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("value: f64 = 0.0,\n");
    try self.emitIndent();
    try self.emit("pub fn __float__(self: @This()) f64 { return self.value; }\n");
    try self.emitIndent();
    try self.emit("pub fn __trunc__(self: @This()) i64 { return @intFromFloat(@trunc(self.value)); }\n");
    try self.emitIndent();
    try self.emit("pub fn __floor__(self: @This()) i64 { return @intFromFloat(@floor(self.value)); }\n");
    try self.emitIndent();
    try self.emit("pub fn __ceil__(self: @This()) i64 { return @intFromFloat(@ceil(self.value)); }\n");
    try self.emitIndent();
    try self.emit("pub fn __round__(self: @This()) i64 { return @intFromFloat(@round(self.value)); }\n");
    try self.emitIndent();
    try self.emit("pub fn __divmod__(self: @This(), other: @This()) struct { f64, f64 } { return .{ @divFloor(self.value, other.value), @mod(self.value, other.value) }; }\n");
    try self.emitIndent();
    try self.emit("pub fn __floordiv__(self: @This(), other: @This()) f64 { return @divFloor(self.value, other.value); }\n");
    try self.emitIndent();
    try self.emit("pub fn __mod__(self: @This(), other: @This()) f64 { return @mod(self.value, other.value); }\n");
    try self.emitIndent();
    try self.emit("pub fn __lt__(self: @This(), other: @This()) bool { return self.value < other.value; }\n");
    try self.emitIndent();
    try self.emit("pub fn __le__(self: @This(), other: @This()) bool { return self.value <= other.value; }\n");
    try self.emitIndent();
    try self.emit("pub fn real(self: @This()) f64 { return self.value; }\n");
    try self.emitIndent();
    try self.emit("pub fn imag(self: @This()) f64 { return 0.0; }\n");
    try self.emitIndent();
    try self.emit("pub fn conjugate(self: @This()) @This() { return self; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate numbers.Rational - Rational numbers (ABC)
pub fn genRational(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("numerator: i64 = 0,\n");
    try self.emitIndent();
    try self.emit("denominator: i64 = 1,\n");
    try self.emitIndent();
    try self.emit("pub fn __float__(self: @This()) f64 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("return @as(f64, @floatFromInt(self.numerator)) / @as(f64, @floatFromInt(self.denominator));\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate numbers.Integral - Integer numbers (ABC)
pub fn genIntegral(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("value: i64 = 0,\n");
    try self.emitIndent();
    try self.emit("pub fn __int__(self: @This()) i64 { return self.value; }\n");
    try self.emitIndent();
    try self.emit("pub fn __index__(self: @This()) i64 { return self.value; }\n");
    try self.emitIndent();
    try self.emit("pub fn __and__(self: @This(), other: @This()) @This() { return .{ .value = self.value & other.value }; }\n");
    try self.emitIndent();
    try self.emit("pub fn __or__(self: @This(), other: @This()) @This() { return .{ .value = self.value | other.value }; }\n");
    try self.emitIndent();
    try self.emit("pub fn __xor__(self: @This(), other: @This()) @This() { return .{ .value = self.value ^ other.value }; }\n");
    try self.emitIndent();
    try self.emit("pub fn __invert__(self: @This()) @This() { return .{ .value = ~self.value }; }\n");
    try self.emitIndent();
    try self.emit("pub fn __lshift__(self: @This(), n: i64) @This() { return .{ .value = self.value << @intCast(n) }; }\n");
    try self.emitIndent();
    try self.emit("pub fn __rshift__(self: @This(), n: i64) @This() { return .{ .value = self.value >> @intCast(n) }; }\n");
    try self.emitIndent();
    try self.emit("pub fn numerator(self: @This()) i64 { return self.value; }\n");
    try self.emitIndent();
    try self.emit("pub fn denominator(self: @This()) i64 { return 1; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}
