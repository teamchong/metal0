/// Python decimal module - Decimal fixed-point arithmetic
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Decimal", genDecimal }, .{ "setcontext", genConst("{}") },
    .{ "getcontext", genConst("struct { prec: i64 = 28, rounding: []const u8 = \"ROUND_HALF_EVEN\", Emin: i64 = -999999, Emax: i64 = 999999, capitals: i64 = 1, clamp: i64 = 0 }{}") },
    .{ "localcontext", genConst("struct { prec: i64 = 28, rounding: []const u8 = \"ROUND_HALF_EVEN\", Emin: i64 = -999999, Emax: i64 = 999999, capitals: i64 = 1, clamp: i64 = 0 }{}") },
    .{ "BasicContext", genConst("struct { prec: i64 = 28, rounding: []const u8 = \"ROUND_HALF_EVEN\", Emin: i64 = -999999, Emax: i64 = 999999, capitals: i64 = 1, clamp: i64 = 0 }{}") },
    .{ "ExtendedContext", genConst("struct { prec: i64 = 28, rounding: []const u8 = \"ROUND_HALF_EVEN\", Emin: i64 = -999999, Emax: i64 = 999999, capitals: i64 = 1, clamp: i64 = 0 }{}") },
    .{ "DefaultContext", genConst("struct { prec: i64 = 28, rounding: []const u8 = \"ROUND_HALF_EVEN\", Emin: i64 = -999999, Emax: i64 = 999999, capitals: i64 = 1, clamp: i64 = 0 }{}") },
    .{ "ROUND_CEILING", genConst("\"ROUND_CEILING\"") }, .{ "ROUND_DOWN", genConst("\"ROUND_DOWN\"") }, .{ "ROUND_FLOOR", genConst("\"ROUND_FLOOR\"") },
    .{ "ROUND_HALF_DOWN", genConst("\"ROUND_HALF_DOWN\"") }, .{ "ROUND_HALF_EVEN", genConst("\"ROUND_HALF_EVEN\"") }, .{ "ROUND_HALF_UP", genConst("\"ROUND_HALF_UP\"") },
    .{ "ROUND_UP", genConst("\"ROUND_UP\"") }, .{ "ROUND_05UP", genConst("\"ROUND_05UP\"") },
    .{ "DecimalException", genConst("\"DecimalException\"") }, .{ "InvalidOperation", genConst("\"InvalidOperation\"") }, .{ "DivisionByZero", genConst("\"DivisionByZero\"") },
    .{ "Overflow", genConst("\"Overflow\"") }, .{ "Underflow", genConst("\"Underflow\"") }, .{ "Inexact", genConst("\"Inexact\"") }, .{ "Rounded", genConst("\"Rounded\"") },
    .{ "Subnormal", genConst("\"Subnormal\"") }, .{ "FloatOperation", genConst("\"FloatOperation\"") }, .{ "Clamped", genConst("\"Clamped\"") },
});

fn genDecimal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("runtime.Decimal{ .value = 0 }"); return; }
    try self.emit("runtime.Decimal{ .value = ");
    if (args[0] == .constant and args[0].constant.value == .string) {
        try self.emit("std.fmt.parseFloat(f64, "); try self.genExpr(args[0]); try self.emit(") catch 0");
    } else if (args[0] == .constant) {
        try self.emit("@as(f64, @floatFromInt("); try self.genExpr(args[0]); try self.emit("))");
    } else try self.genExpr(args[0]);
    try self.emit(" }");
}
