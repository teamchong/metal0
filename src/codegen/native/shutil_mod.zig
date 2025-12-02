/// Python shutil module - high-level file operations
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "copy", genCopy }, .{ "copy2", genCopy }, .{ "copyfile", genCopy },
    .{ "copystat", h.c("{}") }, .{ "copymode", h.c("{}") },
    .{ "move", genMove }, .{ "rmtree", genRmtree }, .{ "copytree", genCopytree },
    .{ "disk_usage", h.c(".{ @as(i64, 0), @as(i64, 0), @as(i64, 0) }") },
    .{ "which", genWhich },
    .{ "get_terminal_size", h.c(".{ @as(i64, 80), @as(i64, 24) }") },
    .{ "make_archive", genMakeArchive }, .{ "unpack_archive", h.c("{}") },
});

fn genCopy(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("blk: { const _src = "); try self.genExpr(args[0]); try self.emit("; const _dst = "); try self.genExpr(args[1]);
    try self.emit("; std.fs.copyFileAbsolute(_src, _dst, .{}) catch break :blk _dst; break :blk _dst; }");
}

fn genMove(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("blk: { const _src = "); try self.genExpr(args[0]); try self.emit("; const _dst = "); try self.genExpr(args[1]);
    try self.emit("; std.fs.renameAbsolute(_src, _dst) catch break :blk _dst; break :blk _dst; }");
}

fn genRmtree(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const _path = "); try self.genExpr(args[0]); try self.emit("; std.fs.deleteTreeAbsolute(_path) catch {}; break :blk; }");
}

fn genCopytree(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("blk: { const _src = "); try self.genExpr(args[0]); try self.emit("; const _dst = "); try self.genExpr(args[1]);
    try self.emit("; var _src_dir = std.fs.openDirAbsolute(_src, .{ .iterate = true }) catch break :blk _dst; defer _src_dir.close(); std.fs.makeDirAbsolute(_dst) catch {}; var _iter = _src_dir.iterate(); while (_iter.next() catch null) |entry| { const _src_path = std.fmt.allocPrint(__global_allocator, \"{s}/{s}\", .{_src, entry.name}) catch continue; defer __global_allocator.free(_src_path); const _dst_path = std.fmt.allocPrint(__global_allocator, \"{s}/{s}\", .{_dst, entry.name}) catch continue; defer __global_allocator.free(_dst_path); if (entry.kind == .file) std.fs.copyFileAbsolute(_src_path, _dst_path, .{}) catch continue; } break :blk _dst; }");
}

fn genWhich(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const _cmd = "); try self.genExpr(args[0]);
    try self.emit("; const _paths = std.posix.getenv(\"PATH\") orelse break :blk null; var _iter = std.mem.splitSequence(u8, _paths, \":\"); while (_iter.next()) |dir| { const _full_path = std.fmt.allocPrint(__global_allocator, \"{s}/{s}\", .{dir, _cmd}) catch continue; const _stat = std.fs.cwd().statFile(_full_path) catch continue; _ = _stat; break :blk _full_path; } break :blk null; }");
}

fn genMakeArchive(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.genExpr(args[0]);
}
