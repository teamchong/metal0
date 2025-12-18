/// Python _string module - Low-level string formatting (internal)
/// Ported from CPython's Objects/stringlib/unicode_format.h
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "formatter_field_name_split", genFormatterFieldNameSplit },
    .{ "formatter_parser", genFormatterParser },
});

fn genFormatterFieldNameSplit(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.emit("runtime._string.formatterFieldNameSplit(__global_allocator, ");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("runtime._string.FieldNameSplitResult{ .first = \"\", .rest = &[_]runtime._string.FieldAccessor{} }"), builder_mod.EmitConfig.forExpression());
    }
}

fn genFormatterParser(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.emit("(runtime._string.formatterParser(__global_allocator, ");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("&[_]runtime._string.FormatterResult{}"), builder_mod.EmitConfig.forExpression());
    }
}
