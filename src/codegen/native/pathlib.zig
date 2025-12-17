/// Pathlib module - pathlib.Path and all Path methods
const std = @import("std");
const ast = @import("analysis.ast");
const m = @import("mod_helper.zig");
const CodegenError = m.CodegenError;
const NativeCodegen = m.NativeCodegen;
const H = m.H;

/// Method handler type for Path methods (takes obj + args)
const MH = *const fn (*NativeCodegen, ast.Node, []ast.Node) CodegenError!void;

// === Comptime method generators ===

/// Generate method: __m{id}_label: { const _p = obj; ...body... }
fn methodBlock(comptime label: []const u8, comptime body: []const u8) MH {
    return struct {
        fn f(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
            _ = args;
            const id = self.nextNameId();
            try self.emitFmt("__m{d}_" ++ label ++ ": {{ const _p = ", .{id});
            try self.genExpr(obj);
            try self.emitFmt("; " ++ body ++ " }}", .{id});
        }
    }.f;
}

/// Generate method that returns bool based on condition
fn boolCheck(comptime label: []const u8, comptime check: []const u8, comptime fallback: []const u8) MH {
    // Note: methodBlock will generate unique ID and replace label references at runtime
    return struct {
        fn f(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
            _ = args;
            const id = self.nextNameId();
            try self.emitFmt("__m{d}_" ++ label ++ ": {{ const _p = ", .{id});
            try self.genExpr(obj);
            try self.emit("; " ++ check ++ " catch break :__m");
            try self.emitFmt("{d}_" ++ label ++ " " ++ fallback ++ "; break :__m{d}_" ++ label ++ " true; }}", .{ id, id });
        }
    }.f;
}

/// Generate method with one arg: __m{id}_label: { const _p = obj; const _arg = arg[0]; ...body... }
fn methodWithArg(comptime label: []const u8, comptime body: []const u8) MH {
    return struct {
        fn f(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
            if (args.len < 1) return error.UnsupportedSyntax;
            const id = self.nextNameId();
            try self.emitFmt("__m{d}_" ++ label ++ ": {{ const _p = ", .{id});
            try self.genExpr(obj);
            try self.emit("; const _arg = ");
            try self.genExpr(args[0]);
            try self.emitFmt("; " ++ body ++ " }}", .{id});
        }
    }.f;
}

/// Generate simple property: expr(obj)
fn prop(comptime pre: []const u8, comptime suf: []const u8) MH {
    return struct {
        fn f(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
            _ = args;
            try self.emit(pre);
            try self.genExpr(obj);
            try self.emit(suf);
        }
    }.f;
}

/// Generate void method: __m{id}_label: { const _p = obj; op catch {}; break :__m{id}_label {}; }
fn voidOp(comptime label: []const u8, comptime op: []const u8) MH {
    return struct {
        fn f(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
            _ = args;
            const id = self.nextNameId();
            try self.emitFmt("__m{d}_" ++ label ++ ": {{ const _p = ", .{id});
            try self.genExpr(obj);
            try self.emit("; " ++ op ++ " catch {{}}; break :__m");
            try self.emitFmt("{d}_" ++ label ++ " {{}}; }}", .{id});
        }
    }.f;
}

// === Module exports ===

pub const Funcs = std.StaticStringMap(H).initComptime(.{
    .{ "Path", m.pass("\".\"") },
    .{ "PurePath", m.pass("\".\"") },
    .{ "PosixPath", m.pass("\".\"") },
    .{ "WindowsPath", m.pass("\".\"") },
    .{ "PurePosixPath", m.pass("\".\"") },
    .{ "PureWindowsPath", m.pass("\".\"") },
});

pub const PathMethods = std.StaticStringMap(MH).initComptime(.{
    // Query methods
    .{ "exists", genPathExists },
    .{ "is_file", boolCheck("path_isfile", "_ = std.fs.cwd().statFile(_p)", "false") },
    .{ "is_dir", genPathIsDir },
    .{ "is_symlink", genPathIsSymlink },
    .{ "is_absolute", genPathIsAbsolute },
    // Reading
    .{ "read_text", genPathReadText },
    .{ "read_bytes", genPathReadBytes },
    // Writing
    .{ "write_text", genPathWrite },
    .{ "write_bytes", genPathWrite },
    // Directory ops
    .{ "iterdir", genPathIterdir },
    .{ "glob", genPathGlob },
    .{ "rglob", genPathRglob },
    .{ "mkdir", voidOp("path_mkdir", "std.fs.cwd().makePath(_p)") },
    .{ "rmdir", voidOp("path_rmdir", "std.fs.cwd().deleteDir(_p)") },
    // File ops
    .{ "unlink", voidOp("path_unlink", "std.fs.cwd().deleteFile(_p)") },
    .{ "rename", genPathRename },
    .{ "replace", genPathReplace },
    .{ "touch", genPathTouch },
    .{ "chmod", genPathChmod },
    .{ "stat", genPathStat },
    .{ "lstat", prop("", ".stat()") },
    // Path manipulation
    .{ "absolute", genPathAbsolute },
    .{ "resolve", genPathResolve },
    .{ "expanduser", genPathExpanduser },
    .{ "with_name", genPathWithName },
    .{ "with_suffix", genPathWithSuffix },
    .{ "with_stem", genPathWithStem },
    .{ "joinpath", genPathJoinpath },
    .{ "relative_to", genPathRelativeTo },
    // Properties
    .{ "name", prop("std.fs.path.basename(", ")") },
    .{ "stem", genPathStem },
    .{ "suffix", prop("std.fs.path.extension(", ")") },
    .{ "suffixes", genPathSuffixes },
    .{ "parent", prop("std.fs.path.dirname(", ") orelse \".\"") },
    .{ "parents", genPathParents },
    .{ "parts", genPathParts },
    .{ "anchor", genPathAnchor },
    .{ "as_posix", prop("", "") },
    .{ "open", genPathOpen },
});

// === Complex handlers ===

fn genPathWrite(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return error.UnsupportedSyntax;
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_path_write: {{ const _p = ", .{id});
    try self.genExpr(obj);
    try self.emit("; const _data = ");
    try self.genExpr(args[0]);
    try self.emitFmt("; const _f = std.fs.cwd().createFile(_p, .{{}}) catch break :__m{d}_path_write @as(usize, 0); defer _f.close(); break :__m{d}_path_write _f.write(_data) catch 0; }}", .{ id, id });
}

fn genPathRename(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return error.UnsupportedSyntax;
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_path_rename: {{ const _old = ", .{id});
    try self.genExpr(obj);
    try self.emit("; const _new = ");
    try self.genExpr(args[0]);
    try self.emitFmt("; std.fs.cwd().rename(_old, _new) catch {{}}; break :__m{d}_path_rename _new; }}", .{id});
}

fn genPathReplace(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return error.UnsupportedSyntax;
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_path_replace: {{ const _old = ", .{id});
    try self.genExpr(obj);
    try self.emit("; const _new = ");
    try self.genExpr(args[0]);
    try self.emitFmt("; std.fs.cwd().deleteFile(_new) catch {{}}; std.fs.cwd().rename(_old, _new) catch {{}}; break :__m{d}_path_replace _new; }}", .{id});
}

fn genPathChmod(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return error.UnsupportedSyntax;
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_path_chmod: {{ const _p = ", .{id});
    try self.genExpr(obj);
    try self.emit("; const _m: std.fs.File.Mode = @intCast(");
    try self.genExpr(args[0]);
    try self.emitFmt("); const _f = std.fs.cwd().openFile(_p, .{{}}) catch break :__m{d}_path_chmod {{}}; defer _f.close(); _f.chmod(_m) catch {{}}; break :__m{d}_path_chmod {{}}; }}", .{ id, id });
}

fn genPathJoinpath(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_path_join: {{ const _base = ", .{id});
    try self.genExpr(obj);
    try self.emit("; const _parts = [_][]const u8{ _base");
    for (args) |arg| {
        try self.emit(", ");
        try self.genExpr(arg);
    }
    try self.emitFmt(" }}; break :__m{d}_path_join std.fs.path.join(__global_allocator, &_parts) catch _base; }}", .{id});
}

/// Generate glob with actual pattern matching
fn genPathGlob(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_path_glob: {{ const _p = ", .{id});
    try self.genExpr(obj);
    try self.emit("; const _pattern = ");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"*\"");
    }
    try self.emit(
        \\; var _entries: std.ArrayList([]const u8) = .{};
        \\ var _d = std.fs.cwd().openDir(_p, .{ .iterate = true }) catch break :__m
    );
    try self.emitFmt("{d}_path_glob _entries;", .{id});
    try self.emit(
        \\ defer _d.close();
        \\ var _it = _d.iterate();
        \\ while (_it.next() catch null) |e| {
        \\     if (runtime.globMatch(_pattern, e.name)) {
        \\         const _full = std.fs.path.join(__global_allocator, &.{_p, e.name}) catch continue;
        \\         _entries.append(__global_allocator, _full) catch continue;
        \\     }
        \\ }
        \\ break :__m
    );
    try self.emitFmt("{d}_path_glob _entries; }}", .{id});
}

/// Generate rglob (recursive glob) with pattern matching
fn genPathRglob(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_path_rglob: {{ const _p = ", .{id});
    try self.genExpr(obj);
    try self.emit("; const _pattern = ");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"*\"");
    }
    try self.emit(
        \\; var _entries: std.ArrayList([]const u8) = .{};
        \\ runtime.rglobCollect(__global_allocator, _p, _pattern, &_entries);
        \\ break :__m
    );
    try self.emitFmt("{d}_path_rglob _entries; }}", .{id});
}

fn genPathExists(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_path_exists: {{ const _p = ", .{id});
    try self.genExpr(obj);
    try self.emit("; _ = std.fs.cwd().statFile(_p) catch { _ = std.fs.cwd().openDir(_p, .{}) catch break :__m");
    try self.emitFmt("{d}_path_exists false; break :__m{d}_path_exists true; }}; break :__m{d}_path_exists true; }}", .{ id, id, id });
}

fn genPathIsDir(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_path_isdir: {{ const _p = ", .{id});
    try self.genExpr(obj);
    try self.emit("; var _d = std.fs.cwd().openDir(_p, .{}) catch break :__m");
    try self.emitFmt("{d}_path_isdir false; _d.close(); break :__m{d}_path_isdir true; }}", .{ id, id });
}

fn genPathIsSymlink(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_path_islink: {{ const _p = ", .{id});
    try self.genExpr(obj);
    try self.emit("; const _s = std.fs.cwd().statFile(_p) catch break :__m");
    try self.emitFmt("{d}_path_islink false; break :__m{d}_path_islink _s.kind == .sym_link; }}", .{ id, id });
}

fn genPathIsAbsolute(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_path_isabs: {{ const _p = ", .{id});
    try self.genExpr(obj);
    try self.emitFmt("; break :__m{d}_path_isabs std.fs.path.isAbsolute(_p); }}", .{id});
}

fn genPathReadText(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_path_read: {{ const _p = ", .{id});
    try self.genExpr(obj);
    try self.emitFmt("; break :__m{d}_path_read std.fs.cwd().readFileAlloc(__global_allocator, _p, 10 * 1024 * 1024) catch \"\"; }}", .{id});
}

fn genPathReadBytes(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_path_readb: {{ const _p = ", .{id});
    try self.genExpr(obj);
    try self.emitFmt("; break :__m{d}_path_readb std.fs.cwd().readFileAlloc(__global_allocator, _p, 10 * 1024 * 1024) catch \"\"; }}", .{id});
}

fn genPathIterdir(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_path_iterdir: {{ const _p = ", .{id});
    try self.genExpr(obj);
    try self.emit("; var _entries: std.ArrayList([]const u8) = .{}; var _d = std.fs.cwd().openDir(_p, .{ .iterate = true }) catch break :__m");
    try self.emitFmt("{d}_path_iterdir _entries; defer _d.close(); var _it = _d.iterate(); while (_it.next() catch null) |e| {{ _entries.append(__global_allocator, __global_allocator.dupe(u8, e.name) catch continue) catch continue; }} break :__m{d}_path_iterdir _entries; }}", .{ id, id });
}

fn genPathTouch(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_path_touch: {{ const _p = ", .{id});
    try self.genExpr(obj);
    try self.emit("; const _f = std.fs.cwd().createFile(_p, .{ .exclusive = false }) catch break :__m");
    try self.emitFmt("{d}_path_touch {{}}; _f.close(); break :__m{d}_path_touch {{}}; }}", .{ id, id });
}

fn genPathStat(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_path_stat: {{ const _p = ", .{id});
    try self.genExpr(obj);
    try self.emit("; const _s = std.fs.cwd().statFile(_p) catch break :__m");
    try self.emitFmt("{d}_path_stat .{{ .st_size = 0, .st_mode = 0 }}; break :__m{d}_path_stat .{{ .st_size = @as(i64, @intCast(_s.size)), .st_mode = @as(u32, @intCast(_s.mode)) }}; }}", .{ id, id });
}

fn genPathAbsolute(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_path_abs: {{ const _p = ", .{id});
    try self.genExpr(obj);
    try self.emit("; const _cwd = std.process.getCwdAlloc(__global_allocator) catch break :__m");
    try self.emitFmt("{d}_path_abs _p; break :__m{d}_path_abs std.fs.path.join(__global_allocator, &.{{_cwd, _p}}) catch _p; }}", .{ id, id });
}

fn genPathResolve(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_path_resolve: {{ const _p = ", .{id});
    try self.genExpr(obj);
    try self.emitFmt("; break :__m{d}_path_resolve std.fs.cwd().realpathAlloc(__global_allocator, _p) catch _p; }}", .{id});
}

fn genPathExpanduser(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_path_expand: {{ const _p = ", .{id});
    try self.genExpr(obj);
    try self.emit("; if (_p.len > 0 and _p[0] == '~') { const _h = if (comptime @import(\"builtin\").os.tag == .windows) \"C:\\\\Users\\\\Public\" else (std.posix.getenv(\"HOME\") orelse \"\"); break :__m");
    try self.emitFmt("{d}_path_expand std.fs.path.join(__global_allocator, &.{{_h, _p[1..]}}) catch _p; }} break :__m{d}_path_expand _p; }}", .{ id, id });
}

fn genPathWithName(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return error.UnsupportedSyntax;
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_path_wname: {{ const _p = ", .{id});
    try self.genExpr(obj);
    try self.emit("; const _arg = ");
    try self.genExpr(args[0]);
    try self.emit("; const _d = std.fs.path.dirname(_p) orelse \"\"; break :__m");
    try self.emitFmt("{d}_path_wname std.fs.path.join(__global_allocator, &.{{_d, _arg}}) catch _p; }}", .{id});
}

fn genPathWithSuffix(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return error.UnsupportedSyntax;
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_path_wsuf: {{ const _p = ", .{id});
    try self.genExpr(obj);
    try self.emit("; const _arg = ");
    try self.genExpr(args[0]);
    try self.emit("; const _ext = std.fs.path.extension(_p); const _stem = if (_ext.len > 0) _p[0.._p.len - _ext.len] else _p; break :__m");
    try self.emitFmt("{d}_path_wsuf std.fmt.allocPrint(__global_allocator, \"{{s}}{{s}}\", .{{_stem, _arg}}) catch _p; }}", .{id});
}

fn genPathWithStem(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return error.UnsupportedSyntax;
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_path_wstem: {{ const _p = ", .{id});
    try self.genExpr(obj);
    try self.emit("; const _arg = ");
    try self.genExpr(args[0]);
    try self.emit("; const _ext = std.fs.path.extension(_p); const _d = std.fs.path.dirname(_p) orelse \"\"; break :__m");
    try self.emitFmt("{d}_path_wstem std.fmt.allocPrint(__global_allocator, \"{{s}}/{{s}}{{s}}\", .{{_d, _arg, _ext}}) catch _p; }}", .{id});
}

fn genPathRelativeTo(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return error.UnsupportedSyntax;
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_path_rel: {{ const _p = ", .{id});
    try self.genExpr(obj);
    try self.emit("; const _arg = ");
    try self.genExpr(args[0]);
    try self.emitFmt("; _ = _arg; break :__m{d}_path_rel _p; }}", .{id});
}

fn genPathStem(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_path_stem: {{ const _p = ", .{id});
    try self.genExpr(obj);
    try self.emit("; const _n = std.fs.path.basename(_p); const _e = std.fs.path.extension(_n); break :__m");
    try self.emitFmt("{d}_path_stem if (_e.len > 0) _n[0.._n.len - _e.len] else _n; }}", .{id});
}

fn genPathSuffixes(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_path_suffixes: {{ const _p = ", .{id});
    try self.genExpr(obj);
    try self.emit("; var _s: std.ArrayList([]const u8) = .{}; const _n = std.fs.path.basename(_p); var _i: usize = 0; while (_i < _n.len) : (_i += 1) { if (_n[_i] == '.') { _s.append(__global_allocator, _n[_i..]) catch continue; break; } } break :__m");
    try self.emitFmt("{d}_path_suffixes _s.items; }}", .{id});
}

fn genPathParents(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_path_parents: {{ const _p = ", .{id});
    try self.genExpr(obj);
    try self.emit("; var _ps: std.ArrayList([]const u8) = .{}; var _cur = _p; while (std.fs.path.dirname(_cur)) |_d| { _ps.append(__global_allocator, _d) catch break; _cur = _d; } break :__m");
    try self.emitFmt("{d}_path_parents _ps.items; }}", .{id});
}

fn genPathParts(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_path_parts: {{ const _p = ", .{id});
    try self.genExpr(obj);
    try self.emit("; var _ps: std.ArrayList([]const u8) = .{}; var _it = std.mem.splitScalar(u8, _p, '/'); while (_it.next()) |_part| { if (_part.len > 0) _ps.append(__global_allocator, _part) catch continue; } break :__m");
    try self.emitFmt("{d}_path_parts _ps.items; }}", .{id});
}

fn genPathAnchor(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_path_anchor: {{ const _p = ", .{id});
    try self.genExpr(obj);
    try self.emitFmt("; break :__m{d}_path_anchor if (_p.len > 0 and _p[0] == '/') \"/\" else \"\"; }}", .{id});
}

fn genPathOpen(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_path_open: {{ const _p = ", .{id});
    try self.genExpr(obj);
    try self.emitFmt("; break :__m{d}_path_open try runtime.PyFile.open(_p, \"r\", __global_allocator); }}", .{id});
}
