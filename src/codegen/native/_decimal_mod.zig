/// Python _decimal module - Internal decimal support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genDecimalZero(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .sign = 0, .digits = &[_]u8{}, .exp = 0 }"); }
fn genContext28(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .prec = 28, .rounding = 4, .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }"); }
fn genContext9(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .prec = 9, .rounding = 4, .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }"); }
fn genMaxPrec(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 999999999999999999)"); }
fn genMinEmin(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, -999999999999999999)"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Decimal", genDecimal }, .{ "Context", genContext28 }, .{ "localcontext", genContext28 },
    .{ "getcontext", genContext28 }, .{ "setcontext", genUnit },
    .{ "BasicContext", genContext9 }, .{ "ExtendedContext", genContext9 }, .{ "DefaultContext", genContext28 },
    .{ "MAX_PREC", genMaxPrec }, .{ "MAX_EMAX", genMaxPrec }, .{ "MIN_EMIN", genMinEmin }, .{ "MIN_ETINY", genMinEmin },
    .{ "ROUND_CEILING", genRoundCeiling }, .{ "ROUND_DOWN", genRoundDown }, .{ "ROUND_FLOOR", genRoundFloor },
    .{ "ROUND_HALF_DOWN", genRoundHalfDown }, .{ "ROUND_HALF_EVEN", genRoundHalfEven },
    .{ "ROUND_HALF_UP", genRoundHalfUp }, .{ "ROUND_UP", genRoundUp }, .{ "ROUND_05UP", genRound05Up },
});

fn genDecimal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const v = "); try self.genExpr(args[0]); try self.emit("; _ = v; break :blk .{ .sign = 0, .digits = &[_]u8{}, .exp = 0 }; }"); } else { try self.emit(".{ .sign = 0, .digits = &[_]u8{}, .exp = 0 }"); }
}

fn genRoundCeiling(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ROUND_CEILING\""); }
fn genRoundDown(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ROUND_DOWN\""); }
fn genRoundFloor(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ROUND_FLOOR\""); }
fn genRoundHalfDown(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ROUND_HALF_DOWN\""); }
fn genRoundHalfEven(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ROUND_HALF_EVEN\""); }
fn genRoundHalfUp(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ROUND_HALF_UP\""); }
fn genRoundUp(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ROUND_UP\""); }
fn genRound05Up(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ROUND_05UP\""); }
