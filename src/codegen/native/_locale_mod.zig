/// Python _locale module - C accelerator for locale (internal)
/// MIGRATED TO ZIGBUILDER
/// DRY: Uses h.c() and h.I32() factories for simple constant generators
const std = @import("std");
const h = @import("mod_helper.zig");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    // Functions that need args - keep as functions
    .{ "setlocale", genSetlocale },
    .{ "strcoll", genStrcoll },
    .{ "strxfrm", genStrxfrm },
    // Simple constant/struct returns - using h.c() factory
    .{ "localeconv", h.c(".{ .decimal_point = \".\", .thousands_sep = \"\", .grouping = \"\", .int_curr_symbol = \"\", .currency_symbol = \"\", .mon_decimal_point = \"\", .mon_thousands_sep = \"\", .mon_grouping = \"\", .positive_sign = \"\", .negative_sign = \"\", .int_frac_digits = 127, .frac_digits = 127, .p_cs_precedes = 127, .p_sep_by_space = 127, .n_cs_precedes = 127, .n_sep_by_space = 127, .p_sign_posn = 127, .n_sign_posn = 127 }") },
    .{ "getlocale", h.c(".{ \"C\", null }") },
    .{ "getdefaultlocale", h.c(".{ \"en_US\", \"UTF-8\" }") },
    .{ "getpreferredencoding", h.c("\"UTF-8\"") },
    .{ "nl_langinfo", h.c("\"\"") },
    // LC_* locale category constants - using h.I32() factory
    .{ "LC_CTYPE", h.I32(0) },
    .{ "LC_COLLATE", h.I32(1) },
    .{ "LC_TIME", h.I32(2) },
    .{ "LC_NUMERIC", h.I32(3) },
    .{ "LC_MONETARY", h.I32(4) },
    .{ "LC_MESSAGES", h.I32(5) },
    .{ "LC_ALL", h.I32(6) },
    // nl_langinfo constants - using h.I32() factory
    .{ "CODESET", h.I32(14) },
    .{ "D_T_FMT", h.I32(1) },
    .{ "D_FMT", h.I32(2) },
    .{ "T_FMT", h.I32(3) },
    .{ "RADIXCHAR", h.I32(65536) },
    .{ "THOUSEP", h.I32(65537) },
    .{ "YESEXPR", h.I32(52) },
    .{ "NOEXPR", h.I32(53) },
    .{ "CRNCYSTR", h.I32(65538) },
    .{ "ERA", h.I32(45) },
    .{ "ERA_D_T_FMT", h.I32(46) },
    .{ "ERA_D_FMT", h.I32(47) },
    .{ "ERA_T_FMT", h.I32(48) },
    .{ "ALT_DIGITS", h.I32(49) },
});

// Functions that need runtime args
fn genSetlocale(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len > 1) {
        try self.genExpr(args[1]);
    } else {
        try self.emit("\"C\"");
    }
}

fn genStrcoll(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len >= 2) {
        const Ctx = struct { a0: ast.Node, a1: ast.Node };
        try self.emitCallCtx("std.mem.order(u8, ", Ctx{ .a0 = args[0], .a1 = args[1] }, struct {
            pub fn f(s: *h.NativeCodegen, ctx: Ctx) h.CodegenError!void {
                try s.genExpr(ctx.a0);
                try s.emit(", ");
                try s.genExpr(ctx.a1);
            }
        }.f);
    } else {
        try self.emit("std.math.Order.eq");
    }
}

fn genStrxfrm(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"\"");
    }
}
