/// Python symtable module - Symbol table access
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "symtable", h.c(".{ .name = \"<module>\", .type = \"module\", .lineno = 1, .is_optimized = false, .is_nested = false, .has_children = false, .has_exec = false, .has_import_star = false, .has_varargs = false, .has_varkeywords = false }") },
    .{ "SymbolTable", h.c(".{ .name = \"\", .type = \"module\", .id = 0 }") },
    .{ "Symbol", h.c(".{ .name = \"\", .is_referenced = false, .is_imported = false, .is_parameter = false, .is_global = false, .is_nonlocal = false, .is_declared_global = false, .is_local = false, .is_annotated = false, .is_free = false, .is_assigned = false, .is_namespace = false }") },
    .{ "Function", h.c(".{ .name = \"\", .type = \"function\", .id = 0 }") },
    .{ "Class", h.c(".{ .name = \"\", .type = \"class\", .id = 0 }") },
});
