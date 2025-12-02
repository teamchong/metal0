/// Python decimal module - Decimal fixed-point arithmetic
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Decimal", genDecimal },
    .{ "getcontext", genGetcontext }, .{ "setcontext", genUnit }, .{ "localcontext", genGetcontext },
    .{ "BasicContext", genGetcontext }, .{ "ExtendedContext", genGetcontext }, .{ "DefaultContext", genGetcontext },
    .{ "ROUND_CEILING", genRoundCeiling }, .{ "ROUND_DOWN", genRoundDown }, .{ "ROUND_FLOOR", genRoundFloor },
    .{ "ROUND_HALF_DOWN", genRoundHalfDown }, .{ "ROUND_HALF_EVEN", genRoundHalfEven },
    .{ "ROUND_HALF_UP", genRoundHalfUp }, .{ "ROUND_UP", genRoundUp }, .{ "ROUND_05UP", genRound05Up },
    .{ "DecimalException", genDecimalException }, .{ "InvalidOperation", genInvalidOperation },
    .{ "DivisionByZero", genDivisionByZero }, .{ "Overflow", genOverflow }, .{ "Underflow", genUnderflow },
    .{ "Inexact", genInexact }, .{ "Rounded", genRounded }, .{ "Subnormal", genSubnormal },
    .{ "FloatOperation", genFloatOperation }, .{ "Clamped", genClamped },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }

// Rounding constants
fn genRoundCeiling(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ROUND_CEILING\""); }
fn genRoundDown(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ROUND_DOWN\""); }
fn genRoundFloor(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ROUND_FLOOR\""); }
fn genRoundHalfDown(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ROUND_HALF_DOWN\""); }
fn genRoundHalfEven(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ROUND_HALF_EVEN\""); }
fn genRoundHalfUp(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ROUND_HALF_UP\""); }
fn genRoundUp(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ROUND_UP\""); }
fn genRound05Up(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ROUND_05UP\""); }

// Exception types
fn genDecimalException(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"DecimalException\""); }
fn genInvalidOperation(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"InvalidOperation\""); }
fn genDivisionByZero(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"DivisionByZero\""); }
fn genOverflow(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"Overflow\""); }
fn genUnderflow(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"Underflow\""); }
fn genInexact(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"Inexact\""); }
fn genRounded(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"Rounded\""); }
fn genSubnormal(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"Subnormal\""); }
fn genFloatOperation(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"FloatOperation\""); }
fn genClamped(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"Clamped\""); }

// Complex types
fn genDecimal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("runtime.Decimal{ .value = 0 }"); return; }
    try self.emit("runtime.Decimal{ .value = ");
    if (args[0] == .constant) {
        if (args[0].constant.value == .string) {
            try self.emit("std.fmt.parseFloat(f64, "); try self.genExpr(args[0]); try self.emit(") catch 0");
        } else {
            try self.emit("@as(f64, @floatFromInt("); try self.genExpr(args[0]); try self.emit("))");
        }
    } else try self.genExpr(args[0]);
    try self.emit(" }");
}

fn genGetcontext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { prec: i64 = 28, rounding: []const u8 = \"ROUND_HALF_EVEN\", Emin: i64 = -999999, Emax: i64 = 999999, capitals: i64 = 1, clamp: i64 = 0 }{}");
}
