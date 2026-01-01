/// File methods - read(), write(), close(), readline(), seek(), tell(), flush(), readlines(), writelines()
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

// isFileUncertain replaced by self.isExprUncertain() (DRY consolidation)

/// Generate code for file.read(n=-1)
/// Two-Flow: Uses runtime.PyFile which handles type dispatch internally
/// Context-aware: at module level uses catch unreachable instead of try
pub fn genFileRead(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    const at_module_level = self.current_function_name == null;
    if (!at_module_level) try self.emit("try ");
    if (args.len > 0) {
        // read(n) - read n bytes
        const Ctx = struct { o: ast.Node, n: ast.Node };
        try self.emitCallCtx("runtime.PyFile.readN", Ctx{ .o = obj, .n = args[0] }, struct {
            pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
                try s.genExpr(ctx.o);
                try s.emit(", ");
                try s.genExpr(ctx.n);
                try s.emit(", __global_allocator");
            }
        }.f);
    } else {
        // read() - read all
        try self.emitCallCtx("runtime.PyFile.read", obj, struct {
            pub fn f(s: *NativeCodegen, o: ast.Node) CodegenError!void {
                try s.genExpr(o);
                try s.emit(", __global_allocator");
            }
        }.f);
    }
    if (at_module_level) try self.emit(" catch unreachable");
}

/// Generate code for file.write(content)
/// Context-aware: at module level uses catch unreachable instead of try
pub fn genFileWrite(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("@compileError(\"write() requires 1 argument\")"); return; }
    const at_module_level = self.current_function_name == null;
    if (!at_module_level) try self.emit("try ");
    const Ctx = struct { o: ast.Node, a: ast.Node };
    try self.emitCallCtx("runtime.PyFile.write", Ctx{ .o = obj, .a = args[0] }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.genExpr(ctx.o);
            try s.emit(", ");
            try s.genExpr(ctx.a);
        }
    }.f);
    if (at_module_level) try self.emit(" catch unreachable");
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
    try self.withInlineBlock("readline", obj, struct {
        fn emit(s: *NativeCodegen, label: []const u8, o: ast.Node) CodegenError!void {
            try s.emit("const _f = "); try s.genExpr(o);
            try s.emit("; var _line: std.ArrayListUnmanaged(u8) = .{}; const _reader = _f.file.reader(); ");
            try s.emit("while (_reader.readByte()) |c| { _line.append(__global_allocator, c) catch break; if (c == '\\n') break; } else |_| {{}} ");
            try s.emitFmt("break :{s} _line.items", .{label});
        }
    }.emit);
}

/// Generate code for file.readlines(hint=-1)
pub fn genFileReadlines(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.withInlineBlock("readlines", obj, struct {
        fn emit(s: *NativeCodegen, label: []const u8, o: ast.Node) CodegenError!void {
            try s.emit("const _f = "); try s.genExpr(o);
            try s.emit("; var _lines: std.ArrayListUnmanaged([]const u8) = .{}; const _reader = _f.file.reader(); ");
            try s.emit("while (true) { var _line: std.ArrayListUnmanaged(u8) = .{}; var _got_data = false; ");
            try s.emit("while (_reader.readByte()) |c| { _got_data = true; _line.append(__global_allocator, c) catch break; if (c == '\\n') break; } else |_| {{}} ");
            try s.emit("if (!_got_data) break; _lines.append(__global_allocator, _line.items) catch continue; } ");
            try s.emitFmt("break :{s} _lines.items", .{label});
        }
    }.emit);
}

/// Generate code for file.writelines(lines)
pub fn genFileWritelines(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return error.UnsupportedSyntax;
    const Ctx = struct { o: ast.Node, lines_arg: ast.Node };
    try self.withInlineBlock("writelines", Ctx{ .o = obj, .lines_arg = args[0] }, struct {
        fn emit(s: *NativeCodegen, label: []const u8, ctx: Ctx) CodegenError!void {
            try s.emit("const _f = "); try s.genExpr(ctx.o);
            try s.emit("; const _lines = "); try s.genExpr(ctx.lines_arg);
            try s.emitFmt("; for (_lines) |_line| {{ _ = _f.file.write(_line) catch continue; }} break :{s} {{}}", .{label});
        }
    }.emit);
}

/// Generate code for file.seek(offset, whence=0)
pub fn genFileSeek(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return error.UnsupportedSyntax;
    const Ctx = struct { o: ast.Node, a: []ast.Node };
    try self.withInlineBlock("seek", Ctx{ .o = obj, .a = args }, struct {
        fn emit(s: *NativeCodegen, label: []const u8, ctx: Ctx) CodegenError!void {
            try s.emit("const _f = "); try s.genExpr(ctx.o);
            try s.emit("; const _offset: i64 = @intCast("); try s.genExpr(ctx.a[0]); try s.emit("); ");
            if (ctx.a.len > 1) {
                try s.emit("const _whence: u2 = @intCast("); try s.genExpr(ctx.a[1]); try s.emit("); ");
                try s.emit("const _w: std.fs.File.SeekableStream.SeekTo = switch (_whence) { 0 => .start, 1 => .cur, 2 => .end, else => .start }; ");
                try s.emit("_f.file.seekTo(@intCast(_offset)) catch |err| { _ = err; }; ");
            } else {
                try s.emit("_f.file.seekTo(@intCast(_offset)) catch |err| { _ = err; }; ");
            }
            try s.emitFmt("break :{s} {{}}", .{label});
        }
    }.emit);
}

/// Generate code for file.tell()
pub fn genFileTell(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.withInlineBlock("tell", obj, struct {
        fn emit(s: *NativeCodegen, label: []const u8, o: ast.Node) CodegenError!void {
            try s.emit("const _f = "); try s.genExpr(o);
            try s.emitFmt("; break :{s} @as(i64, @intCast(_f.file.getPos() catch 0))", .{label});
        }
    }.emit);
}

/// Generate code for file.flush()
pub fn genFileFlush(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.withInlineBlock("flush", obj, struct {
        fn emit(s: *NativeCodegen, label: []const u8, o: ast.Node) CodegenError!void {
            try s.emit("const _f = "); try s.genExpr(o);
            try s.emitFmt("; _ = _f; break :{s} {{}}", .{label}); // Zig auto-flushes on write
        }
    }.emit);
}

/// Generate code for file.truncate(size=None)
pub fn genFileTruncate(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    const Ctx = struct { o: ast.Node, a: []ast.Node };
    try self.withInlineBlock("truncate", Ctx{ .o = obj, .a = args }, struct {
        fn emit(s: *NativeCodegen, label: []const u8, ctx: Ctx) CodegenError!void {
            try s.emit("const _f = "); try s.genExpr(ctx.o);
            if (ctx.a.len > 0) {
                try s.emit("; const _size: u64 = @intCast("); try s.genExpr(ctx.a[0]); try s.emit("); ");
                try s.emit("_f.file.setEndPos(_size) catch |err| { _ = err; }; ");
            } else {
                try s.emit("; const _pos = _f.file.getPos() catch 0; _f.file.setEndPos(_pos) catch |err| { _ = err; }; ");
            }
            try s.emitFmt("break :{s} {{}}", .{label});
        }
    }.emit);
}

/// Generate code for file.readable()
pub fn genFileReadable(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.withInlineBlock("readable", obj, struct {
        fn emit(s: *NativeCodegen, label: []const u8, o: ast.Node) CodegenError!void {
            try s.emit("_ = "); try s.genExpr(o);
            try s.emitFmt("; break :{s} true", .{label});
        }
    }.emit);
}

/// Generate code for file.writable()
pub fn genFileWritable(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.withInlineBlock("writable", obj, struct {
        fn emit(s: *NativeCodegen, label: []const u8, o: ast.Node) CodegenError!void {
            try s.emit("_ = "); try s.genExpr(o);
            try s.emitFmt("; break :{s} true", .{label});
        }
    }.emit);
}

/// Generate code for file.seekable()
pub fn genFileSeekable(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.withInlineBlock("seekable", obj, struct {
        fn emit(s: *NativeCodegen, label: []const u8, o: ast.Node) CodegenError!void {
            try s.emit("_ = "); try s.genExpr(o);
            try s.emitFmt("; break :{s} true", .{label});
        }
    }.emit);
}

/// Generate code for file.fileno()
pub fn genFileFileno(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.withInlineBlock("fileno", obj, struct {
        fn emit(s: *NativeCodegen, label: []const u8, o: ast.Node) CodegenError!void {
            try s.emit("const _f = "); try s.genExpr(o);
            try s.emitFmt("; break :{s} if (comptime @import(\"builtin\").os.tag == .windows) @as(i64, @intFromPtr(_f.file.handle)) else @as(i64, @intCast(_f.file.handle))", .{label});
        }
    }.emit);
}

/// Generate code for file.isatty()
pub fn genFileIsatty(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.withInlineBlock("isatty", obj, struct {
        fn emit(s: *NativeCodegen, label: []const u8, o: ast.Node) CodegenError!void {
            try s.emit("const _f = "); try s.genExpr(o);
            try s.emitFmt("; break :{s} if (comptime @import(\"builtin\").os.tag == .windows) std.os.windows.GetFileType(_f.file.handle) == std.os.windows.FILE_TYPE_CHAR else std.posix.isatty(_f.file.handle)", .{label});
        }
    }.emit);
}
