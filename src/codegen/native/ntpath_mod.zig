/// Python ntpath module - Windows pathname functions
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

fn genPathOp(comptime body: []const u8, comptime default: []const u8) h.H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len > 0) { try self.emit("blk: { const path = "); try self.genExpr(args[0]); try self.emit("; " ++ body ++ " }"); } else try self.emit(default);
    } }.f;
}

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "abspath", genPathOp("var buf: [4096]u8 = undefined; break :blk std.fs.cwd().realpath(path, &buf) catch path;", "\"\"") },
    .{ "basename", genPathOp("break :blk std.fs.path.basename(path);", "\"\"") },
    .{ "dirname", genPathOp("break :blk std.fs.path.dirname(path) orelse \"\";", "\"\"") },
    .{ "exists", genPathOp("_ = std.fs.cwd().statFile(path) catch break :blk false; break :blk true;", "false") },
    .{ "expanduser", genExpanduser }, .{ "expandvars", h.pass("\"\"") },
    .{ "getsize", genPathOp("const stat = std.fs.cwd().statFile(path) catch break :blk @as(i64, 0); break :blk @intCast(stat.size);", "@as(i64, 0)") },
    .{ "isabs", genPathOp("break :blk (path.len > 0 and path[0] == '/') or (path.len > 2 and path[1] == ':');", "false") },
    .{ "isdir", genPathOp("const dir = std.fs.cwd().openDir(path, .{}) catch break :blk false; dir.close(); break :blk true;", "false") },
    .{ "isfile", genPathOp("const stat = std.fs.cwd().statFile(path) catch break :blk false; break :blk stat.kind == .file;", "false") },
    .{ "islink", genPathOp("const stat = std.fs.cwd().statFile(path) catch break :blk false; break :blk stat.kind == .sym_link;", "false") },
    .{ "join", genJoin }, .{ "lexists", genPathOp("_ = std.fs.cwd().statFile(path) catch break :blk false; break :blk true;", "false") },
    .{ "normcase", genPathOp("var result = metal0_allocator.alloc(u8, path.len) catch break :blk path; for (path, 0..) |c, i| { result[i] = if (c >= 'A' and c <= 'Z') c + 32 else if (c == '/') '\\\\' else c; } break :blk result;", "\"\"") },
    .{ "normpath", h.pass("\"\"") }, .{ "realpath", genPathOp("var buf: [4096]u8 = undefined; break :blk std.fs.cwd().realpath(path, &buf) catch path;", "\"\"") },
    .{ "relpath", h.pass("\"\"") }, .{ "samefile", genSamefile }, .{ "split", genSplit }, .{ "splitdrive", genSplitdrive }, .{ "splitext", genSplitext },
    .{ "commonpath", h.c("\"\"") }, .{ "commonprefix", h.c("\"\"") },
    .{ "getatime", h.F64(0.0) }, .{ "getctime", h.F64(0.0) }, .{ "getmtime", h.F64(0.0) },
    .{ "ismount", h.c("false") }, .{ "sameopenfile", h.c("false") }, .{ "samestat", h.c("false") },
    .{ "sep", h.c("\"\\\\\"") }, .{ "altsep", h.c("\"/\"") }, .{ "extsep", h.c("\".\"") },
    .{ "pathsep", h.c("\";\"") }, .{ "defpath", h.c("\".;C:\\\\bin\"") }, .{ "devnull", h.c("\"nul\"") },
    .{ "curdir", h.c("\".\"") }, .{ "pardir", h.c("\"..\"") },
});

fn genExpanduser(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const path = "); try self.genExpr(args[0]); try self.emit("; if (path.len > 0 and path[0] == '~') { const home = std.posix.getenv(\"USERPROFILE\") orelse std.posix.getenv(\"HOME\") orelse \"\"; break :blk std.fmt.allocPrint(metal0_allocator, \"{s}{s}\", .{ home, path[1..] }) catch path; } break :blk path; }"); } else try self.emit("\"\"");
}
fn genJoin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { var parts: [16][]const u8 = undefined; var count: usize = 0; ");
        for (args, 0..) |arg, i| { try self.emitFmt("parts[{d}] = ", .{i}); try self.genExpr(arg); try self.emit("; count += 1; "); }
        try self.emit("break :blk std.fs.path.join(metal0_allocator, parts[0..count]) catch \"\"; }");
    } else try self.emit("\"\"");
}
fn genSamefile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { const p1 = "); try self.genExpr(args[0]); try self.emit("; const p2 = "); try self.genExpr(args[1]); try self.emit("; break :blk std.mem.eql(u8, p1, p2); }"); } else try self.emit("false");
}
fn genSplit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const path = "); try self.genExpr(args[0]); try self.emit("; const dir = std.fs.path.dirname(path) orelse \"\"; const base = std.fs.path.basename(path); break :blk .{ dir, base }; }"); } else try self.emit(".{ \"\", \"\" }");
}
fn genSplitdrive(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const path = "); try self.genExpr(args[0]); try self.emit("; if (path.len >= 2 and path[1] == ':') { break :blk .{ path[0..2], path[2..] }; } break :blk .{ \"\", path }; }"); } else try self.emit(".{ \"\", \"\" }");
}
fn genSplitext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const path = "); try self.genExpr(args[0]); try self.emit("; const ext = std.fs.path.extension(path); const stem_len = path.len - ext.len; break :blk .{ path[0..stem_len], ext }; }"); } else try self.emit(".{ \"\", \"\" }");
}
