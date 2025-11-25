/// OS module - os.getcwd(), os.chdir(), os.listdir(), os.path.exists(), os.path.join() code generation
const std = @import("std");
const ast = @import("../../ast.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate code for os.getcwd()
/// Returns current working directory as PyString
pub fn genGetcwd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 0) {
        std.debug.print("os.getcwd() takes no arguments\n", .{});
        return;
    }

    // Use Zig's std.process.getCwdAlloc, wrap in PyString for Python compatibility
    try self.output.appendSlice(self.allocator, "os_getcwd_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "const _cwd = std.process.getCwdAlloc(allocator) catch \"\";\n");
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "break :os_getcwd_blk try runtime.PyString.create(allocator, _cwd);\n");
    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for os.chdir(path)
/// Changes current working directory, returns None
pub fn genChdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        std.debug.print("os.chdir() requires exactly 1 argument\n", .{});
        return;
    }

    // std.posix.chdir returns void on success, error on failure
    try self.output.appendSlice(self.allocator, "os_chdir_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "const _path = ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "std.posix.chdir(_path) catch {};\n");
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "break :os_chdir_blk {};\n");
    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for os.listdir(path)
/// Returns list of entries in directory as ArrayList
pub fn genListdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // os.listdir() can take 0 or 1 argument
    if (args.len > 1) {
        std.debug.print("os.listdir() takes at most 1 argument\n", .{});
        return;
    }

    try self.output.appendSlice(self.allocator, "os_listdir_blk: {\n");
    self.indent();
    try self.emitIndent();

    // Get path argument or use "." for current directory
    if (args.len == 1) {
        try self.output.appendSlice(self.allocator, "const _dir_path = ");
        try self.genExpr(args[0]);
        try self.output.appendSlice(self.allocator, ";\n");
    } else {
        try self.output.appendSlice(self.allocator, "const _dir_path = \".\";\n");
    }

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "var _entries = std.ArrayList([]const u8).init(allocator);\n");
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "var _dir = std.fs.cwd().openDir(_dir_path, .{ .iterate = true }) catch {\n");
    self.indent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "break :os_listdir_blk _entries;\n");
    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "};\n");
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "defer _dir.close();\n");
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "var _iter = _dir.iterate();\n");
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "while (_iter.next() catch null) |entry| {\n");
    self.indent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "const _name = allocator.dupe(u8, entry.name) catch continue;\n");
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "_entries.append(allocator, _name) catch continue;\n");
    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}\n");
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "break :os_listdir_blk _entries;\n");
    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for os.path.exists(path)
/// Returns True if path exists
pub fn genPathExists(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        std.debug.print("os.path.exists() requires exactly 1 argument\n", .{});
        return;
    }

    // Use std.fs.cwd().access() to check if path exists
    try self.output.appendSlice(self.allocator, "os_path_exists_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "const _path = ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "_ = std.fs.cwd().statFile(_path) catch {\n");
    self.indent();
    try self.emitIndent();
    // Try as directory
    try self.output.appendSlice(self.allocator, "_ = std.fs.cwd().openDir(_path, .{}) catch {\n");
    self.indent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "break :os_path_exists_blk false;\n");
    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "};\n");
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "break :os_path_exists_blk true;\n");
    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "};\n");
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "break :os_path_exists_blk true;\n");
    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for os.path.join(a, b, ...)
/// Joins path components with separator, returns PyString
pub fn genPathJoin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        std.debug.print("os.path.join() requires at least 2 arguments\n", .{});
        return;
    }

    try self.output.appendSlice(self.allocator, "os_path_join_blk: {\n");
    self.indent();
    try self.emitIndent();

    // Build array of paths
    try self.output.appendSlice(self.allocator, "const _paths = [_][]const u8{ ");
    for (args, 0..) |arg, i| {
        try self.genExpr(arg);
        if (i < args.len - 1) {
            try self.output.appendSlice(self.allocator, ", ");
        }
    }
    try self.output.appendSlice(self.allocator, " };\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "const _joined = std.fs.path.join(allocator, &_paths) catch \"\";\n");
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "break :os_path_join_blk try runtime.PyString.create(allocator, _joined);\n");
    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for os.path.dirname(path)
/// Returns directory component of path as PyString
pub fn genPathDirname(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        std.debug.print("os.path.dirname() requires exactly 1 argument\n", .{});
        return;
    }

    try self.output.appendSlice(self.allocator, "os_path_dirname_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "const _path = ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "const _dirname = std.fs.path.dirname(_path) orelse \"\";\n");
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "break :os_path_dirname_blk try runtime.PyString.create(allocator, _dirname);\n");
    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate code for os.path.basename(path)
/// Returns final component of path as PyString
pub fn genPathBasename(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        std.debug.print("os.path.basename() requires exactly 1 argument\n", .{});
        return;
    }

    try self.output.appendSlice(self.allocator, "os_path_basename_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "const _path = ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "break :os_path_basename_blk try runtime.PyString.create(allocator, std.fs.path.basename(_path));\n");
    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}");
}
