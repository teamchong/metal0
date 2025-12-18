/// Python shutil module - high-level file operations
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "copy", genCopy }, .{ "copy2", genCopy }, .{ "copyfile", genCopy },
    .{ "copystat", h.c("{}") }, .{ "copymode", h.c("{}") },
    .{ "move", genMove },
    .{ "rmtree", genRmtree },
    .{ "copytree", genCopytree },
    .{ "disk_usage", h.c(".{ @as(i64, 0), @as(i64, 0), @as(i64, 0) }") },
    .{ "which", genWhich },
    .{ "get_terminal_size", h.c(".{ @as(i64, 80), @as(i64, 24) }") },
    .{ "make_archive", h.pass("\"\"") }, .{ "unpack_archive", h.c("{}") },
});

fn genCopy(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("\"\""); return; }
    const b = try self.getBuilder();
    const label = try b.emitInlineBlockStart("cp");
    try self.emit("const _src = "); try self.genExpr(args[0]);
    try self.emit("; const _dst = "); try self.genExpr(args[1]);
    try self.emitFmt("; std.fs.copyFileAbsolute(_src, _dst, .{{}}) catch break :{s} _dst; break :{s} _dst; ", .{ label, label });
    try b.emitInlineBlockEnd();
}

fn genMove(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("\"\""); return; }
    const b = try self.getBuilder();
    const label = try b.emitInlineBlockStart("mv");
    try self.emit("const _src = "); try self.genExpr(args[0]);
    try self.emit("; const _dst = "); try self.genExpr(args[1]);
    try self.emitFmt("; std.fs.renameAbsolute(_src, _dst) catch break :{s} _dst; break :{s} _dst; ", .{ label, label });
    try b.emitInlineBlockEnd();
}

fn genRmtree(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("{}"); return; }
    const b = try self.getBuilder();
    const label = try b.emitInlineBlockStart("rm");
    try self.emit("const _path = "); try self.genExpr(args[0]);
    try self.emitFmt("; std.fs.deleteTreeAbsolute(_path) catch unreachable; break :{s}; ", .{label});
    try b.emitInlineBlockEnd();
}

fn genCopytree(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("\"\""); return; }
    const b = try self.getBuilder();
    const label = try b.emitInlineBlockStart("cpt");
    try self.emit("const _src = "); try self.genExpr(args[0]);
    try self.emit("; const _dst = "); try self.genExpr(args[1]);
    try self.emitFmt("; var _src_dir = std.fs.openDirAbsolute(_src, .{{ .iterate = true }}) catch break :{s} _dst; defer _src_dir.close(); std.fs.makeDirAbsolute(_dst) catch unreachable; var _iter = _src_dir.iterate(); while (_iter.next() catch null) |entry| {{ const _src_path = std.fmt.allocPrint(__global_allocator, \"{{s}}/{{s}}\", .{{_src, entry.name}}) catch continue; defer __global_allocator.free(_src_path); const _dst_path = std.fmt.allocPrint(__global_allocator, \"{{s}}/{{s}}\", .{{_dst, entry.name}}) catch continue; defer __global_allocator.free(_dst_path); if (entry.kind == .file) std.fs.copyFileAbsolute(_src_path, _dst_path, .{{}}) catch continue; }} break :{s} _dst; ", .{ label, label });
    try b.emitInlineBlockEnd();
}

fn genWhich(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("null"); return; }
    const b = try self.getBuilder();
    const label = try b.emitInlineBlockStart("wh");
    try self.emit("const _cmd = "); try self.genExpr(args[0]);
    try self.emitFmt("; const _paths = if (comptime @import(\"builtin\").os.tag == .windows) @as(?[]const u8, null) else std.posix.getenv(\"PATH\"); if (_paths) |_p| {{ var _iter = std.mem.splitSequence(u8, _p, \":\"); while (_iter.next()) |dir| {{ const _full_path = std.fmt.allocPrint(__global_allocator, \"{{s}}/{{s}}\", .{{dir, _cmd}}) catch continue; const _stat = std.fs.cwd().statFile(_full_path) catch continue; _ = _stat; break :{s} _full_path; }} }} break :{s} null; ", .{ label, label });
    try b.emitInlineBlockEnd();
}
