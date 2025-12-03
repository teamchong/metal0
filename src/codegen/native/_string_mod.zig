/// Python _string module - Low-level string formatting (internal)
/// Ported from CPython's Objects/stringlib/unicode_format.h
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "formatter_field_name_split", h.wrap("runtime._string.formatterFieldNameSplit(__global_allocator, ", ")", "runtime._string.FieldNameSplitResult{ .first = \"\", .rest = &[_]runtime._string.FieldAccessor{} }") },
    // Note: formatterParser can return error.TypeError for non-string inputs
    // Don't catch here - let errors propagate so assertRaises can detect them
    .{ "formatter_parser", h.wrap("(runtime._string.formatterParser(__global_allocator, ", "))", "&[_]runtime._string.FormatterResult{}") },
});
