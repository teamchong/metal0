/// Python _decimal module - Internal decimal support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Decimal", genDecimal }, .{ "Context", genConst(".{ .prec = 28, .rounding = 4, .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }") },
    .{ "localcontext", genConst(".{ .prec = 28, .rounding = 4, .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }") },
    .{ "getcontext", genConst(".{ .prec = 28, .rounding = 4, .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }") }, .{ "setcontext", genConst("{}") },
    .{ "BasicContext", genConst(".{ .prec = 9, .rounding = 4, .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }") },
    .{ "ExtendedContext", genConst(".{ .prec = 9, .rounding = 4, .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }") },
    .{ "DefaultContext", genConst(".{ .prec = 28, .rounding = 4, .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }") },
    .{ "MAX_PREC", genConst("@as(i64, 999999999999999999)") }, .{ "MAX_EMAX", genConst("@as(i64, 999999999999999999)") },
    .{ "MIN_EMIN", genConst("@as(i64, -999999999999999999)") }, .{ "MIN_ETINY", genConst("@as(i64, -999999999999999999)") },
    .{ "ROUND_CEILING", genConst("\"ROUND_CEILING\"") }, .{ "ROUND_DOWN", genConst("\"ROUND_DOWN\"") }, .{ "ROUND_FLOOR", genConst("\"ROUND_FLOOR\"") },
    .{ "ROUND_HALF_DOWN", genConst("\"ROUND_HALF_DOWN\"") }, .{ "ROUND_HALF_EVEN", genConst("\"ROUND_HALF_EVEN\"") },
    .{ "ROUND_HALF_UP", genConst("\"ROUND_HALF_UP\"") }, .{ "ROUND_UP", genConst("\"ROUND_UP\"") }, .{ "ROUND_05UP", genConst("\"ROUND_05UP\"") },
});

fn genDecimal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const v = "); try self.genExpr(args[0]); try self.emit("; _ = v; break :blk .{ .sign = 0, .digits = &[_]u8{}, .exp = 0 }; }"); } else { try self.emit(".{ .sign = 0, .digits = &[_]u8{}, .exp = 0 }"); }
}
