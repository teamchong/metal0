/// Python cgi module - CGI utilities
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "parse", genParse },
    .{ "parse_qs", genParseQs },
    .{ "parse_multipart", genParseMultipart },
    .{ "parse_qsl", genParseQsl },
    .{ "parse_header", genParseHeader },
    .{ "test", genTest },
    .{ "print_environ", genPrintEnviron },
    .{ "print_form", genPrintForm },
    .{ "print_directory", genPrintDirectory },
    .{ "print_environ_usage", genPrintEnvironUsage },
    .{ "escape", genEscape },
    .{ "FieldStorage", genFieldStorage },
    .{ "MiniFieldStorage", genMiniFieldStorage },
    .{ "maxlen", genMaxlen },
});

fn genParse(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genParseQs(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genParseMultipart(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genParseQsl(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_].{ []const u8, []const u8 }{}"), builder_mod.EmitConfig.forExpression());
}

fn genParseHeader(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ \"\", .{} }"), builder_mod.EmitConfig.forExpression());
}

fn genTest(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genPrintEnviron(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genPrintForm(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genPrintDirectory(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genPrintEnvironUsage(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genEscape(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
    }
}

fn genFieldStorage(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = @as(?[]const u8, null), .filename = @as(?[]const u8, null), .value = @as(?[]const u8, null), .file = @as(?*anyopaque, null), .type = \"text/plain\", .type_options = .{}, .disposition = @as(?[]const u8, null), .disposition_options = .{}, .headers = .{}, .list = @as(?*anyopaque, null) }"), builder_mod.EmitConfig.forExpression());
}

fn genMiniFieldStorage(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = @as(?[]const u8, null), .value = @as(?[]const u8, null) }"), builder_mod.EmitConfig.forExpression());
}

fn genMaxlen(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0)"), builder_mod.EmitConfig.forExpression());
}
