/// Python zipimport module - Import modules from zip files
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "zipimporter", genZipimporter },
    .{ "ZipImportError", genZipImportError },
});

fn genZipimporter(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len > 0) {
        // With argument: .{ .archive = __v, .prefix = "" }
        try self.emit(".{ .archive = ");
        try self.genExpr(args[0]);
        try self.emit(", .prefix = \"\" }");
    } else {
        // Without argument: default struct
        const b = try self.getBuilder();
        try b.emitValue(builder_mod.ZigValue.raw(".{ .archive = \"\", .prefix = \"\" }"), builder_mod.EmitConfig.forExpression());
    }
}

fn genZipImportError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.ZipImportError"), builder_mod.EmitConfig.forExpression());
}
