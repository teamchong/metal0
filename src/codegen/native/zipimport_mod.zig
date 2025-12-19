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
    const b = try self.getBuilder();
    if (args.len > 0) {
        // With argument: .{ .archive = __v, .prefix = "" }
        try b.write(".{ .archive = ");
        const output1 = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output1);
        try self.genExpr(args[0]);
        {
            const b2 = try self.getBuilder();
            try b2.write(", .prefix = \"\" }");
            const output2 = b2.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output2);
        }
    } else {
        // Without argument: default struct
        try b.write(".{ .archive = \"\", .prefix = \"\" }");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

fn genZipImportError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("error.ZipImportError");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}
