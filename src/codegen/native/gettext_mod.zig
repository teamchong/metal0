/// Python gettext module - Internationalization services
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "gettext", genPassthrough }, .{ "ngettext", genNgettext }, .{ "pgettext", genPgettext },
    .{ "npgettext", genNpgettext }, .{ "dgettext", genPgettext }, .{ "dngettext", genNpgettext },
    .{ "bindtextdomain", genBindtextdomain }, .{ "textdomain", genTextdomain }, .{ "install", genUnit },
    .{ "translation", genTranslation }, .{ "find", genNull },
    .{ "GNUTranslations", genTranslationsClass }, .{ "NullTranslations", genTranslationsClass },
});

fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }

fn genPassthrough(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.genExpr(args[0]); } else { try self.emit("\"\""); }
}

fn genNgettext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 3) { try self.emit("blk: { const n = "); try self.genExpr(args[2]); try self.emit("; break :blk if (n == 1) "); try self.genExpr(args[0]); try self.emit(" else "); try self.genExpr(args[1]); try self.emit("; }"); }
    else if (args.len >= 1) { try self.genExpr(args[0]); } else { try self.emit("\"\""); }
}

fn genPgettext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.genExpr(args[1]); } else if (args.len >= 1) { try self.genExpr(args[0]); } else { try self.emit("\"\""); }
}

fn genNpgettext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 4) { try self.emit("blk: { const n = "); try self.genExpr(args[3]); try self.emit("; break :blk if (n == 1) "); try self.genExpr(args[1]); try self.emit(" else "); try self.genExpr(args[2]); try self.emit("; }"); }
    else if (args.len >= 2) { try self.genExpr(args[1]); } else { try self.emit("\"\""); }
}

fn genBindtextdomain(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.genExpr(args[1]); } else { try self.emit("null"); }
}

fn genTextdomain(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 1) { try self.genExpr(args[0]); } else { try self.emit("\"messages\""); }
}

fn genTranslation(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genConst(self, args, ".{ .gettext = struct { fn f(msg: []const u8) []const u8 { return msg; } }.f, .ngettext = struct { fn f(s: []const u8, p: []const u8, n: i64) []const u8 { return if (n == 1) s else p; } }.f, .info = struct { fn f() []const u8 { return \"\"; } }.f, .charset = struct { fn f() []const u8 { return \"UTF-8\"; } }.f }");
}

fn genTranslationsClass(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genConst(self, args, ".{ .gettext = struct { fn f(msg: []const u8) []const u8 { return msg; } }.f }");
}
