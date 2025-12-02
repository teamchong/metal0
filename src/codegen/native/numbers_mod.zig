/// Python numbers module - Numeric abstract base classes
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Number", genNumber },
    .{ "Complex", genComplex },
    .{ "Real", genReal },
    .{ "Rational", genRational },
    .{ "Integral", genIntegral },
});

/// Generate numbers.Number - Root of numeric hierarchy (ABC)
pub fn genNumber(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { _is_number: bool = true, pub fn register(_: @This(), _: std.mem.Allocator, _: anytype) !void {} }{}");
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
    try self.emit("pub fn conjugate(self: @This()) @This() { return .{ .real = __self.real, .imag = -__self.imag }; }\n");
    try self.emitIndent();
    try self.emit("pub fn __abs__(self: @This()) f64 { return @sqrt(__self.real * __self.real + __self.imag * __self.imag); }\n");
    try self.emitIndent();
    try self.emit("pub fn __add__(self: @This(), other: @This()) @This() { return .{ .real = __self.real + other.real, .imag = __self.imag + other.imag }; }\n");
    try self.emitIndent();
    try self.emit("pub fn __sub__(self: @This(), other: @This()) @This() { return .{ .real = __self.real - other.real, .imag = __self.imag - other.imag }; }\n");
    try self.emitIndent();
    try self.emit("pub fn __mul__(self: @This(), other: @This()) @This() { return .{ .real = __self.real * other.real - __self.imag * other.imag, .imag = __self.real * other.imag + __self.imag * other.real }; }\n");
    try self.emitIndent();
    try self.emit("pub fn __neg__(self: @This()) @This() { return .{ .real = -__self.real, .imag = -__self.imag }; }\n");
    try self.emitIndent();
    try self.emit("pub fn __pos__(self: @This()) @This() { return __self; }\n");
    try self.emitIndent();
    try self.emit("pub fn __eq__(self: @This(), other: @This()) bool { return __self.real == other.real and __self.imag == other.imag; }\n");
    try self.emitIndent();
    try self.emit("pub fn __bool__(s: @This()) bool { return s.real != 0.0 or s.imag != 0.0; }\n");
    try self.emitIndent();
    try self.emit("pub fn register(_: @This(), _: std.mem.Allocator, _: anytype) !void {}\n");
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
    try self.emit("pub fn __float__(self: @This()) f64 { return __self.value; }\n");
    try self.emitIndent();
    try self.emit("pub fn __trunc__(self: @This()) i64 { return @intFromFloat(@trunc(__self.value)); }\n");
    try self.emitIndent();
    try self.emit("pub fn __floor__(self: @This()) i64 { return @intFromFloat(@floor(__self.value)); }\n");
    try self.emitIndent();
    try self.emit("pub fn __ceil__(self: @This()) i64 { return @intFromFloat(@ceil(__self.value)); }\n");
    try self.emitIndent();
    try self.emit("pub fn __round__(self: @This()) i64 { return @intFromFloat(@round(__self.value)); }\n");
    try self.emitIndent();
    try self.emit("pub fn __divmod__(self: @This(), other: @This()) struct { f64, f64 } { return .{ @divFloor(__self.value, other.value), @mod(__self.value, other.value) }; }\n");
    try self.emitIndent();
    try self.emit("pub fn __floordiv__(self: @This(), other: @This()) f64 { return @divFloor(__self.value, other.value); }\n");
    try self.emitIndent();
    try self.emit("pub fn __mod__(self: @This(), other: @This()) f64 { return @mod(__self.value, other.value); }\n");
    try self.emitIndent();
    try self.emit("pub fn __lt__(self: @This(), other: @This()) bool { return __self.value < other.value; }\n");
    try self.emitIndent();
    try self.emit("pub fn __le__(self: @This(), other: @This()) bool { return __self.value <= other.value; }\n");
    try self.emitIndent();
    try self.emit("pub fn real(self: @This()) f64 { return __self.value; }\n");
    try self.emitIndent();
    try self.emit("pub fn imag(self: @This()) f64 { return 0.0; }\n");
    try self.emitIndent();
    try self.emit("pub fn conjugate(self: @This()) @This() { return __self; }\n");
    try self.emitIndent();
    try self.emit("pub fn register(_: @This(), _: std.mem.Allocator, _: anytype) !void {}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate numbers.Rational - Rational numbers (ABC)
pub fn genRational(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Generate a type reference, not an instance - for ABC.register() pattern
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("numerator: i64 = 0,\n");
    try self.emitIndent();
    try self.emit("denominator: i64 = 1,\n");
    try self.emitIndent();
    try self.emit("pub fn __float__(s: @This()) f64 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("return @as(f64, @floatFromInt(s.numerator)) / @as(f64, @floatFromInt(s.denominator));\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    // ABC register method - no-op at AOT compile time
    try self.emit("pub fn register(_: @This(), _: std.mem.Allocator, _: anytype) !void {}\n");
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
    try self.emit("pub fn __int__(self: @This()) i64 { return __self.value; }\n");
    try self.emitIndent();
    try self.emit("pub fn __index__(self: @This()) i64 { return __self.value; }\n");
    try self.emitIndent();
    try self.emit("pub fn __and__(self: @This(), other: @This()) @This() { return .{ .value = __self.value & other.value }; }\n");
    try self.emitIndent();
    try self.emit("pub fn __or__(self: @This(), other: @This()) @This() { return .{ .value = __self.value | other.value }; }\n");
    try self.emitIndent();
    try self.emit("pub fn __xor__(self: @This(), other: @This()) @This() { return .{ .value = __self.value ^ other.value }; }\n");
    try self.emitIndent();
    try self.emit("pub fn __invert__(self: @This()) @This() { return .{ .value = ~__self.value }; }\n");
    try self.emitIndent();
    try self.emit("pub fn __lshift__(self: @This(), n: i64) @This() { return .{ .value = __self.value << @intCast(n) }; }\n");
    try self.emitIndent();
    try self.emit("pub fn __rshift__(self: @This(), n: i64) @This() { return .{ .value = __self.value >> @intCast(n) }; }\n");
    try self.emitIndent();
    try self.emit("pub fn numerator(self: @This()) i64 { return __self.value; }\n");
    try self.emitIndent();
    try self.emit("pub fn denominator(self: @This()) i64 { return 1; }\n");
    try self.emitIndent();
    try self.emit("pub fn register(_: @This(), _: std.mem.Allocator, _: anytype) !void {}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}
