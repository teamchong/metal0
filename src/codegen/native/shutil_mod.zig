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
    try self.withInlineBlock("cp", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _src = "); try c.genExpr(a[0]);
            try c.emit("; const _dst = "); try c.genExpr(a[1]);
            try c.emitFmt("; std.fs.copyFileAbsolute(_src, _dst, .{{}}) catch break :{s} _dst; break :{s} _dst; ", .{ label, label });
        }
    }.emit);
}

fn genMove(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("\"\""); return; }
    try self.withInlineBlock("mv", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _src = "); try c.genExpr(a[0]);
            try c.emit("; const _dst = "); try c.genExpr(a[1]);
            try c.emitFmt("; std.fs.renameAbsolute(_src, _dst) catch break :{s} _dst; break :{s} _dst; ", .{ label, label });
        }
    }.emit);
}

fn genRmtree(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("{}"); return; }
    try self.withInlineBlock("rm", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _path = "); try c.genExpr(a[0]);
            try c.emitFmt("; std.fs.deleteTreeAbsolute(_path) catch unreachable; break :{s}; ", .{label});
        }
    }.emit);
}

fn genCopytree(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("\"\""); return; }
    try self.withInlineBlock("cpt", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _src = "); try c.genExpr(a[0]);
            try c.emit("; const _dst = "); try c.genExpr(a[1]);
            try c.emitFmt("; var _src_dir = std.fs.openDirAbsolute(_src, .{{ .iterate = true }}) catch break :{s} _dst; defer _src_dir.close(); std.fs.makeDirAbsolute(_dst) catch unreachable; var _iter = _src_dir.iterate(); while (_iter.next() catch null) |entry| {{ const _src_path = std.fmt.allocPrint(__global_allocator, \"{{s}}/{{s}}\", .{{_src, entry.name}}) catch continue; defer __global_allocator.free(_src_path); const _dst_path = std.fmt.allocPrint(__global_allocator, \"{{s}}/{{s}}\", .{{_dst, entry.name}}) catch continue; defer __global_allocator.free(_dst_path); if (entry.kind == .file) std.fs.copyFileAbsolute(_src_path, _dst_path, .{{}}) catch continue; }} break :{s} _dst; ", .{ label, label });
        }
    }.emit);
}

fn genWhich(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("null"); return; }
    try self.withInlineBlock("wh", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _cmd = "); try c.genExpr(a[0]);
            try c.emitFmt("; const _paths = if (comptime @import(\"builtin\").os.tag == .windows) @as(?[]const u8, null) else std.posix.getenv(\"PATH\"); if (_paths) |_p| {{ var _iter = std.mem.splitSequence(u8, _p, \":\"); while (_iter.next()) |dir| {{ const _full_path = std.fmt.allocPrint(__global_allocator, \"{{s}}/{{s}}\", .{{dir, _cmd}}) catch continue; const _stat = std.fs.cwd().statFile(_full_path) catch continue; _ = _stat; break :{s} _full_path; }} }} break :{s} null; ", .{ label, label });
        }
    }.emit);
}
