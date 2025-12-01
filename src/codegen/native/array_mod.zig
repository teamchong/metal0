/// Python array module - Efficient arrays of numeric values
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "array", genArray },
    .{ "typecodes", genTypecodes },
    .{ "ArrayType", genArrayType },
});

/// Generate array.array(typecode, initializer=None) -> array
pub fn genArray(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("typecode: u8 = 'l',\n");
    try self.emitIndent();
    try self.emit("items: std.ArrayList(i64) = .{},\n");
    try self.emitIndent();
    try self.emit("pub fn append(self: *@This(), x: i64) void { self.items.append(__global_allocator, x) catch {}; }\n");
    try self.emitIndent();
    try self.emit("pub fn extend(self: *@This(), iterable: anytype) void { for (iterable) |x| self.append(x); }\n");
    try self.emitIndent();
    try self.emit("pub fn insert(self: *@This(), i: usize, x: i64) void { self.items.insert(__global_allocator, i, x) catch {}; }\n");
    try self.emitIndent();
    try self.emit("pub fn remove(self: *@This(), x: i64) void { for (self.items.items, 0..) |v, i| { if (v == x) { _ = self.items.orderedRemove(i); return; } } }\n");
    try self.emitIndent();
    try self.emit("pub fn pop(self: *@This()) i64 { return self.items.pop(); }\n");
    try self.emitIndent();
    try self.emit("pub fn index(self: *@This(), x: i64) ?usize { for (self.items.items, 0..) |v, i| { if (v == x) return i; } return null; }\n");
    try self.emitIndent();
    try self.emit("pub fn count(self: *@This(), x: i64) usize { var c: usize = 0; for (self.items.items) |v| { if (v == x) c += 1; } return c; }\n");
    try self.emitIndent();
    try self.emit("pub fn reverse(self: *@This()) void { std.mem.reverse(i64, self.items.items); }\n");
    try self.emitIndent();
    try self.emit("pub fn tobytes(self: *@This()) []const u8 { return std.mem.sliceAsBytes(self.items.items); }\n");
    try self.emitIndent();
    try self.emit("pub fn tolist(self: *@This()) []i64 { return self.items.items; }\n");
    try self.emitIndent();
    try self.emit("pub fn frombytes(self: *@This(), s: []const u8) void { _ = self; _ = s; }\n");
    try self.emitIndent();
    try self.emit("pub fn fromlist(self: *@This(), list: []i64) void { for (list) |x| self.append(x); }\n");
    try self.emitIndent();
    try self.emit("pub fn buffer_info(self: *@This()) struct { ptr: usize, len: usize } { return .{ .ptr = @intFromPtr(self.items.items.ptr), .len = self.items.items.len }; }\n");
    try self.emitIndent();
    try self.emit("pub fn byteswap(self: *@This()) void { _ = self; }\n");
    try self.emitIndent();
    try self.emit("pub fn __len__(self: *@This()) usize { return self.items.items.len; }\n");
    try self.emitIndent();
    try self.emit("pub fn __getitem__(self: *@This(), i: usize) i64 { return self.items.items[i]; }\n");
    try self.emitIndent();
    try self.emit("pub fn __setitem__(self: *@This(), i: usize, v: i64) void { self.items.items[i] = v; }\n");
    try self.emitIndent();
    try self.emit("pub fn itemsize(self: *@This()) usize { _ = self; return @sizeOf(i64); }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate array.typecodes constant
pub fn genTypecodes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"bBuhHiIlLqQfd\"");
}

/// Generate array.ArrayType (alias for array)
pub fn genArrayType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genArray(self, args);
}
