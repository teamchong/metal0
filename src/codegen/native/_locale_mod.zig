/// Python _locale module - C accelerator for locale (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genUTF8(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"UTF-8\""); }
fn genLocaleconv(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .decimal_point = \".\", .thousands_sep = \"\", .grouping = \"\", .int_curr_symbol = \"\", .currency_symbol = \"\", .mon_decimal_point = \"\", .mon_thousands_sep = \"\", .mon_grouping = \"\", .positive_sign = \"\", .negative_sign = \"\", .int_frac_digits = 127, .frac_digits = 127, .p_cs_precedes = 127, .p_sep_by_space = 127, .n_cs_precedes = 127, .n_sep_by_space = 127, .p_sign_posn = 127, .n_sign_posn = 127 }"); }
fn genGetlocale(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ \"C\", null }"); }
fn genGetdefaultlocale(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ \"en_US\", \"UTF-8\" }"); }
fn genI32(comptime n: comptime_int) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, std.fmt.comptimePrint("@as(i32, {})", .{n})); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "setlocale", genSetlocale }, .{ "localeconv", genLocaleconv }, .{ "getlocale", genGetlocale },
    .{ "getdefaultlocale", genGetdefaultlocale }, .{ "getpreferredencoding", genUTF8 },
    .{ "nl_langinfo", genEmptyStr }, .{ "strcoll", genStrcoll }, .{ "strxfrm", genStrxfrm },
    .{ "LC_CTYPE", genI32(0) }, .{ "LC_COLLATE", genI32(1) }, .{ "LC_TIME", genI32(2) },
    .{ "LC_NUMERIC", genI32(3) }, .{ "LC_MONETARY", genI32(4) }, .{ "LC_MESSAGES", genI32(5) }, .{ "LC_ALL", genI32(6) },
    .{ "CODESET", genI32(14) }, .{ "D_T_FMT", genI32(1) }, .{ "D_FMT", genI32(2) }, .{ "T_FMT", genI32(3) },
    .{ "RADIXCHAR", genI32(65536) }, .{ "THOUSEP", genI32(65537) }, .{ "YESEXPR", genI32(52) }, .{ "NOEXPR", genI32(53) },
    .{ "CRNCYSTR", genI32(65538) }, .{ "ERA", genI32(45) }, .{ "ERA_D_T_FMT", genI32(46) },
    .{ "ERA_D_FMT", genI32(47) }, .{ "ERA_T_FMT", genI32(48) }, .{ "ALT_DIGITS", genI32(49) },
});

fn genSetlocale(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) try self.genExpr(args[1]) else try self.emit("\"C\"");
}
fn genStrcoll(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("std.mem.order(u8, "); try self.genExpr(args[0]); try self.emit(", "); try self.genExpr(args[1]); try self.emit(")"); }
    else try self.emit("std.math.Order.eq");
}
fn genStrxfrm(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\"");
}
