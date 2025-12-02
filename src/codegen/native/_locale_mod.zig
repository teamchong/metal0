/// Python _locale module - C accelerator for locale (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "setlocale", genSetlocale }, .{ "localeconv", genLocaleconv }, .{ "getlocale", genGetlocale },
    .{ "getdefaultlocale", genGetdefaultlocale }, .{ "getpreferredencoding", genUTF8 },
    .{ "nl_langinfo", genEmptyStr }, .{ "strcoll", genStrcoll }, .{ "strxfrm", genStrxfrm },
    .{ "LC_CTYPE", genI32_0 }, .{ "LC_COLLATE", genI32_1 }, .{ "LC_TIME", genI32_2 },
    .{ "LC_NUMERIC", genI32_3 }, .{ "LC_MONETARY", genI32_4 }, .{ "LC_MESSAGES", genI32_5 }, .{ "LC_ALL", genI32_6 },
    .{ "CODESET", genI32_14 }, .{ "D_T_FMT", genI32_1 }, .{ "D_FMT", genI32_2 }, .{ "T_FMT", genI32_3 },
    .{ "RADIXCHAR", genI32_65536 }, .{ "THOUSEP", genI32_65537 }, .{ "YESEXPR", genI32_52 }, .{ "NOEXPR", genI32_53 },
    .{ "CRNCYSTR", genI32_65538 }, .{ "ERA", genI32_45 }, .{ "ERA_D_T_FMT", genI32_46 },
    .{ "ERA_D_FMT", genI32_47 }, .{ "ERA_T_FMT", genI32_48 }, .{ "ALT_DIGITS", genI32_49 },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genUTF8(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"UTF-8\""); }
fn genLocaleconv(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .decimal_point = \".\", .thousands_sep = \"\", .grouping = \"\", .int_curr_symbol = \"\", .currency_symbol = \"\", .mon_decimal_point = \"\", .mon_thousands_sep = \"\", .mon_grouping = \"\", .positive_sign = \"\", .negative_sign = \"\", .int_frac_digits = 127, .frac_digits = 127, .p_cs_precedes = 127, .p_sep_by_space = 127, .n_cs_precedes = 127, .n_sep_by_space = 127, .p_sign_posn = 127, .n_sign_posn = 127 }"); }
fn genGetlocale(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ \"C\", null }"); }
fn genGetdefaultlocale(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ \"en_US\", \"UTF-8\" }"); }

// Integer constants
fn genI32_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
fn genI32_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 1)"); }
fn genI32_2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 2)"); }
fn genI32_3(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 3)"); }
fn genI32_4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 4)"); }
fn genI32_5(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 5)"); }
fn genI32_6(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 6)"); }
fn genI32_14(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 14)"); }
fn genI32_45(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 45)"); }
fn genI32_46(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 46)"); }
fn genI32_47(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 47)"); }
fn genI32_48(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 48)"); }
fn genI32_49(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 49)"); }
fn genI32_52(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 52)"); }
fn genI32_53(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 53)"); }
fn genI32_65536(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 65536)"); }
fn genI32_65537(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 65537)"); }
fn genI32_65538(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 65538)"); }

// Functions with logic
fn genSetlocale(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) try self.genExpr(args[1]) else try self.emit("\"C\"");
}

fn genStrcoll(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("std.mem.order(u8, "); try self.genExpr(args[0]);
        try self.emit(", "); try self.genExpr(args[1]); try self.emit(")");
    } else try self.emit("std.math.Order.eq");
}

fn genStrxfrm(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\"");
}
