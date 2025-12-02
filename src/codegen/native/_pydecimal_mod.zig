/// Python _pydecimal module - Pure Python decimal implementation
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "decimal", genDecimal },
    .{ "context", h.c(".{ .prec = 28, .rounding = \"ROUND_HALF_EVEN\", .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }") },
    .{ "localcontext", h.c(".{ .prec = 28, .rounding = \"ROUND_HALF_EVEN\", .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }") },
    .{ "getcontext", h.c(".{ .prec = 28, .rounding = \"ROUND_HALF_EVEN\", .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }") },
    .{ "setcontext", h.c("{}") },
});

fn genDecimal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const v = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = v; break :blk .{ .sign = 0, .int = 0, .exp = 0, .is_special = false }; }");
    } else {
        try self.emit(".{ .sign = 0, .int = 0, .exp = 0, .is_special = false }");
    }
}
