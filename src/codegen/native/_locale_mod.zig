/// Python _locale module - C accelerator for locale (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "setlocale", genSetlocale }, .{ "localeconv", genConst(".{ .decimal_point = \".\", .thousands_sep = \"\", .grouping = \"\", .int_curr_symbol = \"\", .currency_symbol = \"\", .mon_decimal_point = \"\", .mon_thousands_sep = \"\", .mon_grouping = \"\", .positive_sign = \"\", .negative_sign = \"\", .int_frac_digits = 127, .frac_digits = 127, .p_cs_precedes = 127, .p_sep_by_space = 127, .n_cs_precedes = 127, .n_sep_by_space = 127, .p_sign_posn = 127, .n_sign_posn = 127 }") },
    .{ "getlocale", genConst(".{ \"C\", null }") },
    .{ "getdefaultlocale", genConst(".{ \"en_US\", \"UTF-8\" }") }, .{ "getpreferredencoding", genConst("\"UTF-8\"") },
    .{ "nl_langinfo", genConst("\"\"") }, .{ "strcoll", genStrcoll }, .{ "strxfrm", genStrxfrm },
    .{ "LC_CTYPE", genConst("@as(i32, 0)") }, .{ "LC_COLLATE", genConst("@as(i32, 1)") }, .{ "LC_TIME", genConst("@as(i32, 2)") },
    .{ "LC_NUMERIC", genConst("@as(i32, 3)") }, .{ "LC_MONETARY", genConst("@as(i32, 4)") }, .{ "LC_MESSAGES", genConst("@as(i32, 5)") }, .{ "LC_ALL", genConst("@as(i32, 6)") },
    .{ "CODESET", genConst("@as(i32, 14)") }, .{ "D_T_FMT", genConst("@as(i32, 1)") }, .{ "D_FMT", genConst("@as(i32, 2)") }, .{ "T_FMT", genConst("@as(i32, 3)") },
    .{ "RADIXCHAR", genConst("@as(i32, 65536)") }, .{ "THOUSEP", genConst("@as(i32, 65537)") }, .{ "YESEXPR", genConst("@as(i32, 52)") }, .{ "NOEXPR", genConst("@as(i32, 53)") },
    .{ "CRNCYSTR", genConst("@as(i32, 65538)") }, .{ "ERA", genConst("@as(i32, 45)") }, .{ "ERA_D_T_FMT", genConst("@as(i32, 46)") },
    .{ "ERA_D_FMT", genConst("@as(i32, 47)") }, .{ "ERA_T_FMT", genConst("@as(i32, 48)") }, .{ "ALT_DIGITS", genConst("@as(i32, 49)") },
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
