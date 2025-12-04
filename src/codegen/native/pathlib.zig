/// Pathlib module - pathlib.Path and all Path methods
const std = @import("std");
const ast = @import("ast");
const m = @import("mod_helper.zig");
const CodegenError = m.CodegenError;
const NativeCodegen = m.NativeCodegen;
const H = m.H;

/// Method handler type for Path methods (takes obj + args)
const MH = *const fn (*NativeCodegen, ast.Node, []ast.Node) CodegenError!void;

// === Comptime method generators ===

/// Generate method: label_blk: { const _p = obj; ...body... }
fn methodBlock(comptime label: []const u8, comptime body: []const u8) MH {
    return struct {
        fn f(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
            _ = args;
            try self.emit(label ++ "_blk: { const _p = ");
            try self.genExpr(obj);
            try self.emit("; " ++ body ++ " }");
        }
    }.f;
}

/// Generate method that returns bool based on condition
fn boolCheck(comptime label: []const u8, comptime check: []const u8, comptime fallback: []const u8) MH {
    return methodBlock(label, check ++ " catch break :" ++ label ++ "_blk " ++ fallback ++ "; break :" ++ label ++ "_blk true;");
}

/// Generate method with one arg: label_blk: { const _p = obj; const _arg = arg[0]; ...body... }
fn methodWithArg(comptime label: []const u8, comptime body: []const u8) MH {
    return struct {
        fn f(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
            if (args.len < 1) return;
            try self.emit(label ++ "_blk: { const _p = ");
            try self.genExpr(obj);
            try self.emit("; const _arg = ");
            try self.genExpr(args[0]);
            try self.emit("; " ++ body ++ " }");
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

/// Generate void method: label_blk: { const _p = obj; op catch {}; break :label_blk {}; }
fn voidOp(comptime label: []const u8, comptime op: []const u8) MH {
    return methodBlock(label, op ++ " catch {}; break :" ++ label ++ "_blk {};");
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
    .{ "exists", methodBlock("path_exists", "_ = std.fs.cwd().statFile(_p) catch { _ = std.fs.cwd().openDir(_p, .{}) catch break :path_exists_blk false; break :path_exists_blk true; }; break :path_exists_blk true;") },
    .{ "is_file", boolCheck("path_isfile", "_ = std.fs.cwd().statFile(_p)", "false") },
    .{ "is_dir", methodBlock("path_isdir", "var _d = std.fs.cwd().openDir(_p, .{}) catch break :path_isdir_blk false; _d.close(); break :path_isdir_blk true;") },
    .{ "is_symlink", methodBlock("path_islink", "const _s = std.fs.cwd().statFile(_p) catch break :path_islink_blk false; break :path_islink_blk _s.kind == .sym_link;") },
    .{ "is_absolute", methodBlock("path_isabs", "break :path_isabs_blk std.fs.path.isAbsolute(_p);") },
    // Reading
    .{ "read_text", methodBlock("path_read", "break :path_read_blk std.fs.cwd().readFileAlloc(__global_allocator, _p, 10 * 1024 * 1024) catch \"\";") },
    .{ "read_bytes", methodBlock("path_readb", "break :path_readb_blk std.fs.cwd().readFileAlloc(__global_allocator, _p, 10 * 1024 * 1024) catch \"\";") },
    // Writing
    .{ "write_text", genPathWrite },
    .{ "write_bytes", genPathWrite },
    // Directory ops
    .{ "iterdir", methodBlock("path_iterdir", "var _entries: std.ArrayList([]const u8) = .{}; var _d = std.fs.cwd().openDir(_p, .{ .iterate = true }) catch break :path_iterdir_blk _entries; defer _d.close(); var _it = _d.iterate(); while (_it.next() catch null) |e| { _entries.append(__global_allocator, __global_allocator.dupe(u8, e.name) catch continue) catch continue; } break :path_iterdir_blk _entries;") },
    .{ "glob", genPathGlob },
    .{ "rglob", genPathRglob },
    .{ "mkdir", voidOp("path_mkdir", "std.fs.cwd().makePath(_p)") },
    .{ "rmdir", voidOp("path_rmdir", "std.fs.cwd().deleteDir(_p)") },
    // File ops
    .{ "unlink", voidOp("path_unlink", "std.fs.cwd().deleteFile(_p)") },
    .{ "rename", genPathRename },
    .{ "replace", genPathReplace },
    .{ "touch", methodBlock("path_touch", "const _f = std.fs.cwd().createFile(_p, .{ .exclusive = false }) catch break :path_touch_blk {}; _f.close(); break :path_touch_blk {};") },
    .{ "chmod", genPathChmod },
    .{ "stat", methodBlock("path_stat", "const _s = std.fs.cwd().statFile(_p) catch break :path_stat_blk .{ .st_size = 0, .st_mode = 0 }; break :path_stat_blk .{ .st_size = @as(i64, @intCast(_s.size)), .st_mode = @as(u32, @intCast(_s.mode)) };") },
    .{ "lstat", prop("", ".stat()") },
    // Path manipulation
    .{ "absolute", methodBlock("path_abs", "const _cwd = std.process.getCwdAlloc(__global_allocator) catch break :path_abs_blk _p; break :path_abs_blk std.fs.path.join(__global_allocator, &.{_cwd, _p}) catch _p;") },
    .{ "resolve", methodBlock("path_resolve", "break :path_resolve_blk std.fs.cwd().realpathAlloc(__global_allocator, _p) catch _p;") },
    .{ "expanduser", methodBlock("path_expand", "if (_p.len > 0 and _p[0] == '~') { const _h = std.posix.getenv(\"HOME\") orelse \"\"; break :path_expand_blk std.fs.path.join(__global_allocator, &.{_h, _p[1..]}) catch _p; } break :path_expand_blk _p;") },
    .{ "with_name", methodWithArg("path_wname", "const _d = std.fs.path.dirname(_p) orelse \"\"; break :path_wname_blk std.fs.path.join(__global_allocator, &.{_d, _arg}) catch _p;") },
    .{ "with_suffix", methodWithArg("path_wsuf", "const _ext = std.fs.path.extension(_p); const _stem = if (_ext.len > 0) _p[0.._p.len - _ext.len] else _p; break :path_wsuf_blk std.fmt.allocPrint(__global_allocator, \"{s}{s}\", .{_stem, _arg}) catch _p;") },
    .{ "with_stem", methodWithArg("path_wstem", "const _ext = std.fs.path.extension(_p); const _d = std.fs.path.dirname(_p) orelse \"\"; break :path_wstem_blk std.fmt.allocPrint(__global_allocator, \"{s}/{s}{s}\", .{_d, _arg, _ext}) catch _p;") },
    .{ "joinpath", genPathJoinpath },
    .{ "relative_to", methodWithArg("path_rel", "_ = _arg; break :path_rel_blk _p;") },
    // Properties
    .{ "name", prop("std.fs.path.basename(", ")") },
    .{ "stem", methodBlock("path_stem", "const _n = std.fs.path.basename(_p); const _e = std.fs.path.extension(_n); break :path_stem_blk if (_e.len > 0) _n[0.._n.len - _e.len] else _n;") },
    .{ "suffix", prop("std.fs.path.extension(", ")") },
    .{ "suffixes", methodBlock("path_suffixes", "var _s: std.ArrayList([]const u8) = .{}; const _n = std.fs.path.basename(_p); var _i: usize = 0; while (_i < _n.len) : (_i += 1) { if (_n[_i] == '.') { _s.append(__global_allocator, _n[_i..]) catch continue; break; } } break :path_suffixes_blk _s.items;") },
    .{ "parent", prop("std.fs.path.dirname(", ") orelse \".\"") },
    .{ "parents", methodBlock("path_parents", "var _ps: std.ArrayList([]const u8) = .{}; var _cur = _p; while (std.fs.path.dirname(_cur)) |_d| { _ps.append(__global_allocator, _d) catch break; _cur = _d; } break :path_parents_blk _ps.items;") },
    .{ "parts", methodBlock("path_parts", "var _ps: std.ArrayList([]const u8) = .{}; var _it = std.mem.splitScalar(u8, _p, '/'); while (_it.next()) |_part| { if (_part.len > 0) _ps.append(__global_allocator, _part) catch continue; } break :path_parts_blk _ps.items;") },
    .{ "anchor", methodBlock("path_anchor", "break :path_anchor_blk if (_p.len > 0 and _p[0] == '/') \"/\" else \"\";") },
    .{ "as_posix", prop("", "") },
    .{ "open", methodBlock("path_open", "break :path_open_blk try runtime.PyFile.open(_p, \"r\", __global_allocator);") },
});

// === Complex handlers ===

fn genPathWrite(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return;
    try self.emit("path_write_blk: { const _p = ");
    try self.genExpr(obj);
    try self.emit("; const _data = ");
    try self.genExpr(args[0]);
    try self.emit("; const _f = std.fs.cwd().createFile(_p, .{}) catch break :path_write_blk @as(usize, 0); defer _f.close(); break :path_write_blk _f.write(_data) catch 0; }");
}

fn genPathRename(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return;
    try self.emit("path_rename_blk: { const _old = ");
    try self.genExpr(obj);
    try self.emit("; const _new = ");
    try self.genExpr(args[0]);
    try self.emit("; std.fs.cwd().rename(_old, _new) catch {}; break :path_rename_blk _new; }");
}

fn genPathReplace(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return;
    try self.emit("path_replace_blk: { const _old = ");
    try self.genExpr(obj);
    try self.emit("; const _new = ");
    try self.genExpr(args[0]);
    try self.emit("; std.fs.cwd().deleteFile(_new) catch {}; std.fs.cwd().rename(_old, _new) catch {}; break :path_replace_blk _new; }");
}

fn genPathChmod(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return;
    try self.emit("path_chmod_blk: { const _p = ");
    try self.genExpr(obj);
    try self.emit("; const _m: std.fs.File.Mode = @intCast(");
    try self.genExpr(args[0]);
    try self.emit("); const _f = std.fs.cwd().openFile(_p, .{}) catch break :path_chmod_blk {}; defer _f.close(); _f.chmod(_m) catch {}; break :path_chmod_blk {}; }");
}

fn genPathJoinpath(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    try self.emit("path_join_blk: { const _base = ");
    try self.genExpr(obj);
    try self.emit("; const _parts = [_][]const u8{ _base");
    for (args) |arg| {
        try self.emit(", ");
        try self.genExpr(arg);
    }
    try self.emit(" }; break :path_join_blk std.fs.path.join(__global_allocator, &_parts) catch _base; }");
}

/// Generate glob with actual pattern matching
fn genPathGlob(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    try self.emit("path_glob_blk: { const _p = ");
    try self.genExpr(obj);
    try self.emit("; const _pattern = ");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"*\"");
    }
    try self.emit(
        \\; var _entries: std.ArrayList([]const u8) = .{};
        \\ var _d = std.fs.cwd().openDir(_p, .{ .iterate = true }) catch break :path_glob_blk _entries;
        \\ defer _d.close();
        \\ var _it = _d.iterate();
        \\ while (_it.next() catch null) |e| {
        \\     if (runtime.globMatch(_pattern, e.name)) {
        \\         const _full = std.fs.path.join(__global_allocator, &.{_p, e.name}) catch continue;
        \\         _entries.append(__global_allocator, _full) catch continue;
        \\     }
        \\ }
        \\ break :path_glob_blk _entries; }
    );
}

/// Generate rglob (recursive glob) with pattern matching
fn genPathRglob(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    try self.emit("path_rglob_blk: { const _p = ");
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
        \\ break :path_rglob_blk _entries; }
    );
}
