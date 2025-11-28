/// Python shutil module - high-level file operations
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate shutil.copy(src, dst) -> dst
pub fn genCopy(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("shutil_copy_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _src = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _dst = ");
    try self.genExpr(args[1]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("std.fs.copyFileAbsolute(_src, _dst, .{}) catch break :shutil_copy_blk _dst;\n");
    try self.emitIndent();
    try self.emit("break :shutil_copy_blk _dst;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate shutil.copy2(src, dst) -> dst (preserves metadata)
pub fn genCopy2(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Same as copy for now
    try genCopy(self, args);
}

/// Generate shutil.copyfile(src, dst) -> dst
pub fn genCopyfile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Same as copy
    try genCopy(self, args);
}

/// Generate shutil.copystat(src, dst) -> None
pub fn genCopystat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // No-op for basic implementation
    try self.emit("{}");
}

/// Generate shutil.copymode(src, dst) -> None
pub fn genCopymode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate shutil.move(src, dst) -> dst
pub fn genMove(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("shutil_move_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _src = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _dst = ");
    try self.genExpr(args[1]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("std.fs.renameAbsolute(_src, _dst) catch break :shutil_move_blk _dst;\n");
    try self.emitIndent();
    try self.emit("break :shutil_move_blk _dst;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate shutil.rmtree(path) -> None
pub fn genRmtree(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("shutil_rmtree_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _path = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("std.fs.deleteTreeAbsolute(_path) catch {};\n");
    try self.emitIndent();
    try self.emit("break :shutil_rmtree_blk;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate shutil.copytree(src, dst) -> dst
pub fn genCopytree(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("shutil_copytree_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _src = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _dst = ");
    try self.genExpr(args[1]);
    try self.emit(";\n");
    try self.emitIndent();
    // Simple recursive copy using Zig's fs functions
    try self.emit("var _src_dir = std.fs.openDirAbsolute(_src, .{ .iterate = true }) catch break :shutil_copytree_blk _dst;\n");
    try self.emitIndent();
    try self.emit("defer _src_dir.close();\n");
    try self.emitIndent();
    try self.emit("std.fs.makeDirAbsolute(_dst) catch {};\n");
    try self.emitIndent();
    try self.emit("var _iter = _src_dir.iterate();\n");
    try self.emitIndent();
    try self.emit("while (_iter.next() catch null) |entry| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _src_path = std.fmt.allocPrint(allocator, \"{s}/{s}\", .{_src, entry.name}) catch continue;\n");
    try self.emitIndent();
    try self.emit("defer allocator.free(_src_path);\n");
    try self.emitIndent();
    try self.emit("const _dst_path = std.fmt.allocPrint(allocator, \"{s}/{s}\", .{_dst, entry.name}) catch continue;\n");
    try self.emitIndent();
    try self.emit("defer allocator.free(_dst_path);\n");
    try self.emitIndent();
    try self.emit("if (entry.kind == .file) std.fs.copyFileAbsolute(_src_path, _dst_path, .{}) catch continue;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :shutil_copytree_blk _dst;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate shutil.disk_usage(path) -> (total, used, free)
pub fn genDiskUsage(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Placeholder - would need system calls
    try self.emit(".{ @as(i64, 0), @as(i64, 0), @as(i64, 0) }");
}

/// Generate shutil.which(cmd) -> path or None
pub fn genWhich(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("shutil_which_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _cmd = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _paths = std.posix.getenv(\"PATH\") orelse break :shutil_which_blk null;\n");
    try self.emitIndent();
    try self.emit("var _iter = std.mem.splitSequence(u8, _paths, \":\");\n");
    try self.emitIndent();
    try self.emit("while (_iter.next()) |dir| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _full_path = std.fmt.allocPrint(allocator, \"{s}/{s}\", .{dir, _cmd}) catch continue;\n");
    try self.emitIndent();
    try self.emit("const _stat = std.fs.cwd().statFile(_full_path) catch continue;\n");
    try self.emitIndent();
    try self.emit("_ = _stat;\n");
    try self.emitIndent();
    try self.emit("break :shutil_which_blk _full_path;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :shutil_which_blk null;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate shutil.get_terminal_size() -> (columns, lines)
pub fn genGetTerminalSize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(i64, 80), @as(i64, 24) }");
}

/// Generate shutil.make_archive(base_name, format, root_dir=None) -> archive path
pub fn genMakeArchive(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    // Placeholder - just return base_name
    try self.genExpr(args[0]);
}

/// Generate shutil.unpack_archive(filename, extract_dir=None, format=None) -> None
pub fn genUnpackArchive(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Placeholder
    try self.emit("{}");
}
