/// Python zipimport module - Import modules from zip files
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

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

// ============================================================================
// Exception
// ============================================================================

pub fn genZipImportError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.ZipImportError");
}
