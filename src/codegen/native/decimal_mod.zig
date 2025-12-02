/// Python decimal module - Decimal fixed-point arithmetic
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

const ctx = h.c("struct { prec: i64 = 28, rounding: []const u8 = \"ROUND_HALF_EVEN\", Emin: i64 = -999999, Emax: i64 = 999999, capitals: i64 = 1, clamp: i64 = 0 }{}");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Decimal", genDecimal }, .{ "setcontext", h.c("{}") },
    .{ "getcontext", ctx }, .{ "localcontext", ctx }, .{ "BasicContext", ctx }, .{ "ExtendedContext", ctx }, .{ "DefaultContext", ctx },
    .{ "ROUND_CEILING", h.c("\"ROUND_CEILING\"") }, .{ "ROUND_DOWN", h.c("\"ROUND_DOWN\"") }, .{ "ROUND_FLOOR", h.c("\"ROUND_FLOOR\"") },
    .{ "ROUND_HALF_DOWN", h.c("\"ROUND_HALF_DOWN\"") }, .{ "ROUND_HALF_EVEN", h.c("\"ROUND_HALF_EVEN\"") }, .{ "ROUND_HALF_UP", h.c("\"ROUND_HALF_UP\"") },
    .{ "ROUND_UP", h.c("\"ROUND_UP\"") }, .{ "ROUND_05UP", h.c("\"ROUND_05UP\"") },
    .{ "DecimalException", h.c("\"DecimalException\"") }, .{ "InvalidOperation", h.c("\"InvalidOperation\"") }, .{ "DivisionByZero", h.c("\"DivisionByZero\"") },
    .{ "Overflow", h.c("\"Overflow\"") }, .{ "Underflow", h.c("\"Underflow\"") }, .{ "Inexact", h.c("\"Inexact\"") }, .{ "Rounded", h.c("\"Rounded\"") },
    .{ "Subnormal", h.c("\"Subnormal\"") }, .{ "FloatOperation", h.c("\"FloatOperation\"") }, .{ "Clamped", h.c("\"Clamped\"") },
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
