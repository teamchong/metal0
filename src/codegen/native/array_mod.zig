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
    try self.emit("pub fn append(__self: *@This(), x: i64) void { __self.items.append(__global_allocator, x) catch {}; }\n");
    try self.emitIndent();
    try self.emit("pub fn extend(__self: *@This(), iterable: anytype) void { for (iterable) |x| __self.append(x); }\n");
    try self.emitIndent();
    try self.emit("pub fn insert(__self: *@This(), i: usize, x: i64) void { __self.items.insert(__global_allocator, i, x) catch {}; }\n");
    try self.emitIndent();
    try self.emit("pub fn remove(__self: *@This(), x: i64) void { for (__self.items.items, 0..) |v, i| { if (v == x) { _ = __self.items.orderedRemove(i); return; } } }\n");
    try self.emitIndent();
    try self.emit("pub fn pop(__self: *@This()) i64 { return __self.items.pop(); }\n");
    try self.emitIndent();
    try self.emit("pub fn index(__self: *@This(), x: i64) ?usize { for (__self.items.items, 0..) |v, i| { if (v == x) return i; } return null; }\n");
    try self.emitIndent();
    try self.emit("pub fn count(__self: *@This(), x: i64) usize { var c: usize = 0; for (__self.items.items) |v| { if (v == x) c += 1; } return c; }\n");
    try self.emitIndent();
    try self.emit("pub fn reverse(__self: *@This()) void { std.mem.reverse(i64, __self.items.items); }\n");
    try self.emitIndent();
    try self.emit("pub fn tobytes(__self: *@This()) []const u8 { return std.mem.sliceAsBytes(__self.items.items); }\n");
    try self.emitIndent();
    try self.emit("pub fn tolist(__self: *@This()) []i64 { return __self.items.items; }\n");
    try self.emitIndent();
    try self.emit("pub fn frombytes(__self: *@This(), s: []const u8) void { _ = s; }\n");
    try self.emitIndent();
    try self.emit("pub fn fromlist(__self: *@This(), list: []i64) void { for (list) |x| __self.append(x); }\n");
    try self.emitIndent();
    try self.emit("pub fn buffer_info(__self: *@This()) struct { ptr: usize, len: usize } { return .{ .ptr = @intFromPtr(__self.items.items.ptr), .len = __self.items.items.len }; }\n");
    try self.emitIndent();
    try self.emit("pub fn byteswap(__self: *@This()) void { }\n");
    try self.emitIndent();
    try self.emit("pub fn __len__(__self: *@This()) usize { return __self.items.items.len; }\n");
    try self.emitIndent();
    try self.emit("pub fn __getitem__(__self: *@This(), i: usize) i64 { return __self.items.items[i]; }\n");
    try self.emitIndent();
    try self.emit("pub fn __setitem__(__self: *@This(), i: usize, v: i64) void { __self.items.items[i] = v; }\n");
    try self.emitIndent();
    try self.emit("pub fn itemsize(__self: *@This()) usize { return @sizeOf(i64); }\n");
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
