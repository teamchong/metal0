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
        const b = try self.getBuilder();
        try b.write("\"C\"");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

fn genLocaleconv(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(".{ .decimal_point = \".\", .thousands_sep = \"\", .grouping = \"\", .int_curr_symbol = \"\", .currency_symbol = \"\", .mon_decimal_point = \"\", .mon_thousands_sep = \"\", .mon_grouping = \"\", .positive_sign = \"\", .negative_sign = \"\", .int_frac_digits = 127, .frac_digits = 127, .p_cs_precedes = 127, .p_sep_by_space = 127, .n_cs_precedes = 127, .n_sep_by_space = 127, .p_sign_posn = 127, .n_sign_posn = 127 }");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genGetlocale(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(".{ \"C\", null }");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genGetdefaultlocale(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(".{ \"en_US\", \"UTF-8\" }");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genGetpreferredencoding(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("\"UTF-8\"");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genNlLanginfo(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("\"\"");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genStrcoll(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len >= 2) {
        {
            const b = try self.getBuilder();
            try b.write("std.mem.order(u8, ");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[0]);
        {
            const b = try self.getBuilder();
            try b.write(", ");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[1]);
        {
            const b = try self.getBuilder();
            try b.write(")");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
    } else {
        const b = try self.getBuilder();
        try b.write("std.math.Order.eq");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

fn genStrxfrm(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        const b = try self.getBuilder();
        try b.write("\"\"");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

fn genLcCtype(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("@as(i32, 0)");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genLcCollate(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("@as(i32, 1)");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genLcTime(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("@as(i32, 2)");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genLcNumeric(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("@as(i32, 3)");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genLcMonetary(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("@as(i32, 4)");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genLcMessages(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("@as(i32, 5)");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genLcAll(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("@as(i32, 6)");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genCodeset(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("@as(i32, 14)");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genDTFmt(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("@as(i32, 1)");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genDFmt(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("@as(i32, 2)");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genTFmt(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("@as(i32, 3)");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genRadixchar(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("@as(i32, 65536)");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genThousep(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("@as(i32, 65537)");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genYesexpr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("@as(i32, 52)");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genNoexpr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("@as(i32, 53)");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genCrncystr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("@as(i32, 65538)");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genEra(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("@as(i32, 45)");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genEraDTFmt(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("@as(i32, 46)");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genEraDFmt(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("@as(i32, 47)");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genEraTFmt(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("@as(i32, 48)");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genAltDigits(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("@as(i32, 49)");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}
