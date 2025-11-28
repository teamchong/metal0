/// Python mmap module - Memory-mapped file support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

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
    try self.emit("pub fn close(self: *@This()) void { self._closed = true; }\n");
    try self.emitIndent();
    try self.emit("pub fn closed(self: *@This()) bool { return self._closed; }\n");
    try self.emitIndent();
    try self.emit("pub fn find(self: *@This(), sub: []const u8, start: ?usize, end: ?usize) isize {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const s = start orelse 0;\n");
    try self.emitIndent();
    try self.emit("const e = end orelse self._data.len;\n");
    try self.emitIndent();
    try self.emit("if (std.mem.indexOf(u8, self._data[s..e], sub)) |idx| return @intCast(s + idx);\n");
    try self.emitIndent();
    try self.emit("return -1;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn rfind(self: *@This(), sub: []const u8, start: ?usize, end: ?usize) isize {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const s = start orelse 0;\n");
    try self.emitIndent();
    try self.emit("const e = end orelse self._data.len;\n");
    try self.emitIndent();
    try self.emit("if (std.mem.lastIndexOf(u8, self._data[s..e], sub)) |idx| return @intCast(s + idx);\n");
    try self.emitIndent();
    try self.emit("return -1;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn flush(self: *@This(), offset: ?usize, size: ?usize) void { _ = self; _ = offset; _ = size; }\n");
    try self.emitIndent();
    try self.emit("pub fn move(self: *@This(), dest: usize, src: usize, count: usize) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("std.mem.copyBackwards(u8, self._data[dest..dest+count], self._data[src..src+count]);\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn read(self: *@This(), n: ?usize) []const u8 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const count = n orelse (self._data.len - self._pos);\n");
    try self.emitIndent();
    try self.emit("const end = @min(self._pos + count, self._data.len);\n");
    try self.emitIndent();
    try self.emit("const result = self._data[self._pos..end];\n");
    try self.emitIndent();
    try self.emit("self._pos = end;\n");
    try self.emitIndent();
    try self.emit("return result;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn read_byte(self: *@This()) ?u8 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (self._pos >= self._data.len) return null;\n");
    try self.emitIndent();
    try self.emit("const b = self._data[self._pos];\n");
    try self.emitIndent();
    try self.emit("self._pos += 1;\n");
    try self.emitIndent();
    try self.emit("return b;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn readline(self: *@This()) []const u8 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const start = self._pos;\n");
    try self.emitIndent();
    try self.emit("while (self._pos < self._data.len and self._data[self._pos] != '\\n') self._pos += 1;\n");
    try self.emitIndent();
    try self.emit("if (self._pos < self._data.len) self._pos += 1;\n");
    try self.emitIndent();
    try self.emit("return self._data[start..self._pos];\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn resize(self: *@This(), newsize: usize) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = self; _ = newsize;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn seek(self: *@This(), pos: usize, whence: ?i32) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const w = whence orelse 0;\n");
    try self.emitIndent();
    try self.emit("if (w == 0) self._pos = pos\n");
    try self.emitIndent();
    try self.emit("else if (w == 1) self._pos = @min(self._pos + pos, self._data.len)\n");
    try self.emitIndent();
    try self.emit("else if (w == 2) self._pos = if (pos > self._data.len) 0 else self._data.len - pos;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn size(self: *@This()) usize { return self._data.len; }\n");
    try self.emitIndent();
    try self.emit("pub fn tell(self: *@This()) usize { return self._pos; }\n");
    try self.emitIndent();
    try self.emit("pub fn write(self: *@This(), data: []const u8) usize {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const count = @min(data.len, self._data.len - self._pos);\n");
    try self.emitIndent();
    try self.emit("@memcpy(self._data[self._pos..self._pos+count], data[0..count]);\n");
    try self.emitIndent();
    try self.emit("self._pos += count;\n");
    try self.emitIndent();
    try self.emit("return count;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn write_byte(self: *@This(), byte: u8) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (self._pos < self._data.len) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("self._data[self._pos] = byte;\n");
    try self.emitIndent();
    try self.emit("self._pos += 1;\n");
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

// ============================================================================
// Constants
// ============================================================================

/// Generate mmap.ACCESS_READ
pub fn genACCESS_READ(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

/// Generate mmap.ACCESS_WRITE
pub fn genACCESS_WRITE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

/// Generate mmap.ACCESS_COPY
pub fn genACCESS_COPY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 3)");
}

/// Generate mmap.ACCESS_DEFAULT
pub fn genACCESS_DEFAULT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate mmap.MAP_SHARED
pub fn genMAP_SHARED(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0x01)");
}

/// Generate mmap.MAP_PRIVATE
pub fn genMAP_PRIVATE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0x02)");
}

/// Generate mmap.MAP_ANONYMOUS
pub fn genMAP_ANONYMOUS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0x20)");
}

/// Generate mmap.PROT_READ
pub fn genPROT_READ(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0x01)");
}

/// Generate mmap.PROT_WRITE
pub fn genPROT_WRITE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0x02)");
}

/// Generate mmap.PROT_EXEC
pub fn genPROT_EXEC(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0x04)");
}

/// Generate mmap.PAGESIZE
pub fn genPAGESIZE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(usize, 4096)");
}

/// Generate mmap.ALLOCATIONGRANULARITY
pub fn genALLOCATIONGRANULARITY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(usize, 4096)");
}

/// Generate mmap.MADV_NORMAL
pub fn genMADV_NORMAL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate mmap.MADV_RANDOM
pub fn genMADV_RANDOM(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

/// Generate mmap.MADV_SEQUENTIAL
pub fn genMADV_SEQUENTIAL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

/// Generate mmap.MADV_WILLNEED
pub fn genMADV_WILLNEED(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 3)");
}

/// Generate mmap.MADV_DONTNEED
pub fn genMADV_DONTNEED(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 4)");
}
