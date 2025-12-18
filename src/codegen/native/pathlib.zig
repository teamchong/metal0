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

/// Generate method: { const _p = obj; ...body... }
fn methodBlock(comptime label: []const u8, comptime body: []const u8) MH {
    return struct {
        fn f(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
            _ = args;
            _ = try self.emitInlineBlockStart(label);
            try self.emit("const _p = ");
            try self.genExpr(obj);
            try self.emitFmt("; " ++ body ++ " ", .{});
            try self.emitInlineBlockEnd();
        }
    }.f;
}

/// Generate method that returns bool based on condition
fn boolCheck(comptime label: []const u8, comptime check: []const u8, comptime fallback: []const u8) MH {
    return struct {
        fn f(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
            _ = args;
            const lbl = try self.emitInlineBlockStart(label);
            try self.emit("const _p = ");
            try self.genExpr(obj);
            try self.emitFmt("; " ++ check ++ " catch break :{s} " ++ fallback ++ "; break :{s} true; ", .{ lbl, lbl });
            try self.emitInlineBlockEnd();
        }
    }.f;
}

/// Generate method with one arg: { const _p = obj; const _arg = arg[0]; ...body... }
fn methodWithArg(comptime label: []const u8, comptime body: []const u8) MH {
    return struct {
        fn f(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
            if (args.len < 1) return error.UnsupportedSyntax;
            _ = try self.emitInlineBlockStart(label);
            try self.emit("const _p = ");
            try self.genExpr(obj);
            try self.emit("; const _arg = ");
            try self.genExpr(args[0]);
            try self.emitFmt("; " ++ body ++ " ", .{});
            try self.emitInlineBlockEnd();
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

/// Generate void method: { const _p = obj; op catch {}; break :label {}; }
fn voidOp(comptime label: []const u8, comptime op: []const u8) MH {
    return struct {
        fn f(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
            _ = args;
            const lbl = try self.emitInlineBlockStart(label);
            try self.emit("const _p = ");
            try self.genExpr(obj);
            try self.emitFmt("; " ++ op ++ " catch {{}}; break :{s} {{}}; ", .{lbl});
            try self.emitInlineBlockEnd();
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
    const label = try self.emitInlineBlockStart("path_write");
    try self.emit("const _p = ");
    try self.genExpr(obj);
    try self.emit("; const _data = ");
    try self.genExpr(args[0]);
    try self.emitFmt("; const _f = std.fs.cwd().createFile(_p, .{{}}) catch break :{s} @as(usize, 0); defer _f.close(); break :{s} _f.write(_data) catch 0; ", .{ label, label });
    try self.emitInlineBlockEnd();
}

fn genPathRename(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return error.UnsupportedSyntax;
    const label = try self.emitInlineBlockStart("path_rename");
    try self.emit("const _old = ");
    try self.genExpr(obj);
    try self.emit("; const _new = ");
    try self.genExpr(args[0]);
    try self.emitFmt("; std.fs.cwd().rename(_old, _new) catch {{}}; break :{s} _new; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genPathReplace(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return error.UnsupportedSyntax;
    const label = try self.emitInlineBlockStart("path_replace");
    try self.emit("const _old = ");
    try self.genExpr(obj);
    try self.emit("; const _new = ");
    try self.genExpr(args[0]);
    try self.emitFmt("; std.fs.cwd().deleteFile(_new) catch {{}}; std.fs.cwd().rename(_old, _new) catch {{}}; break :{s} _new; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genPathChmod(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return error.UnsupportedSyntax;
    const label = try self.emitInlineBlockStart("path_chmod");
    try self.emit("const _p = ");
    try self.genExpr(obj);
    try self.emit("; const _m: std.fs.File.Mode = @intCast(");
    try self.genExpr(args[0]);
    try self.emitFmt("); const _f = std.fs.cwd().openFile(_p, .{{}}) catch break :{s} {{}}; defer _f.close(); _f.chmod(_m) catch {{}}; break :{s} {{}}; ", .{ label, label });
    try self.emitInlineBlockEnd();
}

fn genPathJoinpath(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    const label = try self.emitInlineBlockStart("path_join");
    try self.emit("const _base = ");
    try self.genExpr(obj);
    try self.emit("; const _parts = [_][]const u8{ _base");
    for (args) |arg| {
        try self.emit(", ");
        try self.genExpr(arg);
    }
    try self.emitFmt(" }}; break :{s} std.fs.path.join(__global_allocator, &_parts) catch _base; ", .{label});
    try self.emitInlineBlockEnd();
}

/// Generate glob with actual pattern matching
fn genPathGlob(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    const label = try self.emitInlineBlockStart("path_glob");
    try self.emit("const _p = ");
    try self.genExpr(obj);
    try self.emit("; const _pattern = ");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"*\"");
    }
    try self.emit(
        \\; var _entries: std.ArrayList([]const u8) = .{};
        \\ var _d = std.fs.cwd().openDir(_p, .{ .iterate = true }) catch break :
    );
    try self.emit(label);
    try self.emit(
        \\ _entries;
        \\ defer _d.close();
        \\ var _it = _d.iterate();
        \\ while (_it.next() catch null) |e| {
        \\     if (runtime.globMatch(_pattern, e.name)) {
        \\         const _full = std.fs.path.join(__global_allocator, &.{_p, e.name}) catch continue;
        \\         _entries.append(__global_allocator, _full) catch continue;
        \\     }
        \\ }
        \\ break :
    );
    try self.emitFmt("{s} _entries; ", .{label});
    try self.emitInlineBlockEnd();
}

/// Generate rglob (recursive glob) with pattern matching
fn genPathRglob(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    const label = try self.emitInlineBlockStart("path_rglob");
    try self.emit("const _p = ");
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
        \\ break :
    );
    try self.emitFmt("{s} _entries; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genPathExists(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const label = try self.emitInlineBlockStart("path_exists");
    try self.emit("const _p = ");
    try self.genExpr(obj);
    try self.emitFmt("; _ = std.fs.cwd().statFile(_p) catch {{ _ = std.fs.cwd().openDir(_p, .{{}}) catch break :{s} false; break :{s} true; }}; break :{s} true; ", .{ label, label, label });
    try self.emitInlineBlockEnd();
}

fn genPathIsDir(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const label = try self.emitInlineBlockStart("path_isdir");
    try self.emit("const _p = ");
    try self.genExpr(obj);
    try self.emitFmt("; var _d = std.fs.cwd().openDir(_p, .{{}}) catch break :{s} false; _d.close(); break :{s} true; ", .{ label, label });
    try self.emitInlineBlockEnd();
}

fn genPathIsSymlink(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const label = try self.emitInlineBlockStart("path_islink");
    try self.emit("const _p = ");
    try self.genExpr(obj);
    try self.emitFmt("; const _s = std.fs.cwd().statFile(_p) catch break :{s} false; break :{s} _s.kind == .sym_link; ", .{ label, label });
    try self.emitInlineBlockEnd();
}

fn genPathIsAbsolute(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const label = try self.emitInlineBlockStart("path_isabs");
    try self.emit("const _p = ");
    try self.genExpr(obj);
    try self.emitFmt("; break :{s} std.fs.path.isAbsolute(_p); ", .{label});
    try self.emitInlineBlockEnd();
}

fn genPathReadText(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const label = try self.emitInlineBlockStart("path_read");
    try self.emit("const _p = ");
    try self.genExpr(obj);
    try self.emitFmt("; break :{s} std.fs.cwd().readFileAlloc(__global_allocator, _p, 10 * 1024 * 1024) catch \"\"; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genPathReadBytes(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const label = try self.emitInlineBlockStart("path_readb");
    try self.emit("const _p = ");
    try self.genExpr(obj);
    try self.emitFmt("; break :{s} std.fs.cwd().readFileAlloc(__global_allocator, _p, 10 * 1024 * 1024) catch \"\"; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genPathIterdir(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const label = try self.emitInlineBlockStart("path_iterdir");
    try self.emit("const _p = ");
    try self.genExpr(obj);
    try self.emitFmt("; var _entries: std.ArrayList([]const u8) = .{{}}; var _d = std.fs.cwd().openDir(_p, .{{ .iterate = true }}) catch break :{s} _entries; defer _d.close(); var _it = _d.iterate(); while (_it.next() catch null) |e| {{ _entries.append(__global_allocator, __global_allocator.dupe(u8, e.name) catch continue) catch continue; }} break :{s} _entries; ", .{ label, label });
    try self.emitInlineBlockEnd();
}

fn genPathTouch(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const label = try self.emitInlineBlockStart("path_touch");
    try self.emit("const _p = ");
    try self.genExpr(obj);
    try self.emitFmt("; const _f = std.fs.cwd().createFile(_p, .{{ .exclusive = false }}) catch break :{s} {{}}; _f.close(); break :{s} {{}}; ", .{ label, label });
    try self.emitInlineBlockEnd();
}

fn genPathStat(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const label = try self.emitInlineBlockStart("path_stat");
    try self.emit("const _p = ");
    try self.genExpr(obj);
    try self.emitFmt("; const _s = std.fs.cwd().statFile(_p) catch break :{s} .{{ .st_size = 0, .st_mode = 0 }}; break :{s} .{{ .st_size = @as(i64, @intCast(_s.size)), .st_mode = @as(u32, @intCast(_s.mode)) }}; ", .{ label, label });
    try self.emitInlineBlockEnd();
}

fn genPathAbsolute(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const label = try self.emitInlineBlockStart("path_abs");
    try self.emit("const _p = ");
    try self.genExpr(obj);
    try self.emitFmt("; const _cwd = std.process.getCwdAlloc(__global_allocator) catch break :{s} _p; break :{s} std.fs.path.join(__global_allocator, &.{{_cwd, _p}}) catch _p; ", .{ label, label });
    try self.emitInlineBlockEnd();
}

fn genPathResolve(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const label = try self.emitInlineBlockStart("path_resolve");
    try self.emit("const _p = ");
    try self.genExpr(obj);
    try self.emitFmt("; break :{s} std.fs.cwd().realpathAlloc(__global_allocator, _p) catch _p; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genPathExpanduser(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const label = try self.emitInlineBlockStart("path_expand");
    try self.emit("const _p = ");
    try self.genExpr(obj);
    try self.emitFmt("; if (_p.len > 0 and _p[0] == '~') {{ const _h = if (comptime @import(\"builtin\").os.tag == .windows) \"C:\\\\Users\\\\Public\" else (std.posix.getenv(\"HOME\") orelse \"\"); break :{s} std.fs.path.join(__global_allocator, &.{{_h, _p[1..]}}) catch _p; }} break :{s} _p; ", .{ label, label });
    try self.emitInlineBlockEnd();
}

fn genPathWithName(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return error.UnsupportedSyntax;
    const label = try self.emitInlineBlockStart("path_wname");
    try self.emit("const _p = ");
    try self.genExpr(obj);
    try self.emit("; const _arg = ");
    try self.genExpr(args[0]);
    try self.emitFmt("; const _d = std.fs.path.dirname(_p) orelse \"\"; break :{s} std.fs.path.join(__global_allocator, &.{{_d, _arg}}) catch _p; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genPathWithSuffix(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return error.UnsupportedSyntax;
    const label = try self.emitInlineBlockStart("path_wsuf");
    try self.emit("const _p = ");
    try self.genExpr(obj);
    try self.emit("; const _arg = ");
    try self.genExpr(args[0]);
    try self.emitFmt("; const _ext = std.fs.path.extension(_p); const _stem = if (_ext.len > 0) _p[0.._p.len - _ext.len] else _p; break :{s} std.fmt.allocPrint(__global_allocator, \"{{s}}{{s}}\", .{{_stem, _arg}}) catch _p; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genPathWithStem(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return error.UnsupportedSyntax;
    const label = try self.emitInlineBlockStart("path_wstem");
    try self.emit("const _p = ");
    try self.genExpr(obj);
    try self.emit("; const _arg = ");
    try self.genExpr(args[0]);
    try self.emitFmt("; const _ext = std.fs.path.extension(_p); const _d = std.fs.path.dirname(_p) orelse \"\"; break :{s} std.fmt.allocPrint(__global_allocator, \"{{s}}/{{s}}{{s}}\", .{{_d, _arg, _ext}}) catch _p; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genPathRelativeTo(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return error.UnsupportedSyntax;
    const label = try self.emitInlineBlockStart("path_rel");
    try self.emit("const _p = ");
    try self.genExpr(obj);
    try self.emit("; const _arg = ");
    try self.genExpr(args[0]);
    try self.emitFmt("; _ = _arg; break :{s} _p; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genPathStem(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const label = try self.emitInlineBlockStart("path_stem");
    try self.emit("const _p = ");
    try self.genExpr(obj);
    try self.emitFmt("; const _n = std.fs.path.basename(_p); const _e = std.fs.path.extension(_n); break :{s} if (_e.len > 0) _n[0.._n.len - _e.len] else _n; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genPathSuffixes(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const label = try self.emitInlineBlockStart("path_suffixes");
    try self.emit("const _p = ");
    try self.genExpr(obj);
    try self.emitFmt("; var _s: std.ArrayList([]const u8) = .{{}}; const _n = std.fs.path.basename(_p); var _i: usize = 0; while (_i < _n.len) : (_i += 1) {{ if (_n[_i] == '.') {{ _s.append(__global_allocator, _n[_i..]) catch continue; break; }} }} break :{s} _s.items; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genPathParents(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const label = try self.emitInlineBlockStart("path_parents");
    try self.emit("const _p = ");
    try self.genExpr(obj);
    try self.emitFmt("; var _ps: std.ArrayList([]const u8) = .{{}}; var _cur = _p; while (std.fs.path.dirname(_cur)) |_d| {{ _ps.append(__global_allocator, _d) catch break; _cur = _d; }} break :{s} _ps.items; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genPathParts(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const label = try self.emitInlineBlockStart("path_parts");
    try self.emit("const _p = ");
    try self.genExpr(obj);
    try self.emitFmt("; var _ps: std.ArrayList([]const u8) = .{{}}; var _it = std.mem.splitScalar(u8, _p, '/'); while (_it.next()) |_part| {{ if (_part.len > 0) _ps.append(__global_allocator, _part) catch continue; }} break :{s} _ps.items; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genPathAnchor(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const label = try self.emitInlineBlockStart("path_anchor");
    try self.emit("const _p = ");
    try self.genExpr(obj);
    try self.emitFmt("; break :{s} if (_p.len > 0 and _p[0] == '/') \"/\" else \"\"; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genPathOpen(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const label = try self.emitInlineBlockStart("path_open");
    try self.emit("const _p = ");
    try self.genExpr(obj);
    try self.emitFmt("; break :{s} try runtime.PyFile.open(_p, \"r\", __global_allocator); ", .{label});
    try self.emitInlineBlockEnd();
}
