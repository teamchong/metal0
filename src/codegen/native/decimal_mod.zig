/// Python decimal module - Decimal fixed-point arithmetic
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Decimal", genDecimal }, .{ "getcontext", genCtx }, .{ "setcontext", genUnit }, .{ "localcontext", genCtx },
    .{ "BasicContext", genCtx }, .{ "ExtendedContext", genCtx }, .{ "DefaultContext", genCtx },
    .{ "ROUND_CEILING", genRCeil }, .{ "ROUND_DOWN", genRDown }, .{ "ROUND_FLOOR", genRFloor },
    .{ "ROUND_HALF_DOWN", genRHD }, .{ "ROUND_HALF_EVEN", genRHE }, .{ "ROUND_HALF_UP", genRHU },
    .{ "ROUND_UP", genRUp }, .{ "ROUND_05UP", genR05 },
    .{ "DecimalException", genExDec }, .{ "InvalidOperation", genExInv }, .{ "DivisionByZero", genExDiv },
    .{ "Overflow", genExOv }, .{ "Underflow", genExUn }, .{ "Inexact", genExIn }, .{ "Rounded", genExRo },
    .{ "Subnormal", genExSu }, .{ "FloatOperation", genExFl }, .{ "Clamped", genExCl },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genCtx(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "struct { prec: i64 = 28, rounding: []const u8 = \"ROUND_HALF_EVEN\", Emin: i64 = -999999, Emax: i64 = 999999, capitals: i64 = 1, clamp: i64 = 0 }{}"); }
fn genRCeil(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ROUND_CEILING\""); }
fn genRDown(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ROUND_DOWN\""); }
fn genRFloor(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ROUND_FLOOR\""); }
fn genRHD(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ROUND_HALF_DOWN\""); }
fn genRHE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ROUND_HALF_EVEN\""); }
fn genRHU(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ROUND_HALF_UP\""); }
fn genRUp(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ROUND_UP\""); }
fn genR05(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ROUND_05UP\""); }
fn genExDec(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"DecimalException\""); }
fn genExInv(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"InvalidOperation\""); }
fn genExDiv(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"DivisionByZero\""); }
fn genExOv(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"Overflow\""); }
fn genExUn(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"Underflow\""); }
fn genExIn(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"Inexact\""); }
fn genExRo(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"Rounded\""); }
fn genExSu(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"Subnormal\""); }
fn genExFl(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"FloatOperation\""); }
fn genExCl(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"Clamped\""); }

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
