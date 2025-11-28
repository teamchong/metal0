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
    try self.emit("var _entries = std.ArrayList([]const u8).init(allocator);\n");
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
    try self.emit("_entries.append(allocator, _name) catch continue;\n");
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
    try self.emit("break :os_path_join_blk std.fs.path.join(allocator, &_paths) catch \"\";\n");
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
    try self.emit("}"
    );
}
