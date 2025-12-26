/// Python decimal module - Decimal fixed-point arithmetic
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");
const NativeCodegen = h.NativeCodegen;
const CodegenError = h.CodegenError;

const ctx_val = "struct { prec: i64 = 28, rounding: []const u8 = \"ROUND_HALF_EVEN\", Emin: i64 = -999999, Emax: i64 = 999999, capitals: i64 = 1, clamp: i64 = 0 }{}";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Decimal", genDecimal },
    .{ "setcontext", genSetcontext },
    .{ "getcontext", genGetcontext },
    .{ "localcontext", genLocalcontext },
    .{ "BasicContext", genBasicContext },
    .{ "ExtendedContext", genExtendedContext },
    .{ "DefaultContext", genDefaultContext },
    .{ "ROUND_CEILING", genRoundCeiling },
    .{ "ROUND_DOWN", genRoundDown },
    .{ "ROUND_FLOOR", genRoundFloor },
    .{ "ROUND_HALF_DOWN", genRoundHalfDown },
    .{ "ROUND_HALF_EVEN", genRoundHalfEven },
    .{ "ROUND_HALF_UP", genRoundHalfUp },
    .{ "ROUND_UP", genRoundUp },
    .{ "ROUND_05UP", genRound05Up },
    .{ "DecimalException", genDecimalException },
    .{ "InvalidOperation", genInvalidOperation },
    .{ "DivisionByZero", genDivisionByZero },
    .{ "Overflow", genOverflow },
    .{ "Underflow", genUnderflow },
    .{ "Inexact", genInexact },
    .{ "Rounded", genRounded },
    .{ "Subnormal", genSubnormal },
    .{ "FloatOperation", genFloatOperation },
    .{ "Clamped", genClamped },
});

fn genDecimal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("runtime.Decimal{ .value = 0 }");
        return;
    }
    try self.emit("runtime.Decimal{ .value = ");
    if (args[0] == .constant and args[0].constant.value == .string) {
        try self.emit("std.fmt.parseFloat(f64, ");
        try self.genExpr(args[0]);
        try self.emit(") catch 0");
    } else if (args[0] == .constant) {
        try self.emit("@as(f64, @floatFromInt(");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.genExpr(args[0]);
    }
    try self.emit(" }");
}

fn genSetcontext(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("{}");
}

fn genGetcontext(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit(ctx_val);
}

fn genLocalcontext(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit(ctx_val);
}

fn genBasicContext(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit(ctx_val);
}

fn genExtendedContext(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit(ctx_val);
}

fn genDefaultContext(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit(ctx_val);
}

fn genRoundCeiling(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("\"ROUND_CEILING\"");
}

fn genRoundDown(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("\"ROUND_DOWN\"");
}

fn genRoundFloor(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("\"ROUND_FLOOR\"");
}

fn genRoundHalfDown(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("\"ROUND_HALF_DOWN\"");
}

fn genRoundHalfEven(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("\"ROUND_HALF_EVEN\"");
}

fn genRoundHalfUp(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("\"ROUND_HALF_UP\"");
}

fn genRoundUp(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("\"ROUND_UP\"");
}

fn genRound05Up(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("\"ROUND_05UP\"");
}

fn genDecimalException(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("\"DecimalException\"");
}

fn genInvalidOperation(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("\"InvalidOperation\"");
}

fn genDivisionByZero(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("\"DivisionByZero\"");
}

fn genOverflow(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("\"Overflow\"");
}

fn genUnderflow(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("\"Underflow\"");
}

fn genInexact(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("\"Inexact\"");
}

fn genRounded(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("\"Rounded\"");
}

fn genSubnormal(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("\"Subnormal\"");
}

fn genFloatOperation(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("\"FloatOperation\"");
}

fn genClamped(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("\"Clamped\"");
}
