/// Python mmap module - Memory-mapped file support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "mmap", genMmap },
    .{ "ACCESS_READ", genACCESS_READ },
    .{ "ACCESS_WRITE", genACCESS_WRITE },
    .{ "ACCESS_COPY", genACCESS_COPY },
    .{ "ACCESS_DEFAULT", genACCESS_DEFAULT },
    .{ "MAP_SHARED", genMAP_SHARED },
    .{ "MAP_PRIVATE", genMAP_PRIVATE },
    .{ "MAP_ANONYMOUS", genMAP_ANONYMOUS },
    .{ "PROT_READ", genPROT_READ },
    .{ "PROT_WRITE", genPROT_WRITE },
    .{ "PROT_EXEC", genPROT_EXEC },
    .{ "PAGESIZE", genPAGESIZE },
    .{ "ALLOCATIONGRANULARITY", genALLOCATIONGRANULARITY },
    .{ "MADV_NORMAL", genMADV_NORMAL },
    .{ "MADV_RANDOM", genMADV_RANDOM },
    .{ "MADV_SEQUENTIAL", genMADV_SEQUENTIAL },
    .{ "MADV_WILLNEED", genMADV_WILLNEED },
    .{ "MADV_DONTNEED", genMADV_DONTNEED },
});

/// Generate mmap.mmap(fileno, length, tagname=None, access=ACCESS_WRITE, offset=0)
pub fn genMmap(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_data: []u8 = &[_]u8{},\n");
    try self.emitIndent();
    try self.emit("_pos: usize = 0,\n");
    try self.emitIndent();
    try self.emit("_closed: bool = false,\n");
    try self.emitIndent();
    try self.emit("pub fn close(__self: *@This()) void { __self._closed = true; }\n");
    try self.emitIndent();
    try self.emit("pub fn closed(__self: *@This()) bool { return __self._closed; }\n");
    try self.emitIndent();
    try self.emit("pub fn find(__self: *@This(), sub: []const u8, start: ?usize, end: ?usize) isize {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const s = start orelse 0;\n");
    try self.emitIndent();
    try self.emit("const e = end orelse __self._data.len;\n");
    try self.emitIndent();
    try self.emit("if (std.mem.indexOf(u8, __self._data[s..e], sub)) |idx| return @intCast(s + idx);\n");
    try self.emitIndent();
    try self.emit("return -1;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn rfind(__self: *@This(), sub: []const u8, start: ?usize, end: ?usize) isize {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const s = start orelse 0;\n");
    try self.emitIndent();
    try self.emit("const e = end orelse __self._data.len;\n");
    try self.emitIndent();
    try self.emit("if (std.mem.lastIndexOf(u8, __self._data[s..e], sub)) |idx| return @intCast(s + idx);\n");
    try self.emitIndent();
    try self.emit("return -1;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn flush(__self: *@This(), offset: ?usize, size: ?usize) void { _ = offset; _ = size; }\n");
    try self.emitIndent();
    try self.emit("pub fn move(__self: *@This(), dest: usize, src: usize, count: usize) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("std.mem.copyBackwards(u8, __self._data[dest..dest+count], __self._data[src..src+count]);\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn read(__self: *@This(), n: ?usize) []const u8 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const count = n orelse (__self._data.len - __self._pos);\n");
    try self.emitIndent();
    try self.emit("const end = @min(__self._pos + count, __self._data.len);\n");
    try self.emitIndent();
    try self.emit("const result = __self._data[__self._pos..end];\n");
    try self.emitIndent();
    try self.emit("__self._pos = end;\n");
    try self.emitIndent();
    try self.emit("return result;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn read_byte(__self: *@This()) ?u8 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (__self._pos >= __self._data.len) return null;\n");
    try self.emitIndent();
    try self.emit("const b = __self._data[__self._pos];\n");
    try self.emitIndent();
    try self.emit("__self._pos += 1;\n");
    try self.emitIndent();
    try self.emit("return b;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn readline(__self: *@This()) []const u8 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const start = __self._pos;\n");
    try self.emitIndent();
    try self.emit("while (__self._pos < __self._data.len and __self._data[__self._pos] != '\\n') __self._pos += 1;\n");
    try self.emitIndent();
    try self.emit("if (__self._pos < __self._data.len) __self._pos += 1;\n");
    try self.emitIndent();
    try self.emit("return __self._data[start..__self._pos];\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn resize(__self: *@This(), newsize: usize) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = self; _ = newsize;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn seek(__self: *@This(), pos: usize, whence: ?i32) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const w = whence orelse 0;\n");
    try self.emitIndent();
    try self.emit("if (w == 0) __self._pos = pos\n");
    try self.emitIndent();
    try self.emit("else if (w == 1) __self._pos = @min(__self._pos + pos, __self._data.len)\n");
    try self.emitIndent();
    try self.emit("else if (w == 2) __self._pos = if (pos > __self._data.len) 0 else __self._data.len - pos;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn size(__self: *@This()) usize { return __self._data.len; }\n");
    try self.emitIndent();
    try self.emit("pub fn tell(__self: *@This()) usize { return __self._pos; }\n");
    try self.emitIndent();
    try self.emit("pub fn write(__self: *@This(), data: []const u8) usize {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const count = @min(data.len, __self._data.len - __self._pos);\n");
    try self.emitIndent();
    try self.emit("@memcpy(__self._data[__self._pos..__self._pos+count], data[0..count]);\n");
    try self.emitIndent();
    try self.emit("__self._pos += count;\n");
    try self.emitIndent();
    try self.emit("return count;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn write_byte(__self: *@This(), byte: u8) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (__self._pos < __self._data.len) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("__self._data[__self._pos] = byte;\n");
    try self.emitIndent();
    try self.emit("__self._pos += 1;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }

// Constants
fn genACCESS_READ(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 1)"); }
fn genACCESS_WRITE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 2)"); }
fn genACCESS_COPY(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 3)"); }
fn genACCESS_DEFAULT(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
fn genMAP_SHARED(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0x01)"); }
fn genMAP_PRIVATE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0x02)"); }
fn genMAP_ANONYMOUS(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0x20)"); }
fn genPROT_READ(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0x01)"); }
fn genPROT_WRITE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0x02)"); }
fn genPROT_EXEC(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0x04)"); }
fn genPAGESIZE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(usize, 4096)"); }
fn genALLOCATIONGRANULARITY(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(usize, 4096)"); }
fn genMADV_NORMAL(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
fn genMADV_RANDOM(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 1)"); }
fn genMADV_SEQUENTIAL(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 2)"); }
fn genMADV_WILLNEED(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 3)"); }
fn genMADV_DONTNEED(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 4)"); }
