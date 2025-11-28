/// Python locale module - Internationalization services
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate locale.setlocale(category, locale=None) -> str
pub fn genSetlocale(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"C\"");
}

/// Generate locale.getlocale(category=LC_CTYPE) -> (language_code, encoding)
pub fn genGetlocale(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(?[]const u8, null), @as(?[]const u8, null) }");
}

/// Generate locale.getdefaultlocale() -> (language_code, encoding) - deprecated
pub fn genGetdefaultlocale(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ \"en_US\", \"UTF-8\" }");
}

/// Generate locale.getpreferredencoding(do_setlocale=True) -> str
pub fn genGetpreferredencoding(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"UTF-8\"");
}

/// Generate locale.getencoding() -> str
pub fn genGetencoding(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"UTF-8\"");
}

/// Generate locale.normalize(localename) -> str
pub fn genNormalize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"C\"");
    }
}

/// Generate locale.resetlocale(category=LC_ALL) -> None
pub fn genResetlocale(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate locale.localeconv() -> dict
pub fn genLocaleconv(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("decimal_point: []const u8 = \".\",\n");
    try self.emitIndent();
    try self.emit("thousands_sep: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("grouping: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("int_curr_symbol: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("currency_symbol: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("mon_decimal_point: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("mon_thousands_sep: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("mon_grouping: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("positive_sign: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("negative_sign: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("int_frac_digits: i64 = 127,\n");
    try self.emitIndent();
    try self.emit("frac_digits: i64 = 127,\n");
    try self.emitIndent();
    try self.emit("p_cs_precedes: i64 = 127,\n");
    try self.emitIndent();
    try self.emit("p_sep_by_space: i64 = 127,\n");
    try self.emitIndent();
    try self.emit("n_cs_precedes: i64 = 127,\n");
    try self.emitIndent();
    try self.emit("n_sep_by_space: i64 = 127,\n");
    try self.emitIndent();
    try self.emit("p_sign_posn: i64 = 127,\n");
    try self.emitIndent();
    try self.emit("n_sign_posn: i64 = 127,\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate locale.strcoll(string1, string2) -> int
pub fn genStrcoll(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("@as(i64, 0)");
        return;
    }
    try self.emit("std.mem.order(u8, ");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(")");
}

/// Generate locale.strxfrm(string) -> str
pub fn genStrxfrm(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"\"");
    }
}

/// Generate locale.format_string(format, val, grouping=False, monetary=False) -> str
pub fn genFormatString(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate locale.currency(val, symbol=True, grouping=False, international=False) -> str
pub fn genCurrency(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate locale.str(val) -> str (deprecated)
pub fn genStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate locale.atof(string) -> float
pub fn genAtof(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(f64, 0.0)");
}

/// Generate locale.atoi(string) -> int
pub fn genAtoi(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

/// Generate locale.delocalize(string) -> str
pub fn genDelocalize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"\"");
    }
}

/// Generate locale.localize(string, grouping=False, monetary=False) -> str
pub fn genLocalize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"\"");
    }
}

/// Generate locale.nl_langinfo(option) -> str
pub fn genNlLanginfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate locale.gettext(message) -> str
pub fn genGettext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"\"");
    }
}

// Locale category constants

/// Generate locale.LC_CTYPE constant
pub fn genLC_CTYPE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

/// Generate locale.LC_COLLATE constant
pub fn genLC_COLLATE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 1)");
}

/// Generate locale.LC_TIME constant
pub fn genLC_TIME(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 2)");
}

/// Generate locale.LC_MONETARY constant
pub fn genLC_MONETARY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 3)");
}

/// Generate locale.LC_MESSAGES constant
pub fn genLC_MESSAGES(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 5)");
}

/// Generate locale.LC_NUMERIC constant
pub fn genLC_NUMERIC(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 4)");
}

/// Generate locale.LC_ALL constant
pub fn genLC_ALL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 6)");
}

/// Generate locale.Error exception
pub fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"locale.Error\"");
}
