/// Python _collections_abc module - Abstract Base Classes for containers
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genTypeMarker(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit("@TypeOf(.{})"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
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
