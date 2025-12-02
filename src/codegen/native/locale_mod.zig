/// Python locale module - Internationalization services
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}
fn genI64(comptime n: comptime_int) ModuleHandler { return genConst(std.fmt.comptimePrint("@as(i64, {})", .{n})); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "setlocale", genSetlocale }, .{ "getlocale", genConst(".{ @as(?[]const u8, null), @as(?[]const u8, null) }") },
    .{ "getdefaultlocale", genConst(".{ \"en_US\", \"UTF-8\" }") },
    .{ "getpreferredencoding", genConst("\"UTF-8\"") }, .{ "getencoding", genConst("\"UTF-8\"") }, .{ "normalize", genNormalize },
    .{ "resetlocale", genConst("{}") },
    .{ "localeconv", genConst(".{ .decimal_point = \".\", .thousands_sep = \"\", .grouping = \"\", .int_curr_symbol = \"\", .currency_symbol = \"\", .mon_decimal_point = \"\", .mon_thousands_sep = \"\", .mon_grouping = \"\", .positive_sign = \"\", .negative_sign = \"\", .int_frac_digits = 127, .frac_digits = 127, .p_cs_precedes = 127, .p_sep_by_space = 127, .n_cs_precedes = 127, .n_sep_by_space = 127, .p_sign_posn = 127, .n_sign_posn = 127 }") },
    .{ "strcoll", genStrcoll }, .{ "strxfrm", genStrxfrm },
    .{ "format_string", genConst("\"\"") }, .{ "currency", genConst("\"\"") }, .{ "str", genConst("\"\"") },
    .{ "atof", genConst("@as(f64, 0.0)") }, .{ "atoi", genI64(0) }, .{ "delocalize", genDelocalize }, .{ "localize", genDelocalize },
    .{ "nl_langinfo", genConst("\"\"") }, .{ "gettext", genGettext },
    .{ "LC_CTYPE", genI64(0) }, .{ "LC_COLLATE", genI64(1) }, .{ "LC_TIME", genI64(2) },
    .{ "LC_MONETARY", genI64(3) }, .{ "LC_NUMERIC", genI64(4) }, .{ "LC_MESSAGES", genI64(5) }, .{ "LC_ALL", genI64(6) },
    .{ "Error", genConst("\"locale.Error\"") },
});

pub fn genSetlocale(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit("\"C\""); }
fn genNormalize(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"C\""); }
fn genStrxfrm(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\""); }
fn genDelocalize(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\""); }
fn genGettext(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\""); }
fn genStrcoll(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("@as(i64, 0)"); return; }
    try self.emit("std.mem.order(u8, "); try self.genExpr(args[0]); try self.emit(", "); try self.genExpr(args[1]); try self.emit(")");
}
