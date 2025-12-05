/// OS module - os.getcwd(), os.chdir(), os.listdir(), os.path.exists(), os.path.join() code generation
///
/// NOTE: All handlers use Zig stdlib directly (std.fs, std.process, std.posix).
/// No runtime.os module exists - these generate inline Zig code, not runtime calls.
const std = @import("std");
const ast = @import("ast");
const m = @import("mod_helper.zig");
const CodegenError = m.CodegenError;
const NativeCodegen = m.NativeCodegen;
const H = m.H;

// === Comptime helper generators for OS-specific patterns ===

/// Generate os_X_blk: { const _path = arg; ...body...; break :os_X_blk result; }
fn pathBlock(comptime name: []const u8, comptime body: []const u8, comptime result: []const u8) H {
    return struct {
        fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
            if (args.len == 0) return;
            try self.emit("os_" ++ name ++ "_blk: { const _path = ");
            try self.genExpr(args[0]);
            try self.emit("; " ++ body ++ "break :os_" ++ name ++ "_blk " ++ result ++ "; }");
        }
    }.f;
}

/// Generate simple void-returning path operation
fn pathVoid(comptime name: []const u8, comptime op: []const u8) H {
    return pathBlock(name, op ++ " catch {}; ", "{}");
}

/// Generate os_X_blk: { const _builtin = @import("builtin"); break :os_X_blk switch(_builtin.os.tag) { .windows => win, else => posix }; }
fn osSwitch(comptime name: []const u8, comptime win: []const u8, comptime posix: []const u8) H {
    return struct {
        fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
            _ = args;
            try self.emit("os_" ++ name ++ "_blk: { const _builtin = @import(\"builtin\"); break :os_" ++ name ++ "_blk switch (_builtin.os.tag) { .windows => " ++ win ++ ", else => " ++ posix ++ " }; }");
        }
    }.f;
}

/// Generate posix call with i64 cast: @as(i64, @intCast(std.posix.fn()))
fn posixI64(comptime call: []const u8) H {
    return m.c("@as(i64, @intCast(" ++ call ++ "))");
}

/// Generate posix call with arg cast: @as(i64, @intCast(std.posix.fn(@intCast(arg))))
fn posixArgI64(comptime fn_name: []const u8) H {
    return m.wrap("@as(i64, @intCast(std.posix." ++ fn_name ++ "(@intCast(", ")) catch -1))", "@as(i64, -1)");
}

// === Module function maps ===

pub const Funcs = std.StaticStringMap(H).initComptime(.{
    // Directory operations
    .{ "getcwd", genGetcwd },
    .{ "chdir", pathVoid("chdir", "std.posix.chdir(_path)") },
    .{ "listdir", genListdir },
    .{ "mkdir", pathVoid("mkdir", "std.fs.cwd().makeDir(_path)") },
    .{ "makedirs", pathVoid("makedirs", "std.fs.cwd().makePath(_path)") },
    .{ "rmdir", pathVoid("rmdir", "std.fs.cwd().deleteDir(_path)") },
    .{ "removedirs", pathVoid("removedirs", "std.fs.cwd().deleteTree(_path)") },
    // File operations
    .{ "remove", pathVoid("remove", "std.fs.cwd().deleteFile(_path)") },
    .{ "unlink", pathVoid("remove", "std.fs.cwd().deleteFile(_path)") },
    .{ "rename", genRename },
    .{ "stat", genStat },
    .{ "chmod", genChmod },
    .{ "access", genAccess },
    .{ "truncate", genTruncate },
    // Environment
    .{ "getenv", genGetenv },
    .{ "environ", m.c("hashmap_helper.StringHashMap([]const u8).init(__global_allocator)") },
    // Constants
    .{ "name", osSwitch("name", "\"nt\"", "\"posix\"") },
    .{ "curdir", m.c("\".\"") },
    .{ "pardir", m.c("\"..\"") },
    .{ "sep", m.c("\"/\"") },
    .{ "linesep", osSwitch("linesep", "\"\\r\\n\"", "\"\\n\"") },
    .{ "altsep", m.c("null") },
    .{ "extsep", m.c("\".\"") },
    .{ "pathsep", osSwitch("pathsep", "\";\"", "\":\"") },
    .{ "devnull", osSwitch("devnull", "\"nul\"", "\"/dev/null\"") },
    // Process functions
    .{ "getpid", posixI64("std.os.linux.getpid()") },
    .{ "getppid", posixI64("std.posix.getppid()") },
    .{ "getuid", posixI64("std.posix.getuid()") },
    .{ "geteuid", posixI64("std.posix.geteuid()") },
    .{ "getgid", posixI64("std.posix.getgid()") },
    .{ "getegid", posixI64("std.posix.getegid()") },
    .{ "cpu_count", m.c("@as(?i64, @intCast(std.Thread.getCpuCount() catch 1))") },
    .{ "kill", genKill },
    .{ "system", genSystem },
    // File descriptors
    .{ "close", m.wrap("std.posix.close(@intCast(", "))", "{}") },
    .{ "dup", posixArgI64("dup") },
    .{ "dup2", genDup2 },
    .{ "read", genRead },
    .{ "write", genWrite },
    .{ "open", genOpen },
    .{ "pipe", m.c("os_pipe_blk: { const _p = std.posix.pipe() catch break :os_pipe_blk .{ @as(i64, -1), @as(i64, -1) }; break :os_pipe_blk .{ @as(i64, @intCast(_p[0])), @as(i64, @intCast(_p[1])) }; }") },
    .{ "fdopen", m.wrap("os_fdopen_blk: { const _fd = @as(std.posix.fd_t, @intCast(", ")); break :os_fdopen_blk std.fs.File{ .handle = _fd }; }", "std.fs.File{ .handle = 0 }") },
    .{ "fsync", m.wrap("std.posix.fsync(@intCast(", "))", "{}") },
    .{ "isatty", m.wrap("std.posix.isatty(@intCast(", "))", "false") },
    .{ "sync", m.c("{}") },
    // Random
    .{ "urandom", genUrandom },
    .{ "umask", m.wrap("@as(i64, @intCast(std.posix.umask(@intCast(", "))))", "@as(i64, 0)") },
    .{ "utime", m.discard("{}") },
    .{ "strerror", m.discard("\"Error\"") },
    // Directory traversal
    .{ "walk", genWalk },
    .{ "scandir", genScandir },
    .{ "fspath", m.pass("\"\"") },
    .{ "get_terminal_size", m.c(".{ .columns = @as(i64, 80), .lines = @as(i64, 24) }") },
    // Symlinks
    .{ "symlink", genSymlink },
    .{ "readlink", genReadlink },
    .{ "islink", genIslink },
});

/// OS.path module functions
pub const PathFuncs = std.StaticStringMap(H).initComptime(.{
    .{ "exists", genPathExists },
    .{ "isdir", genPathIsdir },
    .{ "isfile", genPathIsfile },
    .{ "abspath", genPathAbspath },
    .{ "join", genPathJoin },
    .{ "dirname", pathBlock("path_dirname", "", "std.fs.path.dirname(_path) orelse \"\"") },
    .{ "basename", pathBlock("path_basename", "", "std.fs.path.basename(_path)") },
    .{ "split", genPathSplit },
    .{ "splitext", genPathSplitext },
    .{ "getsize", genPathGetsize },
});

// === Complex handlers that need custom logic ===

fn genGetcwd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("(std.process.getCwdAlloc(__global_allocator) catch \"\")");
}

fn genListdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("os_listdir_blk: { ");
    if (args.len >= 1) {
        try self.emit("const _dir_path = ");
        try self.genExpr(args[0]);
        try self.emit("; ");
    } else {
        try self.emit("const _dir_path = \".\"; ");
    }
    try self.emit("var _entries: std.ArrayListUnmanaged([]const u8) = .{}; var _dir = std.fs.cwd().openDir(_dir_path, .{ .iterate = true }) catch break :os_listdir_blk _entries; defer _dir.close(); var _iter = _dir.iterate(); while (_iter.next() catch null) |entry| { const _name = __global_allocator.dupe(u8, entry.name) catch continue; _entries.append(__global_allocator, _name) catch continue; } break :os_listdir_blk _entries; }");
}

fn genGetenv(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("os_getenv_blk: { const _key = ");
    try self.genExpr(args[0]);
    try self.emit("; break :os_getenv_blk std.posix.getenv(_key) orelse ");
    if (args.len >= 2) {
        try self.genExpr(args[1]);
    } else {
        try self.emit("\"\"");
    }
    try self.emit("; }");
}

fn genRename(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("os_rename_blk: { const _old = ");
    try self.genExpr(args[0]);
    try self.emit("; const _new = ");
    try self.genExpr(args[1]);
    try self.emit("; std.fs.cwd().rename(_old, _new) catch {}; break :os_rename_blk {}; }");
}

fn genStat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("os_stat_blk: { const _path = ");
    try self.genExpr(args[0]);
    try self.emit("; const _stat = std.fs.cwd().statFile(_path) catch break :os_stat_blk struct { st_size: i64 = 0, st_mode: u32 = 0, st_ino: u64 = 0, st_mtime: i64 = 0, st_atime: i64 = 0, st_ctime: i64 = 0 }{}; break :os_stat_blk .{ .st_size = @intCast(_stat.size), .st_mode = @intCast(_stat.mode), .st_ino = _stat.inode, .st_mtime = @intCast(@divFloor(_stat.mtime, 1_000_000_000)), .st_atime = @intCast(@divFloor(_stat.atime, 1_000_000_000)), .st_ctime = @intCast(@divFloor(_stat.ctime, 1_000_000_000)) }; }");
}

fn genChmod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("os_chmod_blk: { const _path = ");
    try self.genExpr(args[0]);
    try self.emit("; const _mode: std.fs.File.Mode = @intCast(");
    try self.genExpr(args[1]);
    try self.emit("); const _f = std.fs.cwd().openFile(_path, .{}) catch break :os_chmod_blk {}; defer _f.close(); _f.chmod(_mode) catch {}; break :os_chmod_blk {}; }");
}

fn genAccess(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("os_access_blk: { const _p = ");
    try self.genExpr(args[0]);
    try self.emit("; _ = ");
    try self.genExpr(args[1]);
    try self.emit("; _ = std.fs.cwd().statFile(_p) catch break :os_access_blk false; break :os_access_blk true; }");
}

fn genTruncate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("os_truncate_blk: { const _p = ");
    try self.genExpr(args[0]);
    try self.emit("; const _len = @as(u64, @intCast(");
    try self.genExpr(args[1]);
    try self.emit(")); var _f = std.fs.cwd().openFile(_p, .{ .mode = .write_only }) catch break :os_truncate_blk {}; defer _f.close(); _f.setEndPos(_len) catch {}; break :os_truncate_blk {}; }");
}

fn genKill(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("os_kill_blk: { const _pid: std.posix.pid_t = @intCast(");
    try self.genExpr(args[0]);
    try self.emit("); const _sig: u6 = @intCast(");
    try self.genExpr(args[1]);
    try self.emit("); _ = std.posix.kill(_pid, _sig) catch {}; break :os_kill_blk {}; }");
}

fn genSystem(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("os_system_blk: { const _cmd = ");
    try self.genExpr(args[0]);
    try self.emit("; const _argv = [_][]const u8{ \"/bin/sh\", \"-c\", _cmd }; var _child = std.process.Child.init(.{ .argv = &_argv, .allocator = __global_allocator }); _ = _child.spawn() catch break :os_system_blk @as(i64, -1); const _r = _child.wait() catch break :os_system_blk @as(i64, -1); break :os_system_blk @as(i64, @intCast(_r.Exited)); }");
}

fn genDup2(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("@as(i64, @intCast(std.posix.dup2(@intCast(");
    try self.genExpr(args[0]);
    try self.emit("), @intCast(");
    try self.genExpr(args[1]);
    try self.emit(")) catch -1))");
}

fn genRead(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("os_read_blk: { const _fd = @as(std.posix.fd_t, @intCast(");
    try self.genExpr(args[0]);
    try self.emit(")); const _n = @as(usize, @intCast(");
    try self.genExpr(args[1]);
    try self.emit(")); var _buf = try __global_allocator.alloc(u8, _n); const _read = std.posix.read(_fd, _buf) catch 0; break :os_read_blk _buf[0.._read]; }");
}

fn genWrite(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("@as(i64, @intCast(std.posix.write(@intCast(");
    try self.genExpr(args[0]);
    try self.emit("), ");
    try self.genExpr(args[1]);
    try self.emit(") catch 0))");
}

fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("os_open_blk: { const _p = ");
    try self.genExpr(args[0]);
    try self.emit("; const _flags = @as(u32, @intCast(");
    try self.genExpr(args[1]);
    try self.emit(")); _ = _flags; const _f = std.fs.cwd().openFile(_p, .{}) catch break :os_open_blk @as(i64, -1); break :os_open_blk @as(i64, @intCast(_f.handle)); }");
}

fn genUrandom(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("os_urandom_blk: { const _n = @as(usize, @intCast(");
    try self.genExpr(args[0]);
    try self.emit(")); var _buf = try __global_allocator.alloc(u8, _n); std.crypto.random.bytes(_buf); break :os_urandom_blk _buf; }");
}

fn genWalk(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("os_walk_blk: { const _root = ");
    try self.genExpr(args[0]);
    try self.emit("; var _results: std.ArrayListUnmanaged(struct { []const u8, std.ArrayListUnmanaged([]const u8), std.ArrayListUnmanaged([]const u8) }) = .{}; var _dirs: std.ArrayListUnmanaged([]const u8) = .{}; _dirs.append(__global_allocator, _root) catch {}; while (_dirs.items.len > 0) { const _cur = _dirs.pop(); var _subdirs: std.ArrayListUnmanaged([]const u8) = .{}; var _files: std.ArrayListUnmanaged([]const u8) = .{}; var _dir = std.fs.cwd().openDir(_cur, .{ .iterate = true }) catch continue; defer _dir.close(); var _it = _dir.iterate(); while (_it.next() catch null) |_e| { const _name = __global_allocator.dupe(u8, _e.name) catch continue; if (_e.kind == .directory) { _subdirs.append(__global_allocator, _name) catch continue; const _full = std.fs.path.join(__global_allocator, &.{_cur, _name}) catch continue; _dirs.append(__global_allocator, _full) catch continue; } else { _files.append(__global_allocator, _name) catch continue; } } _results.append(__global_allocator, .{ _cur, _subdirs, _files }) catch continue; } break :os_walk_blk _results; }");
}

fn genScandir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("os_scandir_blk: { ");
    if (args.len >= 1) {
        try self.emit("const _dir_path = ");
        try self.genExpr(args[0]);
        try self.emit("; ");
    } else {
        try self.emit("const _dir_path = \".\"; ");
    }
    try self.emit("const DirEntry = struct { name: []const u8, path: []const u8, is_dir: bool, is_file: bool }; var _entries: std.ArrayListUnmanaged(DirEntry) = .{}; var _dir = std.fs.cwd().openDir(_dir_path, .{ .iterate = true }) catch break :os_scandir_blk _entries; defer _dir.close(); var _iter = _dir.iterate(); while (_iter.next() catch null) |entry| { const _name = __global_allocator.dupe(u8, entry.name) catch continue; const _path = std.fs.path.join(__global_allocator, &.{_dir_path, _name}) catch continue; _entries.append(__global_allocator, .{ .name = _name, .path = _path, .is_dir = entry.kind == .directory, .is_file = entry.kind == .file }) catch continue; } break :os_scandir_blk _entries; }");
}

fn genSymlink(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("os_symlink_blk: { const _src = ");
    try self.genExpr(args[0]);
    try self.emit("; const _dst = ");
    try self.genExpr(args[1]);
    try self.emit("; std.fs.cwd().symLink(_src, _dst, .{}) catch {}; break :os_symlink_blk {}; }");
}

fn genReadlink(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("os_readlink_blk: { const _p = ");
    try self.genExpr(args[0]);
    try self.emit("; var _buf: [4096]u8 = undefined; break :os_readlink_blk std.fs.cwd().readLink(_p, &_buf) catch \"\"; }");
}

fn genIslink(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("os_islink_blk: { const _p = ");
    try self.genExpr(args[0]);
    try self.emit("; const _s = std.fs.cwd().statFile(_p) catch break :os_islink_blk false; break :os_islink_blk _s.kind == .sym_link; }");
}

// === os.path handlers ===

fn genPathExists(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("os_path_exists_blk: { const _path = ");
    try self.genExpr(args[0]);
    try self.emit("; _ = std.fs.cwd().statFile(_path) catch { _ = std.fs.cwd().openDir(_path, .{}) catch break :os_path_exists_blk false; break :os_path_exists_blk true; }; break :os_path_exists_blk true; }");
}

fn genPathIsdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("os_path_isdir_blk: { const _path = ");
    try self.genExpr(args[0]);
    try self.emit("; var _dir = std.fs.cwd().openDir(_path, .{}) catch break :os_path_isdir_blk false; _dir.close(); break :os_path_isdir_blk true; }");
}

fn genPathIsfile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("os_path_isfile_blk: { const _path = ");
    try self.genExpr(args[0]);
    try self.emit("; const _stat = std.fs.cwd().statFile(_path) catch break :os_path_isfile_blk false; _ = _stat; break :os_path_isfile_blk true; }");
}

fn genPathAbspath(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("os_path_abspath_blk: { const _path = ");
    try self.genExpr(args[0]);
    try self.emit("; const _cwd = std.process.getCwdAlloc(__global_allocator) catch break :os_path_abspath_blk _path; break :os_path_abspath_blk std.fs.path.join(__global_allocator, &[_][]const u8{_cwd, _path}) catch _path; }");
}

fn genPathJoin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("\"\"");
        return;
    }
    if (args.len == 1) {
        try self.genExpr(args[0]);
        return;
    }
    try self.emit("os_path_join_blk: { const _paths = [_][]const u8{ ");
    for (args, 0..) |arg, i| {
        try self.genExpr(arg);
        if (i < args.len - 1) try self.emit(", ");
    }
    try self.emit(" }; break :os_path_join_blk std.fs.path.join(__global_allocator, &_paths) catch \"\"; }");
}

fn genPathSplit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("os_path_split_blk: { const _path = ");
    try self.genExpr(args[0]);
    try self.emit("; const _dirname = std.fs.path.dirname(_path) orelse \"\"; const _basename = std.fs.path.basename(_path); break :os_path_split_blk .{ .@\"0\" = _dirname, .@\"1\" = _basename }; }");
}

fn genPathSplitext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("os_path_splitext_blk: { const _path = ");
    try self.genExpr(args[0]);
    try self.emit("; const _ext = std.fs.path.extension(_path); const _root = if (_ext.len > 0) _path[0.._path.len - _ext.len] else _path; break :os_path_splitext_blk .{ .@\"0\" = _root, .@\"1\" = _ext }; }");
}

fn genPathGetsize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("os_path_getsize_blk: { const _path = ");
    try self.genExpr(args[0]);
    try self.emit("; const _stat = std.fs.cwd().statFile(_path) catch break :os_path_getsize_blk @as(i64, 0); break :os_path_getsize_blk @as(i64, @intCast(_stat.size)); }");
}
