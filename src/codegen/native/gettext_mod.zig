/// Python gettext module - Internationalization services
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "gettext", genGettext },
    .{ "ngettext", genNgettext },
    .{ "pgettext", genPgettext },
    .{ "npgettext", genNpgettext },
    .{ "dgettext", genDgettext },
    .{ "dngettext", genDngettext },
    .{ "bindtextdomain", genBindtextdomain },
    .{ "textdomain", genTextdomain },
    .{ "install", genInstall },
    .{ "translation", genTranslation },
    .{ "find", genFind },
    .{ "GNUTranslations", genGNUTranslations },
    .{ "NullTranslations", genNullTranslations },
});

fn genGettext(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
    }
}

fn genNgettext(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
    }
}

fn genPgettext(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 1) {
        try self.genExpr(args[1]);
    } else {
        try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
    }
}

fn genNpgettext(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 1) {
        try self.genExpr(args[1]);
    } else {
        try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
    }
}

fn genDgettext(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 1) {
        try self.genExpr(args[1]);
    } else {
        try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
    }
}

fn genDngettext(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 1) {
        try self.genExpr(args[1]);
    } else {
        try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
    }
}

fn genBindtextdomain(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 1) {
        try self.genExpr(args[1]);
    } else {
        try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
    }
}

fn genTextdomain(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try b.emitValue(builder_mod.ZigValue.string("messages"), builder_mod.EmitConfig.forExpression());
    }
}

fn genInstall(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genTranslation(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .gettext = struct { fn f(msg: []const u8) []const u8 { return msg; } }.f, .ngettext = struct { fn f(s: []const u8, p: []const u8, n: i64) []const u8 { return if (n == 1) s else p; } }.f, .info = struct { fn f() []const u8 { return \"\"; } }.f, .charset = struct { fn f() []const u8 { return \"UTF-8\"; } }.f }"), builder_mod.EmitConfig.forExpression());
}

fn genFind(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
}

fn genGNUTranslations(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .gettext = struct { fn f(msg: []const u8) []const u8 { return msg; } }.f }"), builder_mod.EmitConfig.forExpression());
}

fn genNullTranslations(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .gettext = struct { fn f(msg: []const u8) []const u8 { return msg; } }.f }"), builder_mod.EmitConfig.forExpression());
}
