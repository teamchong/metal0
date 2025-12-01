/// Python shelve module - Python object persistence
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "open", genOpen },
    .{ "Shelf", genShelf },
    .{ "BsdDbShelf", genBsdDbShelf },
    .{ "DbfilenameShelf", genDbfilenameShelf },
});

/// Generate shelve.open(filename, flag='c', protocol=None, writeback=False) -> Shelf
pub fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("filename: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("data: hashmap_helper.StringHashMap([]const u8) = .{},\n");
    try self.emitIndent();
    try self.emit("writeback: bool = false,\n");
    try self.emitIndent();
    try self.emit("pub fn get(__self: *@This(), key: []const u8) ?[]const u8 { return __self.data.get(key); }\n");
    try self.emitIndent();
    try self.emit("pub fn put(__self: *@This(), key: []const u8, value: []const u8) void { __self.data.put(__self.data.allocator, key, value) catch {}; }\n");
    try self.emitIndent();
    try self.emit("pub fn delete(__self: *@This(), key: []const u8) void { _ = __self.data.remove(key); }\n");
    try self.emitIndent();
    try self.emit("pub fn keys(__self: *@This()) [][]const u8 { _ = __self; return &[_][]const u8{}; }\n");
    try self.emitIndent();
    try self.emit("pub fn values(__self: *@This()) [][]const u8 { _ = __self; return &[_][]const u8{}; }\n");
    try self.emitIndent();
    try self.emit("pub fn items(__self: *@This()) []struct { key: []const u8, value: []const u8 } { _ = __self; return &.{}; }\n");
    try self.emitIndent();
    try self.emit("pub fn __len__(__self: *@This()) usize { return __self.data.count(); }\n");
    try self.emitIndent();
    try self.emit("pub fn __contains__(__self: *@This(), key: []const u8) bool { return __self.data.get(key) != null; }\n");
    try self.emitIndent();
    try self.emit("pub fn sync(__self: *@This()) void { _ = __self; }\n");
    try self.emitIndent();
    try self.emit("pub fn close(__self: *@This()) void { _ = __self; }\n");
    try self.emitIndent();
    try self.emit("pub fn __enter__(__self: *@This()) *@This() { return __self; }\n");
    try self.emitIndent();
    try self.emit("pub fn __exit__(__self: *@This(), _: anytype) void { __self.close(); }\n");
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
