/// Python shelve module - Python object persistence
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "open", genOpen },
    .{ "Shelf", genShelf },
    .{ "BsdDbShelf", genBsdDbShelf },
    .{ "DbfilenameShelf", genDbfilenameShelf },
});

const ShelfStruct = "struct { filename: []const u8 = \"\", data: hashmap_helper.StringHashMap([]const u8) = .{}, writeback: bool = false, pub fn get(__self: *@This(), key: []const u8) ?[]const u8 { return __self.data.get(key); } pub fn put(__self: *@This(), key: []const u8, value: []const u8) void { __self.data.put(__self.data.allocator, key, value) catch unreachable; } pub fn delete(__self: *@This(), key: []const u8) void { _ = __self.data.remove(key); } pub fn keys(__self: *@This()) [][]const u8 { _ = __self; return &[_][]const u8{}; } pub fn values(__self: *@This()) [][]const u8 { _ = __self; return &[_][]const u8{}; } pub fn items(__self: *@This()) []struct { key: []const u8, value: []const u8 } { _ = __self; return &.{}; } pub fn __len__(__self: *@This()) usize { return __self.data.count(); } pub fn __contains__(__self: *@This(), key: []const u8) bool { return __self.data.get(key) != null; } pub fn sync(__self: *@This()) void { _ = __self; } pub fn close(__self: *@This()) void { _ = __self; } pub fn __enter__(__self: *@This()) *@This() { return __self; } pub fn __exit__(__self: *@This(), _: anytype) void { __self.close(); } }{}";

fn genOpen(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(ShelfStruct), builder_mod.EmitConfig.forExpression());
}

fn genShelf(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(ShelfStruct), builder_mod.EmitConfig.forExpression());
}

fn genBsdDbShelf(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(ShelfStruct), builder_mod.EmitConfig.forExpression());
}

fn genDbfilenameShelf(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(ShelfStruct), builder_mod.EmitConfig.forExpression());
}
