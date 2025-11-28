/// Python shelve module - Python object persistence
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate shelve.open(filename, flag='c', protocol=None, writeback=False) -> Shelf
pub fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("filename: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("data: hashmap_helper.StringHashMap([]const u8) = hashmap_helper.StringHashMap([]const u8).init(allocator),\n");
    try self.emitIndent();
    try self.emit("writeback: bool = false,\n");
    try self.emitIndent();
    try self.emit("pub fn get(self: *@This(), key: []const u8) ?[]const u8 { return self.data.get(key); }\n");
    try self.emitIndent();
    try self.emit("pub fn put(self: *@This(), key: []const u8, value: []const u8) void { self.data.put(key, value) catch {}; }\n");
    try self.emitIndent();
    try self.emit("pub fn delete(self: *@This(), key: []const u8) void { _ = self.data.remove(key); }\n");
    try self.emitIndent();
    try self.emit("pub fn keys(self: *@This()) [][]const u8 { _ = self; return &[_][]const u8{}; }\n");
    try self.emitIndent();
    try self.emit("pub fn values(self: *@This()) [][]const u8 { _ = self; return &[_][]const u8{}; }\n");
    try self.emitIndent();
    try self.emit("pub fn items(self: *@This()) []struct { key: []const u8, value: []const u8 } { _ = self; return &.{}; }\n");
    try self.emitIndent();
    try self.emit("pub fn __len__(self: *@This()) usize { return self.data.count(); }\n");
    try self.emitIndent();
    try self.emit("pub fn __contains__(self: *@This(), key: []const u8) bool { return self.data.get(key) != null; }\n");
    try self.emitIndent();
    try self.emit("pub fn sync(self: *@This()) void { _ = self; }\n");
    try self.emitIndent();
    try self.emit("pub fn close(self: *@This()) void { _ = self; }\n");
    try self.emitIndent();
    try self.emit("pub fn __enter__(self: *@This()) *@This() { return self; }\n");
    try self.emitIndent();
    try self.emit("pub fn __exit__(self: *@This(), _: anytype) void { self.close(); }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate shelve.Shelf class
pub fn genShelf(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genOpen(self, args);
}

/// Generate shelve.BsdDbShelf class
pub fn genBsdDbShelf(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genOpen(self, args);
}

/// Generate shelve.DbfilenameShelf class
pub fn genDbfilenameShelf(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genOpen(self, args);
}
