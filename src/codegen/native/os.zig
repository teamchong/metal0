/// OS module - os.getcwd(), os.chdir(), os.listdir(), os.path.exists(), os.path.join() code generation
/// MIGRATED TO ZIGBUILDER
///
/// NOTE: All handlers use Zig stdlib directly (std.fs, std.process, std.posix).
/// No runtime.os module exists - these generate inline Zig code, not runtime calls.
const std = @import("std");
const ast = @import("analysis.ast");
const m = @import("mod_helper.zig");
const CodegenError = m.CodegenError;
const NativeCodegen = m.NativeCodegen;
const H = m.H;

// === Comptime helper generators for OS-specific patterns ===

/// Generate os_X_blk: { const _path = toPathStr(@TypeOf(arg), arg); ...body...; break :os_X_blk result; }
/// Uses callback pattern for automatic semicolon handling
/// Note: Uses toPathStr to handle PyValue args from eval() - extracts string from any type
fn pathBlock(comptime name: []const u8, comptime body: []const u8, comptime result: []const u8) H {
    return struct {
        fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
            // os.path operations require at least 1 argument
            if (args.len == 0) return error.UnsupportedSyntax;
            try self.withInlineBlock(name, args, struct {
                fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                    // Use toPathStr to extract path string from any type (including PyValue from eval)
                    try c.emit("const _path = runtime.container_dispatch.toPathStr(@TypeOf(");
                    try c.genExpr(a[0]);
                    try c.emit("), ");
                    try c.genExpr(a[0]);
                    try c.emit("); " ++ body);
                    try c.emitFmt("break :{s} " ++ result, .{label});
                }
            }.emit);
        }
    }.f;
}

/// Generate simple void-returning path operation
fn pathVoid(comptime name: []const u8, comptime op: []const u8) H {
    // Note: {{}} is escaped to produce {} in output
    return pathBlock(name, op ++ " catch {{}}; ", "{{}}");
}

/// Generate os_X_blk: { const _builtin = @import("builtin"); break :os_X_blk switch(_builtin.os.tag) { .windows => win, else => posix }; }
/// Uses callback pattern for automatic semicolon handling
fn osSwitch(comptime name: []const u8, comptime win: []const u8, comptime posix: []const u8) H {
    return struct {
        fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
            try self.withInlineBlock(name, args, struct {
                fn emit(c: *NativeCodegen, label: []const u8, _: []ast.Node) !void {
                    try c.emitFmt("const _builtin = @import(\"builtin\"); break :{s} switch (_builtin.os.tag) {{ .windows => " ++ win ++ ", else => " ++ posix ++ " }}", .{label});
                }
            }.emit);
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
    .{ "pipe", genPipe },
    .{ "fdopen", genFdopen },
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
    .{ "isabs", pathBlock("path_isabs", "", "_path.len > 0 and _path[0] == '/'") },
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
    try self.withInlineBlock("listdir", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            if (a.len >= 1) {
                try c.emit("const _dir_path = ");
                try c.genExpr(a[0]);
                try c.emit("; ");
            } else {
                try c.emit("const _dir_path = \".\"; ");
            }
            try c.emitFmt("var _entries: std.ArrayListUnmanaged([]const u8) = .{{}}; var _dir = std.fs.cwd().openDir(_dir_path, .{{ .iterate = true }}) catch break :{s} _entries; defer _dir.close(); var _iter = _dir.iterate(); while (_iter.next() catch null) |entry| {{ const _name = __global_allocator.dupe(u8, entry.name) catch continue; _entries.append(__global_allocator, _name) catch continue; }} break :{s} _entries", .{ label, label });
        }
    }.emit);
}

fn genGetenv(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // os.getenv() requires at least 1 argument
    if (args.len == 0) return error.UnsupportedSyntax;
    try self.withInlineBlock("getenv", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            // Note: std.posix.getenv unavailable on Windows - use comptime check
            try c.emit("const _key = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; _ = _key; break :{s} if (comptime @import(\"builtin\").os.tag == .windows) @as(?[]const u8, ", .{label});
            if (a.len >= 2) {
                try c.genExpr(a[1]);
            } else {
                try c.emit("null");
            }
            try c.emit(") else (std.posix.getenv(_key) orelse ");
            if (a.len >= 2) {
                try c.genExpr(a[1]);
            } else {
                try c.emit("\"\"");
            }
            try c.emit(")");
        }
    }.emit);
}

fn genRename(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // os.rename() requires 2 arguments
    if (args.len < 2) return error.UnsupportedSyntax;
    try self.withInlineBlock("rename", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _old = ");
            try c.genExpr(a[0]);
            try c.emit("; const _new = ");
            try c.genExpr(a[1]);
            try c.emitFmt("; std.fs.cwd().rename(_old, _new) catch {{}}; break :{s} {{}}", .{label});
        }
    }.emit);
}

fn genStat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // os.stat() requires 1 argument
    if (args.len == 0) return error.UnsupportedSyntax;
    try self.withInlineBlock("stat", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _path = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; const _stat = std.fs.cwd().statFile(_path) catch break :{s} struct {{ st_size: i64 = 0, st_mode: u32 = 0, st_ino: u64 = 0, st_mtime: i64 = 0, st_atime: i64 = 0, st_ctime: i64 = 0 }}{{}}; break :{s} .{{ .st_size = @as(i64, @intCast(_stat.size)), .st_mode = @as(u32, @intCast(_stat.mode)), .st_ino = _stat.inode, .st_mtime = @as(i64, @intCast(@divFloor(_stat.mtime, 1_000_000_000))), .st_atime = @as(i64, @intCast(@divFloor(_stat.atime, 1_000_000_000))), .st_ctime = @as(i64, @intCast(@divFloor(_stat.ctime, 1_000_000_000))) }}", .{ label, label });
        }
    }.emit);
}

fn genChmod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // os.chmod() requires 2 arguments
    if (args.len < 2) return error.UnsupportedSyntax;
    try self.withInlineBlock("chmod", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _path = ");
            try c.genExpr(a[0]);
            try c.emit("; const _mode: std.fs.File.Mode = @intCast(");
            try c.genExpr(a[1]);
            try c.emitFmt("); const _f = std.fs.cwd().openFile(_path, .{{}}) catch break :{s} {{}}; defer _f.close(); _f.chmod(_mode) catch {{}}; break :{s} {{}}", .{ label, label });
        }
    }.emit);
}

fn genAccess(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // os.access() requires 2 arguments
    if (args.len < 2) return error.UnsupportedSyntax;
    try self.withInlineBlock("access", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _p = ");
            try c.genExpr(a[0]);
            try c.emit("; _ = ");
            try c.genExpr(a[1]);
            try c.emitFmt("; _ = std.fs.cwd().statFile(_p) catch break :{s} false; break :{s} true", .{ label, label });
        }
    }.emit);
}

fn genTruncate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return error.UnsupportedSyntax;
    try self.withInlineBlock("truncate", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _p = ");
            try c.genExpr(a[0]);
            try c.emit("; const _len = @as(u64, @intCast(");
            try c.genExpr(a[1]);
            try c.emitFmt(")); var _f = std.fs.cwd().openFile(_p, .{{ .mode = .write_only }}) catch break :{s} {{}}; defer _f.close(); _f.setEndPos(_len) catch {{}}; break :{s} {{}}", .{ label, label });
        }
    }.emit);
}

fn genKill(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return error.UnsupportedSyntax;
    try self.withInlineBlock("kill", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _pid: std.posix.pid_t = @intCast(");
            try c.genExpr(a[0]);
            try c.emit("); const _sig: u6 = @intCast(");
            try c.genExpr(a[1]);
            try c.emitFmt("); _ = std.posix.kill(_pid, _sig) catch {{}}; break :{s} {{}}", .{label});
        }
    }.emit);
}

fn genSystem(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return error.UnsupportedSyntax;
    try self.withInlineBlock("system", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _cmd = ");
            try c.genExpr(a[0]);
            try c.emit("; const _argv = [_][]const u8{ \"/bin/sh\", \"-c\", _cmd }; var _child = std.process.Child.init(.{ .argv = &_argv, .allocator = __global_allocator }); ");
            try c.emitFmt("_ = _child.spawn() catch break :{s} @as(i64, -1); ", .{label});
            try c.emitFmt("const _r = _child.wait() catch break :{s} @as(i64, -1); ", .{label});
            try c.emitFmt("break :{s} @as(i64, @intCast(_r.Exited))", .{label});
        }
    }.emit);
}

fn genDup2(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return error.UnsupportedSyntax;
    try self.emit("@as(i64, @intCast(std.posix.dup2(@intCast(");
    try self.genExpr(args[0]);
    try self.emit("), @intCast(");
    try self.genExpr(args[1]);
    try self.emit(")) catch -1))");
}

fn genRead(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return error.UnsupportedSyntax;
    try self.withInlineBlock("read", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _fd = @as(std.posix.fd_t, @intCast(");
            try c.genExpr(a[0]);
            try c.emit(")); const _n = @as(usize, @intCast(");
            try c.genExpr(a[1]);
            try c.emitFmt(")); var _buf = try __global_allocator.alloc(u8, _n); const _read = std.posix.read(_fd, _buf) catch 0; break :{s} _buf[0.._read]", .{label});
        }
    }.emit);
}

fn genWrite(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return error.UnsupportedSyntax;
    try self.emit("@as(i64, @intCast(std.posix.write(@intCast(");
    try self.genExpr(args[0]);
    try self.emit("), ");
    try self.genExpr(args[1]);
    try self.emit(") catch 0))");
}

fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return error.UnsupportedSyntax;
    try self.withInlineBlock("open", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _p = ");
            try c.genExpr(a[0]);
            try c.emit("; const _flags = @as(u32, @intCast(");
            try c.genExpr(a[1]);
            try c.emitFmt(")); _ = _flags; const _f = std.fs.cwd().openFile(_p, .{{}}) catch break :{s} @as(i64, -1); break :{s} if (comptime @import(\"builtin\").os.tag == .windows) @as(i64, @intFromPtr(_f.handle)) else @as(i64, @intCast(_f.handle))", .{ label, label });
        }
    }.emit);
}

fn genPipe(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.withInlineBlock("pipe", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, _: []ast.Node) !void {
            try c.emitFmt("const _p = std.posix.pipe() catch break :{s} .{{ @as(i64, -1), @as(i64, -1) }}; break :{s} .{{ @as(i64, @intCast(_p[0])), @as(i64, @intCast(_p[1])) }}", .{ label, label });
        }
    }.emit);
}

fn genFdopen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("std.io.getStdIn()");
        return;
    }
    try self.withInlineBlock("fdopen", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _fd_int: i64 = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; const _builtin = @import(\"builtin\"); const _handle = if (comptime _builtin.os.tag == .windows) @as(*anyopaque, @ptrFromInt(@as(usize, @intCast(_fd_int)))) else @as(std.posix.fd_t, @intCast(_fd_int)); break :{s} std.fs.File{{ .handle = _handle }}", .{label});
        }
    }.emit);
}

fn genUrandom(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return error.UnsupportedSyntax;
    try self.withInlineBlock("urandom", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _n = @as(usize, @intCast(");
            try c.genExpr(a[0]);
            try c.emitFmt(")); var _buf = try __global_allocator.alloc(u8, _n); std.crypto.random.bytes(_buf); break :{s} _buf", .{label});
        }
    }.emit);
}

fn genWalk(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return error.UnsupportedSyntax;
    try self.withInlineBlock("walk", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _root = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; var _results: std.ArrayListUnmanaged(struct {{ []const u8, std.ArrayListUnmanaged([]const u8), std.ArrayListUnmanaged([]const u8) }}) = .{{}}; var _dirs: std.ArrayListUnmanaged([]const u8) = .{{}}; _dirs.append(__global_allocator, _root) catch unreachable; while (_dirs.items.len > 0) {{ const _cur = _dirs.pop(); var _subdirs: std.ArrayListUnmanaged([]const u8) = .{{}}; var _files: std.ArrayListUnmanaged([]const u8) = .{{}}; var _dir = std.fs.cwd().openDir(_cur, .{{ .iterate = true }}) catch continue; defer _dir.close(); var _it = _dir.iterate(); while (_it.next() catch null) |_e| {{ const _name = __global_allocator.dupe(u8, _e.name) catch continue; if (_e.kind == .directory) {{ _subdirs.append(__global_allocator, _name) catch unreachable; const _full = std.fs.path.join(__global_allocator, &.{{_cur, _name}}) catch continue; _dirs.append(__global_allocator, _full) catch unreachable; }} else {{ _files.append(__global_allocator, _name) catch unreachable; }} }} _results.append(__global_allocator, .{{ _cur, _subdirs, _files }}) catch unreachable; }} break :{s} _results", .{label});
        }
    }.emit);
}

fn genScandir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.withInlineBlock("scandir", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            if (a.len >= 1) {
                try c.emit("const _dir_path = ");
                try c.genExpr(a[0]);
                try c.emit("; ");
            } else {
                try c.emit("const _dir_path = \".\"; ");
            }
            try c.emitFmt("const DirEntry = struct {{ name: []const u8, path: []const u8, is_dir: bool, is_file: bool }}; var _entries: std.ArrayListUnmanaged(DirEntry) = .{{}}; var _dir = std.fs.cwd().openDir(_dir_path, .{{ .iterate = true }}) catch break :{s} _entries; defer _dir.close(); var _iter = _dir.iterate(); while (_iter.next() catch null) |entry| {{ const _name = __global_allocator.dupe(u8, entry.name) catch continue; const _path = std.fs.path.join(__global_allocator, &.{{_dir_path, _name}}) catch continue; _entries.append(__global_allocator, .{{ .name = _name, .path = _path, .is_dir = entry.kind == .directory, .is_file = entry.kind == .file }}) catch continue; }} break :{s} _entries", .{ label, label });
        }
    }.emit);
}

fn genSymlink(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return error.UnsupportedSyntax;
    try self.withInlineBlock("symlink", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _src = ");
            try c.genExpr(a[0]);
            try c.emit("; const _dst = ");
            try c.genExpr(a[1]);
            try c.emitFmt("; std.fs.cwd().symLink(_src, _dst, .{{}}) catch {{}}; break :{s} {{}}", .{label});
        }
    }.emit);
}

fn genReadlink(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return error.UnsupportedSyntax;
    try self.withInlineBlock("readlink", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _p = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; var _buf: [4096]u8 = undefined; break :{s} std.fs.cwd().readLink(_p, &_buf) catch \"\"", .{label});
        }
    }.emit);
}

fn genIslink(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return error.UnsupportedSyntax;
    try self.withInlineBlock("islink", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _p = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; const _s = std.fs.cwd().statFile(_p) catch break :{s} false; break :{s} _s.kind == .sym_link", .{ label, label });
        }
    }.emit);
}

// === os.path handlers ===

fn genPathExists(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return error.UnsupportedSyntax;
    try self.withInlineBlock("path_exists", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _path = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; _ = std.fs.cwd().statFile(_path) catch {{ _ = std.fs.cwd().openDir(_path, .{{}}) catch break :{s} false; break :{s} true; }}; break :{s} true", .{ label, label, label });
        }
    }.emit);
}

fn genPathIsdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return error.UnsupportedSyntax;
    try self.withInlineBlock("path_isdir", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _path = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; var _dir = std.fs.cwd().openDir(_path, .{{}}) catch break :{s} false; _dir.close(); break :{s} true", .{ label, label });
        }
    }.emit);
}

fn genPathIsfile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return error.UnsupportedSyntax;
    try self.withInlineBlock("path_isfile", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _path = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; const _stat = std.fs.cwd().statFile(_path) catch break :{s} false; _ = _stat; break :{s} true", .{ label, label });
        }
    }.emit);
}

fn genPathAbspath(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return error.UnsupportedSyntax;
    try self.withInlineBlock("path_abspath", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _path = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; const _cwd = std.process.getCwdAlloc(__global_allocator) catch break :{s} _path; break :{s} std.fs.path.join(__global_allocator, &[_][]const u8{{_cwd, _path}}) catch _path", .{ label, label });
        }
    }.emit);
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
    try self.withInlineBlock("path_join", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _paths = [_][]const u8{ ");
            for (a, 0..) |arg, i| {
                try c.genExpr(arg);
                if (i < a.len - 1) try c.emit(", ");
            }
            try c.emitFmt(" }}; break :{s} std.fs.path.join(__global_allocator, &_paths) catch \"\"", .{label});
        }
    }.emit);
}

fn genPathSplit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return error.UnsupportedSyntax;
    try self.withInlineBlock("path_split", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _path = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; const _dirname = std.fs.path.dirname(_path) orelse \"\"; const _basename = std.fs.path.basename(_path); break :{s} .{{ .@\"0\" = _dirname, .@\"1\" = _basename }}", .{label});
        }
    }.emit);
}

fn genPathSplitext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return error.UnsupportedSyntax;
    try self.withInlineBlock("path_splitext", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _path = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; const _ext = std.fs.path.extension(_path); const _root = if (_ext.len > 0) _path[0.._path.len - _ext.len] else _path; break :{s} .{{ .@\"0\" = _root, .@\"1\" = _ext }}", .{label});
        }
    }.emit);
}

fn genPathGetsize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return error.UnsupportedSyntax;
    try self.withInlineBlock("path_getsize", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const _path = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; const _stat = std.fs.cwd().statFile(_path) catch break :{s} @as(i64, 0); break :{s} @as(i64, @intCast(_stat.size))", .{ label, label });
        }
    }.emit);
}
