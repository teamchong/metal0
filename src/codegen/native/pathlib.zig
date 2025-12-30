/// Pathlib module - pathlib.Path and all Path methods
/// MIGRATED TO ZIGBUILDER
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
            try self.withInlineBlock(label, obj, struct {
                fn emit(s: *NativeCodegen, _: []const u8, o: ast.Node) CodegenError!void {
                    try s.emit("const _p = ");
                    try s.genExpr(o);
                    try s.emit("; " ++ body);
                }
            }.emit);
        }
    }.f;
}

/// Generate method that returns bool based on condition
fn boolCheck(comptime label: []const u8, comptime check: []const u8, comptime fallback: []const u8) MH {
    return struct {
        fn f(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
            _ = args;
            try self.withInlineBlock(label, obj, struct {
                fn emit(s: *NativeCodegen, lbl: []const u8, o: ast.Node) CodegenError!void {
                    try s.emit("const _p = ");
                    try s.genExpr(o);
                    try s.emit("; " ++ check ++ " catch break :");
                    try s.emit(lbl);
                    try s.emit(" " ++ fallback ++ "; break :");
                    try s.emit(lbl);
                    try s.emit(" true");
                }
            }.emit);
        }
    }.f;
}

/// Generate method with one arg: { const _p = obj; const _arg = arg[0]; ...body... }
fn methodWithArg(comptime label: []const u8, comptime body: []const u8) MH {
    const Ctx = struct { o: ast.Node, a: ast.Node };
    return struct {
        fn f(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
            if (args.len < 1) return error.UnsupportedSyntax;
            try self.withInlineBlock(label, Ctx{ .o = obj, .a = args[0] }, struct {
                fn emit(s: *NativeCodegen, _: []const u8, ctx: Ctx) CodegenError!void {
                    try s.emit("const _p = ");
                    try s.genExpr(ctx.o);
                    try s.emit("; const _arg = ");
                    try s.genExpr(ctx.a);
                    try s.emit("; " ++ body);
                }
            }.emit);
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
            try self.withInlineBlock(label, obj, struct {
                fn emit(s: *NativeCodegen, lbl: []const u8, o: ast.Node) CodegenError!void {
                    try s.emit("const _p = ");
                    try s.genExpr(o);
                    try s.emit("; " ++ op ++ " catch {}; break :");
                    try s.emit(lbl);
                    try s.emit(" {}");
                }
            }.emit);
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
    const Ctx = struct { o: ast.Node, a: ast.Node };
    try self.withInlineBlock("path_write", Ctx{ .o = obj, .a = args[0] }, struct {
        fn emit(s: *NativeCodegen, label: []const u8, ctx: Ctx) CodegenError!void {
            try s.emit("const _p = ");
            try s.genExpr(ctx.o);
            try s.emit("; const _data = ");
            try s.genExpr(ctx.a);
            try s.emitFmt("; const _f = std.fs.cwd().createFile(_p, .{{}}) catch break :{s} @as(usize, 0); defer _f.close(); break :{s} _f.write(_data) catch 0", .{ label, label });
        }
    }.emit);
}

fn genPathRename(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return error.UnsupportedSyntax;
    const Ctx = struct { o: ast.Node, a: ast.Node };
    try self.withInlineBlock("path_rename", Ctx{ .o = obj, .a = args[0] }, struct {
        fn emit(s: *NativeCodegen, label: []const u8, ctx: Ctx) CodegenError!void {
            try s.emit("const _old = ");
            try s.genExpr(ctx.o);
            try s.emit("; const _new = ");
            try s.genExpr(ctx.a);
            try s.emitFmt("; std.fs.cwd().rename(_old, _new) catch {{}}; break :{s} _new", .{label});
        }
    }.emit);
}

fn genPathReplace(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return error.UnsupportedSyntax;
    const Ctx = struct { o: ast.Node, a: ast.Node };
    try self.withInlineBlock("path_replace", Ctx{ .o = obj, .a = args[0] }, struct {
        fn emit(s: *NativeCodegen, label: []const u8, ctx: Ctx) CodegenError!void {
            try s.emit("const _old = ");
            try s.genExpr(ctx.o);
            try s.emit("; const _new = ");
            try s.genExpr(ctx.a);
            try s.emitFmt("; std.fs.cwd().deleteFile(_new) catch {{}}; std.fs.cwd().rename(_old, _new) catch {{}}; break :{s} _new", .{label});
        }
    }.emit);
}

fn genPathChmod(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return error.UnsupportedSyntax;
    const Ctx = struct { o: ast.Node, a: ast.Node };
    try self.withInlineBlock("path_chmod", Ctx{ .o = obj, .a = args[0] }, struct {
        fn emit(s: *NativeCodegen, label: []const u8, ctx: Ctx) CodegenError!void {
            try s.emit("const _p = ");
            try s.genExpr(ctx.o);
            try s.emit("; const _m: std.fs.File.Mode = @intCast(");
            try s.genExpr(ctx.a);
            try s.emitFmt("); const _f = std.fs.cwd().openFile(_p, .{{}}) catch break :{s} {{}}; defer _f.close(); _f.chmod(_m) catch {{}}; break :{s} {{}}", .{ label, label });
        }
    }.emit);
}

fn genPathJoinpath(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    const Ctx = struct { o: ast.Node, a: []ast.Node };
    try self.withInlineBlock("path_join", Ctx{ .o = obj, .a = args }, struct {
        fn emit(s: *NativeCodegen, label: []const u8, ctx: Ctx) CodegenError!void {
            try s.emit("const _base = ");
            try s.genExpr(ctx.o);
            try s.emit("; const _parts = [_][]const u8{ _base");
            for (ctx.a) |arg| {
                try s.emit(", ");
                try s.genExpr(arg);
            }
            try s.emitFmt(" }}; break :{s} std.fs.path.join(__global_allocator, &_parts) catch _base", .{label});
        }
    }.emit);
}

/// Generate glob with actual pattern matching
fn genPathGlob(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    const Ctx = struct { o: ast.Node, a: []ast.Node };
    try self.withInlineBlock("path_glob", Ctx{ .o = obj, .a = args }, struct {
        fn emit(s: *NativeCodegen, label: []const u8, ctx: Ctx) CodegenError!void {
            try s.emit("const _p = ");
            try s.genExpr(ctx.o);
            try s.emit("; const _pattern = ");
            if (ctx.a.len > 0) {
                try s.genExpr(ctx.a[0]);
            } else {
                try s.emit("\"*\"");
            }
            try s.emit("; var _entries: std.ArrayList([]const u8) = .{}; var _d = std.fs.cwd().openDir(_p, .{ .iterate = true }) catch break :");
            try s.emit(label);
            try s.emit(" _entries; defer _d.close(); var _it = _d.iterate(); while (_it.next() catch null) |e| { if (runtime.globMatch(_pattern, e.name)) { const _full = std.fs.path.join(__global_allocator, &.{_p, e.name}) catch continue; _entries.append(__global_allocator, _full) catch continue; } } break :");
            try s.emitFmt("{s} _entries", .{label});
        }
    }.emit);
}

/// Generate rglob (recursive glob) with pattern matching
fn genPathRglob(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    const Ctx = struct { o: ast.Node, a: []ast.Node };
    try self.withInlineBlock("path_rglob", Ctx{ .o = obj, .a = args }, struct {
        fn emit(s: *NativeCodegen, label: []const u8, ctx: Ctx) CodegenError!void {
            try s.emit("const _p = ");
            try s.genExpr(ctx.o);
            try s.emit("; const _pattern = ");
            if (ctx.a.len > 0) {
                try s.genExpr(ctx.a[0]);
            } else {
                try s.emit("\"*\"");
            }
            try s.emitFmt("; var _entries: std.ArrayList([]const u8) = .{{}}; runtime.rglobCollect(__global_allocator, _p, _pattern, &_entries); break :{s} _entries", .{label});
        }
    }.emit);
}

fn genPathExists(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.withInlineBlock("path_exists", obj, struct {
        fn emit(s: *NativeCodegen, label: []const u8, o: ast.Node) CodegenError!void {
            try s.emit("const _p = ");
            try s.genExpr(o);
            try s.emitFmt("; _ = std.fs.cwd().statFile(_p) catch {{ _ = std.fs.cwd().openDir(_p, .{{}}) catch break :{s} false; break :{s} true; }}; break :{s} true", .{ label, label, label });
        }
    }.emit);
}

fn genPathIsDir(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.withInlineBlock("path_isdir", obj, struct {
        fn emit(s: *NativeCodegen, label: []const u8, o: ast.Node) CodegenError!void {
            try s.emit("const _p = ");
            try s.genExpr(o);
            try s.emitFmt("; var _d = std.fs.cwd().openDir(_p, .{{}}) catch break :{s} false; _d.close(); break :{s} true", .{ label, label });
        }
    }.emit);
}

fn genPathIsSymlink(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.withInlineBlock("path_islink", obj, struct {
        fn emit(s: *NativeCodegen, label: []const u8, o: ast.Node) CodegenError!void {
            try s.emit("const _p = ");
            try s.genExpr(o);
            try s.emitFmt("; const _s = std.fs.cwd().statFile(_p) catch break :{s} false; break :{s} _s.kind == .sym_link", .{ label, label });
        }
    }.emit);
}

fn genPathIsAbsolute(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.withInlineBlock("path_isabs", obj, struct {
        fn emit(s: *NativeCodegen, label: []const u8, o: ast.Node) CodegenError!void {
            try s.emit("const _p = ");
            try s.genExpr(o);
            try s.emitFmt("; break :{s} std.fs.path.isAbsolute(_p)", .{label});
        }
    }.emit);
}

fn genPathReadText(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.withInlineBlock("path_read", obj, struct {
        fn emit(s: *NativeCodegen, label: []const u8, o: ast.Node) CodegenError!void {
            try s.emit("const _p = ");
            try s.genExpr(o);
            try s.emitFmt("; break :{s} std.fs.cwd().readFileAlloc(__global_allocator, _p, 10 * 1024 * 1024) catch \"\"", .{label});
        }
    }.emit);
}

fn genPathReadBytes(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.withInlineBlock("path_readb", obj, struct {
        fn emit(s: *NativeCodegen, label: []const u8, o: ast.Node) CodegenError!void {
            try s.emit("const _p = ");
            try s.genExpr(o);
            try s.emitFmt("; break :{s} std.fs.cwd().readFileAlloc(__global_allocator, _p, 10 * 1024 * 1024) catch \"\"", .{label});
        }
    }.emit);
}

fn genPathIterdir(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.withInlineBlock("path_iterdir", obj, struct {
        fn emit(s: *NativeCodegen, label: []const u8, o: ast.Node) CodegenError!void {
            try s.emit("const _p = ");
            try s.genExpr(o);
            try s.emitFmt("; var _entries: std.ArrayList([]const u8) = .{{}}; var _d = std.fs.cwd().openDir(_p, .{{ .iterate = true }}) catch break :{s} _entries; defer _d.close(); var _it = _d.iterate(); while (_it.next() catch null) |e| {{ _entries.append(__global_allocator, __global_allocator.dupe(u8, e.name) catch continue) catch continue; }} break :{s} _entries", .{ label, label });
        }
    }.emit);
}

fn genPathTouch(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.withInlineBlock("path_touch", obj, struct {
        fn emit(s: *NativeCodegen, label: []const u8, o: ast.Node) CodegenError!void {
            try s.emit("const _p = ");
            try s.genExpr(o);
            try s.emitFmt("; const _f = std.fs.cwd().createFile(_p, .{{ .exclusive = false }}) catch break :{s} {{}}; _f.close(); break :{s} {{}}", .{ label, label });
        }
    }.emit);
}

fn genPathStat(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.withInlineBlock("path_stat", obj, struct {
        fn emit(s: *NativeCodegen, label: []const u8, o: ast.Node) CodegenError!void {
            try s.emit("const _p = ");
            try s.genExpr(o);
            try s.emitFmt("; const _s = std.fs.cwd().statFile(_p) catch break :{s} .{{ .st_size = 0, .st_mode = 0 }}; break :{s} .{{ .st_size = @as(i64, @intCast(_s.size)), .st_mode = @as(u32, @intCast(_s.mode)) }}", .{ label, label });
        }
    }.emit);
}

fn genPathAbsolute(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.withInlineBlock("path_abs", obj, struct {
        fn emit(s: *NativeCodegen, label: []const u8, o: ast.Node) CodegenError!void {
            try s.emit("const _p = ");
            try s.genExpr(o);
            try s.emitFmt("; const _cwd = std.process.getCwdAlloc(__global_allocator) catch break :{s} _p; break :{s} std.fs.path.join(__global_allocator, &.{{_cwd, _p}}) catch _p", .{ label, label });
        }
    }.emit);
}

fn genPathResolve(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.withInlineBlock("path_resolve", obj, struct {
        fn emit(s: *NativeCodegen, label: []const u8, o: ast.Node) CodegenError!void {
            try s.emit("const _p = ");
            try s.genExpr(o);
            try s.emitFmt("; break :{s} std.fs.cwd().realpathAlloc(__global_allocator, _p) catch _p", .{label});
        }
    }.emit);
}

fn genPathExpanduser(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.withInlineBlock("path_expand", obj, struct {
        fn emit(s: *NativeCodegen, label: []const u8, o: ast.Node) CodegenError!void {
            try s.emit("const _p = ");
            try s.genExpr(o);
            try s.emitFmt("; if (_p.len > 0 and _p[0] == '~') {{ const _h = if (comptime @import(\"builtin\").os.tag == .windows) \"C:\\\\Users\\\\Public\" else (std.posix.getenv(\"HOME\") orelse \"\"); break :{s} std.fs.path.join(__global_allocator, &.{{_h, _p[1..]}}) catch _p; }} break :{s} _p", .{ label, label });
        }
    }.emit);
}

fn genPathWithName(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return error.UnsupportedSyntax;
    const Ctx = struct { o: ast.Node, a: ast.Node };
    try self.withInlineBlock("path_wname", Ctx{ .o = obj, .a = args[0] }, struct {
        fn emit(s: *NativeCodegen, label: []const u8, ctx: Ctx) CodegenError!void {
            try s.emit("const _p = ");
            try s.genExpr(ctx.o);
            try s.emit("; const _arg = ");
            try s.genExpr(ctx.a);
            try s.emitFmt("; const _d = std.fs.path.dirname(_p) orelse \"\"; break :{s} std.fs.path.join(__global_allocator, &.{{_d, _arg}}) catch _p", .{label});
        }
    }.emit);
}

fn genPathWithSuffix(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return error.UnsupportedSyntax;
    const Ctx = struct { o: ast.Node, a: ast.Node };
    try self.withInlineBlock("path_wsuf", Ctx{ .o = obj, .a = args[0] }, struct {
        fn emit(s: *NativeCodegen, label: []const u8, ctx: Ctx) CodegenError!void {
            try s.emit("const _p = ");
            try s.genExpr(ctx.o);
            try s.emit("; const _arg = ");
            try s.genExpr(ctx.a);
            try s.emitFmt("; const _ext = std.fs.path.extension(_p); const _stem = if (_ext.len > 0) _p[0.._p.len - _ext.len] else _p; break :{s} std.fmt.allocPrint(__global_allocator, \"{{s}}{{s}}\", .{{_stem, _arg}}) catch _p", .{label});
        }
    }.emit);
}

fn genPathWithStem(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return error.UnsupportedSyntax;
    const Ctx = struct { o: ast.Node, a: ast.Node };
    try self.withInlineBlock("path_wstem", Ctx{ .o = obj, .a = args[0] }, struct {
        fn emit(s: *NativeCodegen, label: []const u8, ctx: Ctx) CodegenError!void {
            try s.emit("const _p = ");
            try s.genExpr(ctx.o);
            try s.emit("; const _arg = ");
            try s.genExpr(ctx.a);
            try s.emitFmt("; const _ext = std.fs.path.extension(_p); const _d = std.fs.path.dirname(_p) orelse \"\"; break :{s} std.fmt.allocPrint(__global_allocator, \"{{s}}/{{s}}{{s}}\", .{{_d, _arg, _ext}}) catch _p", .{label});
        }
    }.emit);
}

fn genPathRelativeTo(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len < 1) return error.UnsupportedSyntax;
    const Ctx = struct { o: ast.Node, a: ast.Node };
    try self.withInlineBlock("path_rel", Ctx{ .o = obj, .a = args[0] }, struct {
        fn emit(s: *NativeCodegen, label: []const u8, ctx: Ctx) CodegenError!void {
            try s.emit("const _p = ");
            try s.genExpr(ctx.o);
            try s.emit("; const _arg = ");
            try s.genExpr(ctx.a);
            try s.emitFmt("; _ = _arg; break :{s} _p", .{label});
        }
    }.emit);
}

fn genPathStem(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.withInlineBlock("path_stem", obj, struct {
        fn emit(s: *NativeCodegen, label: []const u8, o: ast.Node) CodegenError!void {
            try s.emit("const _p = ");
            try s.genExpr(o);
            try s.emitFmt("; const _n = std.fs.path.basename(_p); const _e = std.fs.path.extension(_n); break :{s} if (_e.len > 0) _n[0.._n.len - _e.len] else _n", .{label});
        }
    }.emit);
}

fn genPathSuffixes(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.withInlineBlock("path_suffixes", obj, struct {
        fn emit(s: *NativeCodegen, label: []const u8, o: ast.Node) CodegenError!void {
            try s.emit("const _p = ");
            try s.genExpr(o);
            try s.emitFmt("; var _s: std.ArrayList([]const u8) = .{{}}; const _n = std.fs.path.basename(_p); var _i: usize = 0; while (_i < _n.len) : (_i += 1) {{ if (_n[_i] == '.') {{ _s.append(__global_allocator, _n[_i..]) catch continue; break; }} }} break :{s} _s.items", .{label});
        }
    }.emit);
}

fn genPathParents(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.withInlineBlock("path_parents", obj, struct {
        fn emit(s: *NativeCodegen, label: []const u8, o: ast.Node) CodegenError!void {
            try s.emit("const _p = ");
            try s.genExpr(o);
            try s.emitFmt("; var _ps: std.ArrayList([]const u8) = .{{}}; var _cur = _p; while (std.fs.path.dirname(_cur)) |_d| {{ _ps.append(__global_allocator, _d) catch break; _cur = _d; }} break :{s} _ps.items", .{label});
        }
    }.emit);
}

fn genPathParts(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.withInlineBlock("path_parts", obj, struct {
        fn emit(s: *NativeCodegen, label: []const u8, o: ast.Node) CodegenError!void {
            try s.emit("const _p = ");
            try s.genExpr(o);
            try s.emitFmt("; var _ps: std.ArrayList([]const u8) = .{{}}; var _it = std.mem.splitScalar(u8, _p, '/'); while (_it.next()) |_part| {{ if (_part.len > 0) _ps.append(__global_allocator, _part) catch continue; }} break :{s} _ps.items", .{label});
        }
    }.emit);
}

fn genPathAnchor(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.withInlineBlock("path_anchor", obj, struct {
        fn emit(s: *NativeCodegen, label: []const u8, o: ast.Node) CodegenError!void {
            try s.emit("const _p = ");
            try s.genExpr(o);
            try s.emitFmt("; break :{s} if (_p.len > 0 and _p[0] == '/') \"/\" else \"\"", .{label});
        }
    }.emit);
}

fn genPathOpen(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.withInlineBlock("path_open", obj, struct {
        fn emit(s: *NativeCodegen, label: []const u8, o: ast.Node) CodegenError!void {
            try s.emit("const _p = ");
            try s.genExpr(o);
            try s.emitFmt("; break :{s} try runtime.PyFile.open(_p, \"r\", __global_allocator)", .{label});
        }
    }.emit);
}
