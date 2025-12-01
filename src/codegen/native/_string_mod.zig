/// Python _string module - Low-level string formatting (internal)
/// Ported from CPython's Objects/stringlib/unicode_format.h
const std = @import("std");
const ast = @import("ast");

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "formatter_field_name_split", genFormatterFieldNameSplit },
    .{ "formatter_parser", genFormatterParser },
});
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _string.formatter_field_name_split(field_name)
/// Returns (first_part, iterator_of_accessors)
pub fn genFormatterFieldNameSplit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("runtime._string.formatterFieldNameSplit(__global_allocator, ");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        try self.emit("runtime._string.FieldNameSplitResult{ .first = \"\", .rest = &[_]runtime._string.FieldAccessor{} }");
    }
}

/// Generate _string.formatter_parser(format_string)
/// Returns an iterator/slice of (literal, field_name, format_spec, conversion) tuples
pub fn genFormatterParser(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        // Use catch to avoid requiring error handling in nested functions
        try self.emit("(runtime._string.formatterParser(__global_allocator, ");
        try self.genExpr(args[0]);
        try self.emit(") catch &[_]runtime._string.FormatterResult{})");
    } else {
        try self.emit("&[_]runtime._string.FormatterResult{}");
    }
}
