/// Python urllib.error module - URL error exceptions
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "URLError", genURLError },
    .{ "HTTPError", genHTTPError },
    .{ "ContentTooShortError", genContentTooShortError },
});

fn genURLError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.URLError"), builder_mod.EmitConfig.forExpression());
}

fn genHTTPError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.HTTPError"), builder_mod.EmitConfig.forExpression());
}

fn genContentTooShortError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.ContentTooShortError"), builder_mod.EmitConfig.forExpression());
}

