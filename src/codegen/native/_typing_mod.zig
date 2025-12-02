/// Python _typing module - Internal typing support (C accelerator)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "_idfunc", h.pass("null") },
    .{ "TypeVar", h.c(".{ .__name__ = \"\", .__bound__ = null, .__constraints__ = &[_]type{}, .__covariant__ = false, .__contravariant__ = false }") },
    .{ "ParamSpec", h.c(".{ .__name__ = \"\" }") }, .{ "TypeVarTuple", h.c(".{ .__name__ = \"\" }") },
    .{ "ParamSpecArgs", h.c(".{ .__origin__ = null }") }, .{ "ParamSpecKwargs", h.c(".{ .__origin__ = null }") },
    .{ "Generic", h.c(".{}") },
});
