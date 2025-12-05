/// File methods - read(), write(), close(), readline(), seek(), tell(), flush(), readlines(), writelines()
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

/// Generate code for file.read(n=-1)
pub fn genFileRead(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        // read(n) - read n bytes
        try self.emit("try runtime.PyFile.readN(");
        try self.genExpr(obj);
        try self.emit(", ");
        try self.genExpr(args[0]);
        try self.emit(", __global_allocator)");
    } else {
        // read() - read all
        try self.emit("try runtime.PyFile.read(");
        try self.genExpr(obj);
        try self.emit(", __global_allocator)");
    }
}

/// Generate code for file.write(content)
pub fn genFileWrite(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("@compileError(\"write() requires 1 argument\")"); return; }
    try self.emit("try runtime.PyFile.write("); try self.genExpr(obj); try self.emit(", "); try self.genExpr(args[0]); try self.emit(")");
}

/// Generate code for file.close()
pub fn genFileClose(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("runtime.PyFile.close("); try self.genExpr(obj); try self.emit(")");
}

/// Generate code for file.readline(size=-1)
pub fn genFileReadline(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args; // size parameter ignored for now
    try self.emit("readline_blk: { const _f = "); try self.genExpr(obj);
    try self.emit("; var _line: std.ArrayListUnmanaged(u8) = .{}; const _reader = _f.file.reader(); ");
    try self.emit("while (_reader.readByte()) |c| { _line.append(__global_allocator, c) catch break; if (c == '\\n') break; } else |_| {} ");
    try self.emit("break :readline_blk _line.items; }");
}

/// Generate code for file.readlines(hint=-1)
pub fn genFileReadlines(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("readlines_blk: { const _f = "); try self.genExpr(obj);
    try self.emit("; var _lines: std.ArrayListUnmanaged([]const u8) = .{}; const _reader = _f.file.reader(); ");
    try self.emit("while (true) { var _line: std.ArrayListUnmanaged(u8) = .{}; var _got_data = false; ");
    try self.emit("while (_reader.readByte()) |c| { _got_data = true; _line.append(__global_allocator, c) catch break; if (c == '\\n') break; } else |_| {} ");
    try self.emit("if (!_got_data) break; _lines.append(__global_allocator, _line.items) catch continue; } ");
    try self.emit("break :readlines_blk _lines.items; }");
}

/// Generate code for file.writelines(lines)
pub fn genFileWritelines(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return;
    try self.emit("writelines_blk: { const _f = "); try self.genExpr(obj);
    try self.emit("; const _lines = "); try self.genExpr(args[0]);
    try self.emit("; for (_lines) |_line| { _ = _f.file.write(_line) catch continue; } break :writelines_blk {}; }");
}

/// Generate code for file.seek(offset, whence=0)
pub fn genFileSeek(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return;
    try self.emit("seek_blk: { const _f = "); try self.genExpr(obj);
    try self.emit("; const _offset: i64 = @intCast("); try self.genExpr(args[0]); try self.emit("); ");
    if (args.len > 1) {
        try self.emit("const _whence: u2 = @intCast("); try self.genExpr(args[1]); try self.emit("); ");
        try self.emit("const _w: std.fs.File.SeekableStream.SeekTo = switch (_whence) { 0 => .start, 1 => .cur, 2 => .end, else => .start }; ");
        try self.emit("_f.file.seekTo(@intCast(_offset)) catch {}; ");
    } else {
        try self.emit("_f.file.seekTo(@intCast(_offset)) catch {}; ");
    }
    try self.emit("break :seek_blk {}; }");
}

/// Generate code for file.tell()
pub fn genFileTell(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("tell_blk: { const _f = "); try self.genExpr(obj);
    try self.emit("; break :tell_blk @as(i64, @intCast(_f.file.getPos() catch 0)); }");
}

/// Generate code for file.flush()
pub fn genFileFlush(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("flush_blk: { const _f = "); try self.genExpr(obj);
    try self.emit("; _ = _f; break :flush_blk {}; }"); // Zig auto-flushes on write
}

/// Generate code for file.truncate(size=None)
pub fn genFileTruncate(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    try self.emit("truncate_blk: { const _f = "); try self.genExpr(obj);
    if (args.len > 0) {
        try self.emit("; const _size: u64 = @intCast("); try self.genExpr(args[0]); try self.emit("); ");
        try self.emit("_f.file.setEndPos(_size) catch {}; ");
    } else {
        try self.emit("; const _pos = _f.file.getPos() catch 0; _f.file.setEndPos(_pos) catch {}; ");
    }
    try self.emit("break :truncate_blk {}; }");
}

/// Generate code for file.readable()
pub fn genFileReadable(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("readable_blk: { _ = "); try self.genExpr(obj); try self.emit("; break :readable_blk true; }");
}

/// Generate code for file.writable()
pub fn genFileWritable(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("writable_blk: { _ = "); try self.genExpr(obj); try self.emit("; break :writable_blk true; }");
}

/// Generate code for file.seekable()
pub fn genFileSeekable(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("seekable_blk: { _ = "); try self.genExpr(obj); try self.emit("; break :seekable_blk true; }");
}

/// Generate code for file.fileno()
pub fn genFileFileno(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("fileno_blk: { const _f = "); try self.genExpr(obj);
    try self.emit("; break :fileno_blk @as(i64, @intCast(_f.file.handle)); }");
}

/// Generate code for file.isatty()
pub fn genFileIsatty(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("isatty_blk: { const _f = "); try self.genExpr(obj);
    try self.emit("; break :isatty_blk std.posix.isatty(_f.file.handle); }");
}
