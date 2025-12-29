/// File methods - read(), write(), close(), readline(), seek(), tell(), flush(), readlines(), writelines()
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

/// Check if a file expression is uncertain (needs PyValue operations)
/// Two-Flow: File objects from open() are typically certain, but function params may be uncertain
/// Note: Current implementation assumes file objects are always runtime.PyFile
fn isFileUncertain(self: *NativeCodegen, obj: ast.Node) bool {
    if (obj == .name) {
        const name = obj.name.id;
        const var_type = self.type_inferrer.getScopedVar(name) orelse
            self.type_inferrer.var_types.get(name);
        if (var_type) |vt| {
            switch (vt) {
                .pyvalue, .unknown => return true,
                else => {},
            }
        }
        return false;
    }
    return false;
}

/// Generate code for file.read(n=-1)
/// Two-Flow: Uses runtime.PyFile which handles type dispatch internally
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
    const Ctx = struct { o: ast.Node, a: ast.Node };
    try self.emitCallCtx("try runtime.PyFile.write", Ctx{ .o = obj, .a = args[0] }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.genExpr(ctx.o);
            try s.emit(", ");
            try s.genExpr(ctx.a);
        }
    }.f);
}

/// Generate code for file.close()
pub fn genFileClose(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emitCallCtx("runtime.PyFile.close", obj, struct {
        pub fn f(s: *NativeCodegen, o: ast.Node) CodegenError!void {
            try s.genExpr(o);
        }
    }.f);
}

/// Generate code for file.readline(size=-1)
pub fn genFileReadline(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args; // size parameter ignored for now
    const label = try self.emitInlineBlockStart("readline");
    try self.emit("const _f = "); try self.genExpr(obj);
    try self.emit("; var _line: std.ArrayListUnmanaged(u8) = .{}; const _reader = _f.file.reader(); ");
    try self.emit("while (_reader.readByte()) |c| { _line.append(__global_allocator, c) catch break; if (c == '\\n') break; } else |_| {{}} ");
    try self.emitFmt("break :{s} _line.items; ", .{label});
    try self.emitInlineBlockEnd();
}

/// Generate code for file.readlines(hint=-1)
pub fn genFileReadlines(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const label = try self.emitInlineBlockStart("readlines");
    try self.emit("const _f = "); try self.genExpr(obj);
    try self.emit("; var _lines: std.ArrayListUnmanaged([]const u8) = .{}; const _reader = _f.file.reader(); ");
    try self.emit("while (true) { var _line: std.ArrayListUnmanaged(u8) = .{}; var _got_data = false; ");
    try self.emit("while (_reader.readByte()) |c| { _got_data = true; _line.append(__global_allocator, c) catch break; if (c == '\\n') break; } else |_| {{}} ");
    try self.emit("if (!_got_data) break; _lines.append(__global_allocator, _line.items) catch continue; } ");
    try self.emitFmt("break :{s} _lines.items; ", .{label});
    try self.emitInlineBlockEnd();
}

/// Generate code for file.writelines(lines)
pub fn genFileWritelines(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return error.UnsupportedSyntax;
    const label = try self.emitInlineBlockStart("writelines");
    try self.emit("const _f = "); try self.genExpr(obj);
    try self.emit("; const _lines = "); try self.genExpr(args[0]);
    try self.emitFmt("; for (_lines) |_line| {{ _ = _f.file.write(_line) catch continue; }} break :{s} {{}}; ", .{label});
    try self.emitInlineBlockEnd();
}

/// Generate code for file.seek(offset, whence=0)
pub fn genFileSeek(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return error.UnsupportedSyntax;
    const label = try self.emitInlineBlockStart("seek");
    try self.emit("const _f = "); try self.genExpr(obj);
    try self.emit("; const _offset: i64 = @intCast("); try self.genExpr(args[0]); try self.emit("); ");
    if (args.len > 1) {
        try self.emit("const _whence: u2 = @intCast("); try self.genExpr(args[1]); try self.emit("); ");
        try self.emit("const _w: std.fs.File.SeekableStream.SeekTo = switch (_whence) { 0 => .start, 1 => .cur, 2 => .end, else => .start }; ");
        try self.emit("_f.file.seekTo(@intCast(_offset)) catch |err| { _ = err; }; ");
    } else {
        try self.emit("_f.file.seekTo(@intCast(_offset)) catch |err| { _ = err; }; ");
    }
    try self.emitFmt("break :{s} {{}}; ", .{label});
    try self.emitInlineBlockEnd();
}

/// Generate code for file.tell()
pub fn genFileTell(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const label = try self.emitInlineBlockStart("tell");
    try self.emit("const _f = "); try self.genExpr(obj);
    try self.emitFmt("; break :{s} @as(i64, @intCast(_f.file.getPos() catch 0)); ", .{label});
    try self.emitInlineBlockEnd();
}

/// Generate code for file.flush()
pub fn genFileFlush(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const label = try self.emitInlineBlockStart("flush");
    try self.emit("const _f = "); try self.genExpr(obj);
    try self.emitFmt("; _ = _f; break :{s} {{}}; ", .{label});
    try self.emitInlineBlockEnd(); // Zig auto-flushes on write
}

/// Generate code for file.truncate(size=None)
pub fn genFileTruncate(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    const label = try self.emitInlineBlockStart("truncate");
    try self.emit("const _f = "); try self.genExpr(obj);
    if (args.len > 0) {
        try self.emit("; const _size: u64 = @intCast("); try self.genExpr(args[0]); try self.emit("); ");
        try self.emit("_f.file.setEndPos(_size) catch |err| { _ = err; }; ");
    } else {
        try self.emit("; const _pos = _f.file.getPos() catch 0; _f.file.setEndPos(_pos) catch |err| { _ = err; }; ");
    }
    try self.emitFmt("break :{s} {{}}; ", .{label});
    try self.emitInlineBlockEnd();
}

/// Generate code for file.readable()
pub fn genFileReadable(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const label = try self.emitInlineBlockStart("readable");
    try self.emit("_ = "); try self.genExpr(obj); try self.emitFmt("; break :{s} true; ", .{label});
    try self.emitInlineBlockEnd();
}

/// Generate code for file.writable()
pub fn genFileWritable(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const label = try self.emitInlineBlockStart("writable");
    try self.emit("_ = "); try self.genExpr(obj); try self.emitFmt("; break :{s} true; ", .{label});
    try self.emitInlineBlockEnd();
}

/// Generate code for file.seekable()
pub fn genFileSeekable(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const label = try self.emitInlineBlockStart("seekable");
    try self.emit("_ = "); try self.genExpr(obj); try self.emitFmt("; break :{s} true; ", .{label});
    try self.emitInlineBlockEnd();
}

/// Generate code for file.fileno()
pub fn genFileFileno(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const label = try self.emitInlineBlockStart("fileno");
    try self.emit("const _f = "); try self.genExpr(obj);
    try self.emitFmt("; break :{s} if (comptime @import(\"builtin\").os.tag == .windows) @as(i64, @intFromPtr(_f.file.handle)) else @as(i64, @intCast(_f.file.handle)); ", .{label});
    try self.emitInlineBlockEnd();
}

/// Generate code for file.isatty()
pub fn genFileIsatty(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const label = try self.emitInlineBlockStart("isatty");
    try self.emit("const _f = "); try self.genExpr(obj);
    try self.emitFmt("; break :{s} if (comptime @import(\"builtin\").os.tag == .windows) std.os.windows.GetFileType(_f.file.handle) == std.os.windows.FILE_TYPE_CHAR else std.posix.isatty(_f.file.handle); ", .{label});
    try self.emitInlineBlockEnd();
}
