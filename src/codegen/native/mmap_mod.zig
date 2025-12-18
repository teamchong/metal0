/// Python mmap module - Memory-mapped file support
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "mmap", genMmap },
    .{ "ACCESS_READ", genAccessRead },
    .{ "ACCESS_WRITE", genAccessWrite },
    .{ "ACCESS_COPY", genAccessCopy },
    .{ "ACCESS_DEFAULT", genAccessDefault },
    .{ "MAP_SHARED", genMapShared },
    .{ "MAP_PRIVATE", genMapPrivate },
    .{ "MAP_ANONYMOUS", genMapAnonymous },
    .{ "PROT_READ", genProtRead },
    .{ "PROT_WRITE", genProtWrite },
    .{ "PROT_EXEC", genProtExec },
    .{ "PAGESIZE", genPagesize },
    .{ "ALLOCATIONGRANULARITY", genAllocationGranularity },
    .{ "MADV_NORMAL", genMadvNormal },
    .{ "MADV_RANDOM", genMadvRandom },
    .{ "MADV_SEQUENTIAL", genMadvSequential },
    .{ "MADV_WILLNEED", genMadvWillneed },
    .{ "MADV_DONTNEED", genMadvDontneed },
});

fn genMmap(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("struct { _data: []u8 = &[_]u8{}, _pos: usize = 0, _closed: bool = false, pub fn close(__self: *@This()) void { __self._closed = true; } pub fn closed(__self: *@This()) bool { return __self._closed; } pub fn find(__self: *@This(), sub: []const u8, start: ?usize, end: ?usize) isize { const s = start orelse 0; const e = end orelse __self._data.len; if (std.mem.indexOf(u8, __self._data[s..e], sub)) |idx| return @intCast(s + idx); return -1; } pub fn rfind(__self: *@This(), sub: []const u8, start: ?usize, end: ?usize) isize { const s = start orelse 0; const e = end orelse __self._data.len; if (std.mem.lastIndexOf(u8, __self._data[s..e], sub)) |idx| return @intCast(s + idx); return -1; } pub fn flush(__self: *@This(), offset: ?usize, size: ?usize) void { _ = __self; _ = offset; _ = size; } pub fn move(__self: *@This(), dest: usize, src: usize, count: usize) void { std.mem.copyBackwards(u8, __self._data[dest..dest+count], __self._data[src..src+count]); } pub fn read(__self: *@This(), n: ?usize) []const u8 { const count = n orelse (__self._data.len - __self._pos); const e = @min(__self._pos + count, __self._data.len); const result = __self._data[__self._pos..e]; __self._pos = e; return result; } pub fn read_byte(__self: *@This()) ?u8 { if (__self._pos >= __self._data.len) return null; const b = __self._data[__self._pos]; __self._pos += 1; return b; } pub fn readline(__self: *@This()) []const u8 { const start = __self._pos; while (__self._pos < __self._data.len and __self._data[__self._pos] != '\\n') __self._pos += 1; if (__self._pos < __self._data.len) __self._pos += 1; return __self._data[start..__self._pos]; } pub fn resize(__self: *@This(), newsize: usize) void { _ = __self; _ = newsize; } pub fn seek(__self: *@This(), pos: usize, whence: ?i32) void { const w = whence orelse 0; if (w == 0) __self._pos = pos else if (w == 1) __self._pos = @min(__self._pos + pos, __self._data.len) else if (w == 2) __self._pos = if (pos > __self._data.len) 0 else __self._data.len - pos; } pub fn size(__self: *@This()) usize { return __self._data.len; } pub fn tell(__self: *@This()) usize { return __self._pos; } pub fn write(__self: *@This(), data: []const u8) usize { const count = @min(data.len, __self._data.len - __self._pos); @memcpy(__self._data[__self._pos..__self._pos+count], data[0..count]); __self._pos += count; return count; } pub fn write_byte(__self: *@This(), byte: u8) void { if (__self._pos < __self._data.len) { __self._data[__self._pos] = byte; __self._pos += 1; } } }{}"), builder_mod.EmitConfig.forExpression());
}

fn genAccessRead(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

fn genAccessWrite(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2), builder_mod.EmitConfig.forExpression());
}

fn genAccessCopy(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(3), builder_mod.EmitConfig.forExpression());
}

fn genAccessDefault(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genMapShared(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0x01), builder_mod.EmitConfig.forExpression());
}

fn genMapPrivate(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0x02), builder_mod.EmitConfig.forExpression());
}

fn genMapAnonymous(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0x20), builder_mod.EmitConfig.forExpression());
}

fn genProtRead(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0x01), builder_mod.EmitConfig.forExpression());
}

fn genProtWrite(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0x02), builder_mod.EmitConfig.forExpression());
}

fn genProtExec(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0x04), builder_mod.EmitConfig.forExpression());
}

fn genPagesize(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(usize, 4096)"), builder_mod.EmitConfig.forExpression());
}

fn genAllocationGranularity(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(usize, 4096)"), builder_mod.EmitConfig.forExpression());
}

fn genMadvNormal(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genMadvRandom(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

fn genMadvSequential(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2), builder_mod.EmitConfig.forExpression());
}

fn genMadvWillneed(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(3), builder_mod.EmitConfig.forExpression());
}

fn genMadvDontneed(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(4), builder_mod.EmitConfig.forExpression());
}
