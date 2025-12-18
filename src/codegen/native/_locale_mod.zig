/// Python _locale module - C accelerator for locale (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
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
    const b = try self.getBuilder();
    if (args.len > 1) {
        try self.genExpr(args[1]);
    } else {
        try b.emitValue(builder_mod.ZigValue.string("C"), builder_mod.EmitConfig.forExpression());
    }
}

fn genLocaleconv(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .decimal_point = \".\", .thousands_sep = \"\", .grouping = \"\", .int_curr_symbol = \"\", .currency_symbol = \"\", .mon_decimal_point = \"\", .mon_thousands_sep = \"\", .mon_grouping = \"\", .positive_sign = \"\", .negative_sign = \"\", .int_frac_digits = 127, .frac_digits = 127, .p_cs_precedes = 127, .p_sep_by_space = 127, .n_cs_precedes = 127, .n_sep_by_space = 127, .p_sign_posn = 127, .n_sign_posn = 127 }"), builder_mod.EmitConfig.forExpression());
}

fn genGetlocale(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ \"C\", null }"), builder_mod.EmitConfig.forExpression());
}

fn genGetdefaultlocale(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ \"en_US\", \"UTF-8\" }"), builder_mod.EmitConfig.forExpression());
}

fn genGetpreferredencoding(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("UTF-8"), builder_mod.EmitConfig.forExpression());
}

fn genNlLanginfo(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genStrcoll(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len >= 2) {
        try self.emit("std.mem.order(u8, ");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[1]);
        try self.emit(")");
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("std.math.Order.eq"), builder_mod.EmitConfig.forExpression());
    }
}

fn genStrxfrm(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
    }
}

fn genLcCtype(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0)"), builder_mod.EmitConfig.forExpression());
}

fn genLcCollate(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 1)"), builder_mod.EmitConfig.forExpression());
}

fn genLcTime(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 2)"), builder_mod.EmitConfig.forExpression());
}

fn genLcNumeric(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 3)"), builder_mod.EmitConfig.forExpression());
}

fn genLcMonetary(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 4)"), builder_mod.EmitConfig.forExpression());
}

fn genLcMessages(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 5)"), builder_mod.EmitConfig.forExpression());
}

fn genLcAll(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 6)"), builder_mod.EmitConfig.forExpression());
}

fn genCodeset(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 14)"), builder_mod.EmitConfig.forExpression());
}

fn genDTFmt(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 1)"), builder_mod.EmitConfig.forExpression());
}

fn genDFmt(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 2)"), builder_mod.EmitConfig.forExpression());
}

fn genTFmt(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 3)"), builder_mod.EmitConfig.forExpression());
}

fn genRadixchar(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 65536)"), builder_mod.EmitConfig.forExpression());
}

fn genThousep(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 65537)"), builder_mod.EmitConfig.forExpression());
}

fn genYesexpr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 52)"), builder_mod.EmitConfig.forExpression());
}

fn genNoexpr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 53)"), builder_mod.EmitConfig.forExpression());
}

fn genCrncystr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 65538)"), builder_mod.EmitConfig.forExpression());
}

fn genEra(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 45)"), builder_mod.EmitConfig.forExpression());
}

fn genEraDTFmt(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 46)"), builder_mod.EmitConfig.forExpression());
}

fn genEraDFmt(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 47)"), builder_mod.EmitConfig.forExpression());
}

fn genEraTFmt(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 48)"), builder_mod.EmitConfig.forExpression());
}

fn genAltDigits(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 49)"), builder_mod.EmitConfig.forExpression());
}
