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
        try b.write("runtime._string.formatterFieldNameSplit(__global_allocator, ");
        const output1 = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output1);
        try self.genExpr(args[0]);
        {
            const b2 = try self.getBuilder();
            try b2.write(")");
            const output2 = b2.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output2);
        }
    } else {
        try b.write("runtime._string.FieldNameSplitResult{ .first = \"\", .rest = &[_]runtime._string.FieldAccessor{} }");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

fn genFormatterParser(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try b.write("(runtime._string.formatterParser(__global_allocator, ");
        const output1 = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output1);
        try self.genExpr(args[0]);
        {
            const b2 = try self.getBuilder();
            try b2.write("))");
            const output2 = b2.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output2);
        }
    } else {
        try b.write("&[_]runtime._string.FormatterResult{}");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}
