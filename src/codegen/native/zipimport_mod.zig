/// Python zipimport module - Import modules from zip files
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "zipimporter", genZipimporter },
    .{ "ZipImportError", h.err("ZipImportError") },
});

/// Generate zipimport.zipimporter(archivepath)
pub fn genZipimporter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .archive = path, .prefix = \"\" }; }");
    } else {
        try self.emit(".{ .archive = \"\", .prefix = \"\" }");
    }
}
