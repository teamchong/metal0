/// Python _collections_abc module - Abstract Base Classes for containers
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

fn genTypeMarker(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@TypeOf(.{})"), builder_mod.EmitConfig.forExpression());
}

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
