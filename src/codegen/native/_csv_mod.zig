/// Python _csv module - C accelerator for csv (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "reader", genRW },
    .{ "writer", genRW },
    .{ "register_dialect", genRegisterDialect },
    .{ "unregister_dialect", genUnregisterDialect },
    .{ "get_dialect", genGetDialect },
    .{ "list_dialects", genListDialects },
    .{ "field_size_limit", genFieldSizeLimit },
    .{ "QUOTE_ALL", genQuoteAll },
    .{ "QUOTE_MINIMAL", genQuoteMinimal },
    .{ "QUOTE_NONNUMERIC", genQuoteNonnumeric },
    .{ "QUOTE_NONE", genQuoteNone },
    .{ "Error", genError },
});

fn genRW(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    const default = ".{ .file = null, .dialect = \"excel\" }";
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.raw(default), builder_mod.EmitConfig.forExpression());
        return;
    }
    const label = try self.emitInlineBlockStart("csv");
    try self.emit("const __v = ");
    try self.genExpr(args[0]);
    try self.emitFmt("; break :{s} .{{ .file = __v, .dialect = \"excel\" }}; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genRegisterDialect(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genUnregisterDialect(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetDialect(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .delimiter = ',', .quotechar = '\"', .escapechar = null, .doublequote = true, .skipinitialspace = false, .lineterminator = \"\\r\\n\", .quoting = 0, .strict = false }"), builder_mod.EmitConfig.forExpression());
}

fn genListDialects(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{ \"excel\", \"excel-tab\", \"unix\" }"), builder_mod.EmitConfig.forExpression());
}

fn genFieldSizeLimit(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 131072)"), builder_mod.EmitConfig.forExpression());
    }
}

fn genQuoteAll(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

fn genQuoteMinimal(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genQuoteNonnumeric(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2), builder_mod.EmitConfig.forExpression());
}

fn genQuoteNone(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(3), builder_mod.EmitConfig.forExpression());
}

fn genError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.CsvError"), builder_mod.EmitConfig.forExpression());
}
