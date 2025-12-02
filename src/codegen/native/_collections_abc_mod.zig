/// Python _collections_abc module - Abstract Base Classes for containers
const std = @import("std");
const h = @import("mod_helper.zig");

const genTypeMarker = h.c("@TypeOf(.{})");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Awaitable", genTypeMarker }, .{ "Coroutine", genTypeMarker }, .{ "AsyncIterable", genTypeMarker },
    .{ "AsyncIterator", genTypeMarker }, .{ "AsyncGenerator", genTypeMarker }, .{ "Hashable", genTypeMarker },
    .{ "Iterable", genTypeMarker }, .{ "Iterator", genTypeMarker }, .{ "Generator", genTypeMarker },
    .{ "Reversible", genTypeMarker }, .{ "Container", genTypeMarker }, .{ "Collection", genTypeMarker },
    .{ "Callable", genTypeMarker }, .{ "Set", genTypeMarker }, .{ "MutableSet", genTypeMarker },
    .{ "Mapping", genTypeMarker }, .{ "MutableMapping", genTypeMarker }, .{ "Sequence", genTypeMarker },
    .{ "MutableSequence", genTypeMarker }, .{ "ByteString", genTypeMarker }, .{ "MappingView", genTypeMarker },
    .{ "KeysView", genTypeMarker }, .{ "ItemsView", genTypeMarker }, .{ "ValuesView", genTypeMarker },
    .{ "Sized", genTypeMarker }, .{ "Buffer", genTypeMarker },
});
