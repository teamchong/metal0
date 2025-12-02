/// Python _pydecimal module - Pure Python decimal implementation
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "decimal", h.wrap("blk: { const v = ", "; _ = v; break :blk .{ .sign = 0, .int = 0, .exp = 0, .is_special = false }; }", ".{ .sign = 0, .int = 0, .exp = 0, .is_special = false }") },
    .{ "context", h.c(".{ .prec = 28, .rounding = \"ROUND_HALF_EVEN\", .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }") },
    .{ "localcontext", h.c(".{ .prec = 28, .rounding = \"ROUND_HALF_EVEN\", .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }") },
    .{ "getcontext", h.c(".{ .prec = 28, .rounding = \"ROUND_HALF_EVEN\", .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }") },
    .{ "setcontext", h.c("{}") },
});
