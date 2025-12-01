/// OS module - os.getcwd(), os.chdir(), os.listdir(), os.path.exists(), os.path.join() code generation
///
/// NOTE: All handlers use Zig stdlib directly (std.fs, std.process, std.posix).
/// No runtime.os module exists - these generate inline Zig code, not runtime calls.
/// Bridge pattern doesn't apply here since there's nothing to passthrough to.
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;
// const bridge = @import("stdlib_bridge.zig"); // Future: for any runtime passthrough functions

/// Handler function type
const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;

/// Module function map - exported for dispatch
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "getcwd", genGetcwd },
    .{ "chdir", genChdir },
    .{ "listdir", genListdir },
    .{ "getenv", genGetenv },
    .{ "mkdir", genMkdir },
    .{ "makedirs", genMakedirs },
    .{ "name", genName },
    .{ "curdir", genCurdir },
    .{ "pardir", genPardir },
    .{ "sep", genSep },
    .{ "remove", genRemove },
    .{ "unlink", genUnlink },
    .{ "rename", genRename },
    .{ "rmdir", genRmdir },
    .{ "removedirs", genRemovedirs },
    .{ "stat", genStat },
    .{ "environ", genEnviron },
    .{ "linesep", genLinesep },
    .{ "altsep", genAltsep },
    .{ "extsep", genExtsep },
    .{ "pathsep", genPathsep },
    .{ "devnull", genDevnull },
});

/// OS.path module functions
pub const PathFuncs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "exists", genPathExists },
    .{ "isdir", genPathIsdir },
    .{ "isfile", genPathIsfile },
    .{ "abspath", genPathAbspath },
    .{ "join", genPathJoin },
    .{ "dirname", genPathDirname },
    .{ "basename", genPathBasename },
    .{ "split", genPathSplit },
    .{ "splitext", genPathSplitext },
    .{ "getsize", genPathGetsize },
});

/// Generate code for os.getcwd()
/// Returns current working directory as []const u8
pub fn genGetcwd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 0) {
        std.debug.print("os.getcwd() takes no arguments\n", .{});
        return;
    }

    // Use Zig's std.process.getCwdAlloc, returns []const u8
    try self.emit("(std.process.getCwdAlloc(__global_allocator) catch \"\")");
}

/// Generate code for os.chdir(path)
/// Changes current working directory, returns None
pub fn genChdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        std.debug.print("os.chdir() requires exactly 1 argument\n", .{});
        return;
    }

    // std.posix.chdir returns void on success, error on failure
    try self.emit("os_chdir_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _path = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("std.posix.chdir(_path) catch {};\n");
    try self.emitIndent();
    try self.emit("break :os_chdir_blk {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate code for os.listdir(path)
/// Returns list of entries in directory as ArrayList
pub fn genListdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // os.listdir() can take 0 or 1 argument
    if (args.len > 1) {
        std.debug.print("os.listdir() takes at most 1 argument\n", .{});
        return;
    }

    try self.emit("os_listdir_blk: {\n");
    self.indent();
    try self.emitIndent();

    // Get path argument or use "." for current directory
    if (args.len == 1) {
        try self.emit("const _dir_path = ");
        try self.genExpr(args[0]);
        try self.emit(";\n");
    } else {
        try self.emit("const _dir_path = \".\";\n");
    }

    try self.emitIndent();
    try self.emit("var _entries: std.ArrayList([]const u8) = .{};\n");
    try self.emitIndent();
    try self.emit("var _dir = std.fs.cwd().openDir(_dir_path, .{ .iterate = true }) catch {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("break :os_listdir_blk _entries;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");
    try self.emitIndent();
    try self.emit("defer _dir.close();\n");
    try self.emitIndent();
    try self.emit("var _iter = _dir.iterate();\n");
    try self.emitIndent();
    try self.emit("while (_iter.next() catch null) |entry| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _name = allocator.dupe(u8, entry.name) catch continue;\n");
    try self.emitIndent();
    try self.emit("_entries.append(__global_allocator, _name) catch continue;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :os_listdir_blk _entries;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate code for os.path.exists(path)
/// Returns True if path exists
pub fn genPathExists(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        std.debug.print("os.path.exists() requires exactly 1 argument\n", .{});
        return;
    }

    // Use std.fs.cwd().access() to check if path exists
    try self.emit("os_path_exists_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _path = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("_ = std.fs.cwd().statFile(_path) catch {\n");
    self.indent();
    try self.emitIndent();
    // Try as directory
    try self.emit("_ = std.fs.cwd().openDir(_path, .{}) catch {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("break :os_path_exists_blk false;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");
    try self.emitIndent();
    try self.emit("break :os_path_exists_blk true;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");
    try self.emitIndent();
    try self.emit("break :os_path_exists_blk true;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate code for os.path.join(a, b, ...)
/// Joins path components with separator, returns []const u8
pub fn genPathJoin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        std.debug.print("os.path.join() requires at least 2 arguments\n", .{});
        return;
    }

    try self.emit("os_path_join_blk: {\n");
    self.indent();
    try self.emitIndent();

    // Build array of paths
    try self.emit("const _paths = [_][]const u8{ ");
    for (args, 0..) |arg, i| {
        try self.genExpr(arg);
        if (i < args.len - 1) {
            try self.emit(", ");
        }
    }
    try self.emit(" };\n");

    try self.emitIndent();
    try self.emit("break :os_path_join_blk std.fs.path.join(__global_allocator, &_paths) catch \"\";\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate code for os.path.dirname(path)
/// Returns directory component of path as []const u8
pub fn genPathDirname(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        std.debug.print("os.path.dirname() requires exactly 1 argument\n", .{});
        return;
    }

    try self.emit("os_path_dirname_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _path = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("break :os_path_dirname_blk std.fs.path.dirname(_path) orelse \"\";\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate code for os.path.basename(path)
/// Returns final component of path as []const u8
pub fn genPathBasename(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        std.debug.print("os.path.basename() requires exactly 1 argument\n", .{});
        return;
    }

    try self.emit("os_path_basename_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _path = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("break :os_path_basename_blk std.fs.path.basename(_path);\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate code for os.curdir constant
/// Returns "." (current directory)
pub fn genCurdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\".\"");
}

/// Generate code for os.pardir constant
/// Returns ".." (parent directory)
pub fn genPardir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"..\"");
}

/// Generate code for os.sep constant
/// Returns path separator
pub fn genSep(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"/\"");
}

/// Generate code for os.getenv(key, default=None)
/// Returns environment variable value or default
pub fn genGetenv(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1 or args.len > 2) {
        std.debug.print("os.getenv() requires 1 or 2 arguments\n", .{});
        return;
    }

    try self.emit("os_getenv_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _key = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("break :os_getenv_blk std.posix.getenv(_key) orelse ");
    if (args.len == 2) {
        try self.genExpr(args[1]);
    } else {
        try self.emit("\"\"");
    }
    try self.emit(";\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate code for os.mkdir(path, mode=0o777)
/// Creates a single directory
pub fn genMkdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1 or args.len > 2) {
        std.debug.print("os.mkdir() requires 1 or 2 arguments\n", .{});
        return;
    }

    try self.emit("os_mkdir_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _path = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("std.fs.cwd().makeDir(_path) catch {};\n");
    try self.emitIndent();
    try self.emit("break :os_mkdir_blk {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate code for os.makedirs(path, mode=0o777, exist_ok=False)
/// Creates directories recursively
pub fn genMakedirs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1 or args.len > 3) {
        std.debug.print("os.makedirs() requires 1 to 3 arguments\n", .{});
        return;
    }

    try self.emit("os_makedirs_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _path = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("std.fs.cwd().makePath(_path) catch {};\n");
    try self.emitIndent();
    try self.emit("break :os_makedirs_blk {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate code for os.remove(path)
/// Removes a file
pub fn genRemove(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        std.debug.print("os.remove() requires exactly 1 argument\n", .{});
        return;
    }

    try self.emit("os_remove_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _path = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("std.fs.cwd().deleteFile(_path) catch {};\n");
    try self.emitIndent();
    try self.emit("break :os_remove_blk {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate code for os.rename(src, dst)
/// Renames a file or directory
pub fn genRename(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 2) {
        std.debug.print("os.rename() requires exactly 2 arguments\n", .{});
        return;
    }

    try self.emit("os_rename_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _old = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _new = ");
    try self.genExpr(args[1]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("std.fs.cwd().rename(_old, _new) catch {};\n");
    try self.emitIndent();
    try self.emit("break :os_rename_blk {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate code for os.rmdir(path)
/// Removes an empty directory
pub fn genRmdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        std.debug.print("os.rmdir() requires exactly 1 argument\n", .{});
        return;
    }

    try self.emit("os_rmdir_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _path = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("std.fs.cwd().deleteDir(_path) catch {};\n");
    try self.emitIndent();
    try self.emit("break :os_rmdir_blk {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate code for os.path.isdir(path)
/// Returns True if path is a directory
pub fn genPathIsdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        std.debug.print("os.path.isdir() requires exactly 1 argument\n", .{});
        return;
    }

    try self.emit("os_path_isdir_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _path = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _dir = std.fs.cwd().openDir(_path, .{}) catch break :os_path_isdir_blk false;\n");
    try self.emitIndent();
    try self.emit("_dir.close();\n");
    try self.emitIndent();
    try self.emit("break :os_path_isdir_blk true;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate code for os.path.isfile(path)
/// Returns True if path is a file
pub fn genPathIsfile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        std.debug.print("os.path.isfile() requires exactly 1 argument\n", .{});
        return;
    }

    try self.emit("os_path_isfile_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _path = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _stat = std.fs.cwd().statFile(_path) catch break :os_path_isfile_blk false;\n");
    try self.emitIndent();
    try self.emit("_ = _stat;\n");
    try self.emitIndent();
    try self.emit("break :os_path_isfile_blk true;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate code for os.path.abspath(path)
/// Returns absolute path
pub fn genPathAbspath(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        std.debug.print("os.path.abspath() requires exactly 1 argument\n", .{});
        return;
    }

    try self.emit("os_path_abspath_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _path = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _cwd = std.process.getCwdAlloc(__global_allocator) catch break :os_path_abspath_blk _path;\n");
    try self.emitIndent();
    try self.emit("break :os_path_abspath_blk std.fs.path.join(__global_allocator, &[_][]const u8{_cwd, _path}) catch _path;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate code for os.path.split(path)
/// Returns (head, tail) tuple where tail is final component
/// Python: os.path.split('/usr/bin') -> ('/usr', 'bin')
pub fn genPathSplit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        std.debug.print("os.path.split() requires exactly 1 argument\n", .{});
        return;
    }

    // Generate: struct { @"0": []const u8, @"1": []const u8 } { .@"0" = dirname(path), .@"1" = basename(path) }
    try self.emit("os_path_split_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _path = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _dirname = std.fs.path.dirname(_path) orelse \"\";\n");
    try self.emitIndent();
    try self.emit("const _basename = std.fs.path.basename(_path);\n");
    try self.emitIndent();
    // Return as a struct with numeric field names for tuple-like access
    try self.emit("break :os_path_split_blk .{ .@\"0\" = _dirname, .@\"1\" = _basename };\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate code for os.name
/// Returns 'posix', 'nt', or 'java' based on the operating system
pub fn genName(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args; // os.name is a constant, no arguments

    // Emit comptime code to detect OS and return appropriate name
    try self.emit("os_name_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _builtin = @import(\"builtin\");\n");
    try self.emitIndent();
    try self.emit("break :os_name_blk switch (_builtin.os.tag) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit(".windows => \"nt\",\n");
    try self.emitIndent();
    try self.emit("else => \"posix\",\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate code for os.unlink(path) - alias for os.remove
pub const genUnlink = genRemove;

/// Generate code for os.stat(path) - returns stat struct
pub fn genStat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        std.debug.print("os.stat() requires exactly 1 argument\n", .{});
        return;
    }

    try self.emit("os_stat_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _path = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _stat = std.fs.cwd().statFile(_path) catch break :os_stat_blk struct { st_size: i64 = 0, st_mode: u32 = 0, st_ino: u64 = 0, st_mtime: i64 = 0, st_atime: i64 = 0, st_ctime: i64 = 0 }{};\n");
    try self.emitIndent();
    try self.emit("break :os_stat_blk .{ .st_size = @intCast(_stat.size), .st_mode = @intCast(_stat.mode), .st_ino = _stat.inode, .st_mtime = @intCast(@divFloor(_stat.mtime, 1_000_000_000)), .st_atime = @intCast(@divFloor(_stat.atime, 1_000_000_000)), .st_ctime = @intCast(@divFloor(_stat.ctime, 1_000_000_000)) };\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate code for os.path.splitext(path) - split extension
pub fn genPathSplitext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        std.debug.print("os.path.splitext() requires exactly 1 argument\n", .{});
        return;
    }

    try self.emit("os_path_splitext_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _path = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _ext = std.fs.path.extension(_path);\n");
    try self.emitIndent();
    try self.emit("const _root = if (_ext.len > 0) _path[0.._path.len - _ext.len] else _path;\n");
    try self.emitIndent();
    try self.emit("break :os_path_splitext_blk .{ .@\"0\" = _root, .@\"1\" = _ext };\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate code for os.path.getsize(path) - get file size
pub fn genPathGetsize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        std.debug.print("os.path.getsize() requires exactly 1 argument\n", .{});
        return;
    }

    try self.emit("os_path_getsize_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _path = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _stat = std.fs.cwd().statFile(_path) catch break :os_path_getsize_blk @as(i64, 0);\n");
    try self.emitIndent();
    try self.emit("break :os_path_getsize_blk @as(i64, @intCast(_stat.size));\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate code for os.environ - environment variables dictionary
pub fn genEnviron(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("hashmap_helper.StringHashMap([]const u8).init(__global_allocator)");
}

/// Generate code for os.removedirs(path) - remove directories recursively
pub fn genRemovedirs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        std.debug.print("os.removedirs() requires exactly 1 argument\n", .{});
        return;
    }

    try self.emit("os_removedirs_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _path = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("std.fs.cwd().deleteTree(_path) catch {};\n");
    try self.emitIndent();
    try self.emit("break :os_removedirs_blk {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate code for os.linesep - line separator
pub fn genLinesep(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("os_linesep_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _builtin = @import(\"builtin\");\n");
    try self.emitIndent();
    try self.emit("break :os_linesep_blk switch (_builtin.os.tag) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit(".windows => \"\\r\\n\",\n");
    try self.emitIndent();
    try self.emit("else => \"\\n\",\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate code for os.altsep - alternate separator
pub fn genAltsep(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate code for os.extsep - extension separator
pub fn genExtsep(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\".\"");
}

/// Generate code for os.pathsep - path separator
pub fn genPathsep(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("os_pathsep_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _builtin = @import(\"builtin\");\n");
    try self.emitIndent();
    try self.emit("break :os_pathsep_blk switch (_builtin.os.tag) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit(".windows => \";\",\n");
    try self.emitIndent();
    try self.emit("else => \":\",\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate code for os.devnull - null device path
pub fn genDevnull(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("os_devnull_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _builtin = @import(\"builtin\");\n");
    try self.emitIndent();
    try self.emit("break :os_devnull_blk switch (_builtin.os.tag) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit(".windows => \"nul\",\n");
    try self.emitIndent();
    try self.emit("else => \"/dev/null\",\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}
