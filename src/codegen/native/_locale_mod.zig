/// Python _locale module - C accelerator for locale (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "setlocale", genSetlocale },
    .{ "localeconv", genLocaleconv },
    .{ "getlocale", genGetlocale },
    .{ "getdefaultlocale", genGetdefaultlocale },
    .{ "getpreferredencoding", genGetpreferredencoding },
    .{ "nl_langinfo", genNlLanginfo },
    .{ "strcoll", genStrcoll },
    .{ "strxfrm", genStrxfrm },
    .{ "LC_CTYPE", genLcCtype },
    .{ "LC_COLLATE", genLcCollate },
    .{ "LC_TIME", genLcTime },
    .{ "LC_NUMERIC", genLcNumeric },
    .{ "LC_MONETARY", genLcMonetary },
    .{ "LC_MESSAGES", genLcMessages },
    .{ "LC_ALL", genLcAll },
    .{ "CODESET", genCodeset },
    .{ "D_T_FMT", genDTFmt },
    .{ "D_FMT", genDFmt },
    .{ "T_FMT", genTFmt },
    .{ "RADIXCHAR", genRadixchar },
    .{ "THOUSEP", genThousep },
    .{ "YESEXPR", genYesexpr },
    .{ "NOEXPR", genNoexpr },
    .{ "CRNCYSTR", genCrncystr },
    .{ "ERA", genEra },
    .{ "ERA_D_T_FMT", genEraDTFmt },
    .{ "ERA_D_FMT", genEraDFmt },
    .{ "ERA_T_FMT", genEraTFmt },
    .{ "ALT_DIGITS", genAltDigits },
});

fn genSetlocale(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len > 1) {
        try self.genExpr(args[1]);
    } else {
        try self.emit("\"C\"");
    }
}

fn genLocaleconv(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit(".{ .decimal_point = \".\", .thousands_sep = \"\", .grouping = \"\", .int_curr_symbol = \"\", .currency_symbol = \"\", .mon_decimal_point = \"\", .mon_thousands_sep = \"\", .mon_grouping = \"\", .positive_sign = \"\", .negative_sign = \"\", .int_frac_digits = 127, .frac_digits = 127, .p_cs_precedes = 127, .p_sep_by_space = 127, .n_cs_precedes = 127, .n_sep_by_space = 127, .p_sign_posn = 127, .n_sign_posn = 127 }");
}

fn genGetlocale(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit(".{ \"C\", null }");
}

fn genGetdefaultlocale(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit(".{ \"en_US\", \"UTF-8\" }");
}

fn genGetpreferredencoding(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("\"UTF-8\"");
}

fn genNlLanginfo(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("\"\"");
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

fn genLcCtype(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 0)");
}

fn genLcCollate(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 1)");
}

fn genLcTime(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 2)");
}

fn genLcNumeric(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 3)");
}

fn genLcMonetary(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 4)");
}

fn genLcMessages(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 5)");
}

fn genLcAll(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 6)");
}

fn genCodeset(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 14)");
}

fn genDTFmt(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 1)");
}

fn genDFmt(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 2)");
}

fn genTFmt(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 3)");
}

fn genRadixchar(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 65536)");
}

fn genThousep(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 65537)");
}

fn genYesexpr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 52)");
}

fn genNoexpr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 53)");
}

fn genCrncystr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 65538)");
}

fn genEra(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 45)");
}

fn genEraDTFmt(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 46)");
}

fn genEraDFmt(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 47)");
}

fn genEraTFmt(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 48)");
}

fn genAltDigits(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try self.emit("@as(i32, 49)");
}
