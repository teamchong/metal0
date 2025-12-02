/// Python locale module - Internationalization services
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "setlocale", genSetlocale }, .{ "getlocale", genGetlocale }, .{ "getdefaultlocale", genGetdefaultlocale },
    .{ "getpreferredencoding", genUTF8 }, .{ "getencoding", genUTF8 }, .{ "normalize", genNormalize },
    .{ "resetlocale", genUnit }, .{ "localeconv", genLocaleconv }, .{ "strcoll", genStrcoll }, .{ "strxfrm", genStrxfrm },
    .{ "format_string", genEmptyStr }, .{ "currency", genEmptyStr }, .{ "str", genEmptyStr },
    .{ "atof", genF64_0 }, .{ "atoi", genI64_0 }, .{ "delocalize", genDelocalize }, .{ "localize", genDelocalize },
    .{ "nl_langinfo", genEmptyStr }, .{ "gettext", genGettext },
    .{ "LC_CTYPE", genI64_0 }, .{ "LC_COLLATE", genI64_1 }, .{ "LC_TIME", genI64_2 },
    .{ "LC_MONETARY", genI64_3 }, .{ "LC_NUMERIC", genI64_4 }, .{ "LC_MESSAGES", genI64_5 }, .{ "LC_ALL", genI64_6 },
    .{ "Error", genError },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genUTF8(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"UTF-8\""); }
fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"locale.Error\""); }
fn genLocaleconv(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .decimal_point = \".\", .thousands_sep = \"\", .grouping = \"\", .int_curr_symbol = \"\", .currency_symbol = \"\", .mon_decimal_point = \"\", .mon_thousands_sep = \"\", .mon_grouping = \"\", .positive_sign = \"\", .negative_sign = \"\", .int_frac_digits = 127, .frac_digits = 127, .p_cs_precedes = 127, .p_sep_by_space = 127, .n_cs_precedes = 127, .n_sep_by_space = 127, .p_sign_posn = 127, .n_sign_posn = 127 }"); }
fn genGetlocale(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ @as(?[]const u8, null), @as(?[]const u8, null) }"); }
fn genGetdefaultlocale(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ \"en_US\", \"UTF-8\" }"); }

// Integer constants
fn genI64_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0)"); }
fn genI64_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 1)"); }
fn genI64_2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 2)"); }
fn genI64_3(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 3)"); }
fn genI64_4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 4)"); }
fn genI64_5(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 5)"); }
fn genI64_6(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 6)"); }
fn genF64_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(f64, 0.0)"); }

// Functions with logic
pub fn genSetlocale(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit("\"C\""); }

fn genNormalize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"C\"");
}

fn genStrxfrm(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\"");
}

fn genDelocalize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\"");
}

fn genGettext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\"");
}

fn genStrcoll(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("@as(i64, 0)"); return; }
    try self.emit("std.mem.order(u8, "); try self.genExpr(args[0]);
    try self.emit(", "); try self.genExpr(args[1]); try self.emit(")");
}
