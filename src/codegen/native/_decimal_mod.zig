/// Python _decimal module - Internal decimal support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Decimal", genDecimal }, .{ "Context", h.c(".{ .prec = 28, .rounding = 4, .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }") },
    .{ "localcontext", h.c(".{ .prec = 28, .rounding = 4, .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }") },
    .{ "getcontext", h.c(".{ .prec = 28, .rounding = 4, .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }") }, .{ "setcontext", h.c("{}") },
    .{ "BasicContext", h.c(".{ .prec = 9, .rounding = 4, .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }") },
    .{ "ExtendedContext", h.c(".{ .prec = 9, .rounding = 4, .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }") },
    .{ "DefaultContext", h.c(".{ .prec = 28, .rounding = 4, .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }") },
    .{ "MAX_PREC", h.I64(999999999999999999) }, .{ "MAX_EMAX", h.I64(999999999999999999) },
    .{ "MIN_EMIN", h.I64(-999999999999999999) }, .{ "MIN_ETINY", h.I64(-999999999999999999) },
    .{ "ROUND_CEILING", h.c("\"ROUND_CEILING\"") }, .{ "ROUND_DOWN", h.c("\"ROUND_DOWN\"") }, .{ "ROUND_FLOOR", h.c("\"ROUND_FLOOR\"") },
    .{ "ROUND_HALF_DOWN", h.c("\"ROUND_HALF_DOWN\"") }, .{ "ROUND_HALF_EVEN", h.c("\"ROUND_HALF_EVEN\"") },
    .{ "ROUND_HALF_UP", h.c("\"ROUND_HALF_UP\"") }, .{ "ROUND_UP", h.c("\"ROUND_UP\"") }, .{ "ROUND_05UP", h.c("\"ROUND_05UP\"") },
});

fn genDecimal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const v = "); try self.genExpr(args[0]); try self.emit("; _ = v; break :blk .{ .sign = 0, .digits = &[_]u8{}, .exp = 0 }; }"); } else { try self.emit(".{ .sign = 0, .digits = &[_]u8{}, .exp = 0 }"); }
}
