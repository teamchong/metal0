/// Python _string module - Low-level string formatting (internal)
/// Ported from CPython's Objects/stringlib/unicode_format.h
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "formatter_field_name_split", h.wrap("runtime._string.formatterFieldNameSplit(__global_allocator, ", ")", "runtime._string.FieldNameSplitResult{ .first = \"\", .rest = &[_]runtime._string.FieldAccessor{} }") },
    .{ "formatter_parser", h.wrap("(runtime._string.formatterParser(__global_allocator, ", ") catch &[_]runtime._string.FormatterResult{})", "&[_]runtime._string.FormatterResult{}") },
});
