/// Python typing module - Type hints (no-ops for AOT compilation)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Optional", h.wrap("?", "", "?*runtime.PyObject") }, .{ "List", h.c("std.ArrayList(*runtime.PyObject)") },
    .{ "Dict", h.c("hashmap_helper.StringHashMap(*runtime.PyObject)") },
    .{ "Set", h.c("hashmap_helper.StringHashMap(void)") }, .{ "Tuple", h.c("struct {}") },
    .{ "Union", h.c("*runtime.PyObject") }, .{ "Any", h.c("*runtime.PyObject") },
    .{ "Callable", h.c("*const fn () void") }, .{ "TypeVar", h.discard("void{}") },
    .{ "Generic", h.c("void{}") }, .{ "cast", h.passN(1, "void{}") },
    .{ "get_type_hints", h.c("hashmap_helper.StringHashMap(*runtime.PyObject).init(__global_allocator)") },
});
