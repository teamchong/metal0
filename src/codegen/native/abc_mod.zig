/// Python abc module - Abstract Base Classes
const std = @import("std");
const h = @import("mod_helper.zig");

const genAbstractmethod = h.pass("struct { _is_abstract: bool = true }{}");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "ABC", h.c("struct { _is_abc: bool = true }{}") }, .{ "ABCMeta", h.c("\"ABCMeta\"") },
    .{ "abstractmethod", genAbstractmethod }, .{ "abstractclassmethod", genAbstractmethod },
    .{ "abstractstaticmethod", genAbstractmethod }, .{ "abstractproperty", genAbstractmethod },
    .{ "get_cache_token", h.I64(0) }, .{ "update_abstractmethods", h.pass("void{}") },
});
