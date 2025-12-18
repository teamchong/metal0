/// Python posixpath module - POSIX pathname functions
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "abspath", genAbspath },
    .{ "basename", genBasename },
    .{ "dirname", genDirname },
    .{ "exists", genExists },
    .{ "expanduser", genExpanduser },
    .{ "expandvars", h.pass("\"\"") },
    .{ "getsize", genGetsize },
    .{ "isabs", genIsabs },
    .{ "isdir", genIsdir },
    .{ "isfile", genIsfile },
    .{ "islink", genIslink },
    .{ "join", genJoin },
    .{ "lexists", genLexists },
    .{ "normcase", h.pass("\"\"") }, .{ "normpath", h.pass("\"\"") },
    .{ "realpath", genRealpath },
    .{ "relpath", h.pass("\"\"") },
    .{ "samefile", genSamefile },
    .{ "split", genSplit },
    .{ "splitdrive", genSplitdrive },
    .{ "splitext", genSplitext },
    .{ "commonpath", h.c("\"\"") }, .{ "commonprefix", h.c("\"\"") },
    .{ "getatime", h.F64(0.0) }, .{ "getctime", h.F64(0.0) }, .{ "getmtime", h.F64(0.0) },
    .{ "ismount", h.c("false") }, .{ "sameopenfile", h.c("false") }, .{ "samestat", h.c("false") },
    .{ "sep", h.c("\"/\"") }, .{ "altsep", h.c("@as(?[]const u8, null)") }, .{ "extsep", h.c("\".\"") },
    .{ "pathsep", h.c("\":\"") }, .{ "defpath", h.c("\"/bin:/usr/bin\"") }, .{ "devnull", h.c("\"/dev/null\"") },
    .{ "curdir", h.c("\".\"") }, .{ "pardir", h.c("\"..\"") },
});

fn genAbspath(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_abspath: {{ const path = ", .{id});
        try self.genExpr(args[0]);
        try self.emitFmt("; var buf: [4096]u8 = undefined; break :__m{d}_abspath std.fs.cwd().realpath(path, &buf) catch path; }}", .{id});
    } else {
        try self.emit("\"\"");
    }
}

fn genBasename(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_basename: {{ const path = ", .{id});
        try self.genExpr(args[0]);
        try self.emitFmt("; break :__m{d}_basename std.fs.path.basename(path); }}", .{id});
    } else {
        try self.emit("\"\"");
    }
}

fn genDirname(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_dirname: {{ const path = ", .{id});
        try self.genExpr(args[0]);
        try self.emitFmt("; break :__m{d}_dirname std.fs.path.dirname(path) orelse \"\"; }}", .{id});
    } else {
        try self.emit("\"\"");
    }
}

fn genExists(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_exists: {{ const path = ", .{id});
        try self.genExpr(args[0]);
        try self.emitFmt("; _ = std.fs.cwd().statFile(path) catch break :__m{d}_exists false; break :__m{d}_exists true; }}", .{ id, id });
    } else {
        try self.emit("false");
    }
}

fn genExpanduser(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_expanduser: {{ const path = ", .{id});
        try self.genExpr(args[0]);
        try self.emit("; if (path.len > 0 and path[0] == '~') { const home = if (comptime @import(\"builtin\").os.tag == .windows) \"C:\\\\Users\\\\Public\" else (std.posix.getenv(\"HOME\") orelse \"\"); break :__m");
        try self.emitFmt("{d}_expanduser std.fmt.allocPrint(__global_allocator, \"{{s}}{{s}}\", .{{ home, path[1..] }}) catch path; }} break :__m{d}_expanduser path; }}", .{ id, id });
    } else {
        try self.emit("\"\"");
    }
}

fn genGetsize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_getsize: {{ const path = ", .{id});
        try self.genExpr(args[0]);
        try self.emitFmt("; const stat = std.fs.cwd().statFile(path) catch break :__m{d}_getsize @as(i64, 0); break :__m{d}_getsize @intCast(stat.size); }}", .{ id, id });
    } else {
        try self.emit("@as(i64, 0)");
    }
}

fn genIsabs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_isabs: {{ const path = ", .{id});
        try self.genExpr(args[0]);
        try self.emitFmt("; break :__m{d}_isabs path.len > 0 and path[0] == '/'; }}", .{id});
    } else {
        try self.emit("false");
    }
}

fn genIsdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_isdir: {{ const path = ", .{id});
        try self.genExpr(args[0]);
        try self.emit("; const dir = std.fs.cwd().openDir(path, .{}) catch break :__m");
        try self.emitFmt("{d}_isdir false; dir.close(); break :__m{d}_isdir true; }}", .{ id, id });
    } else {
        try self.emit("false");
    }
}

fn genIsfile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_isfile: {{ const path = ", .{id});
        try self.genExpr(args[0]);
        try self.emitFmt("; const stat = std.fs.cwd().statFile(path) catch break :__m{d}_isfile false; break :__m{d}_isfile stat.kind == .file; }}", .{ id, id });
    } else {
        try self.emit("false");
    }
}

fn genIslink(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_islink: {{ const path = ", .{id});
        try self.genExpr(args[0]);
        try self.emitFmt("; const stat = std.fs.cwd().statFile(path) catch break :__m{d}_islink false; break :__m{d}_islink stat.kind == .sym_link; }}", .{ id, id });
    } else {
        try self.emit("false");
    }
}

fn genJoin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_join: {{ var parts: [16][]const u8 = undefined; var count: usize = 0; ", .{id});
        for (args, 0..) |arg, i| {
            try self.emitFmt("parts[{d}] = ", .{i});
            try self.genExpr(arg);
            try self.emit("; count += 1; ");
        }
        try self.emitFmt("break :__m{d}_join std.fs.path.join(__global_allocator, parts[0..count]) catch \"\"; }}", .{id});
    } else {
        try self.emit("\"\"");
    }
}

fn genLexists(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_lexists: {{ const path = ", .{id});
        try self.genExpr(args[0]);
        try self.emitFmt("; _ = std.fs.cwd().statFile(path) catch break :__m{d}_lexists false; break :__m{d}_lexists true; }}", .{ id, id });
    } else {
        try self.emit("false");
    }
}

fn genRealpath(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_realpath: {{ const path = ", .{id});
        try self.genExpr(args[0]);
        try self.emitFmt("; var buf: [4096]u8 = undefined; break :__m{d}_realpath std.fs.cwd().realpath(path, &buf) catch path; }}", .{id});
    } else {
        try self.emit("\"\"");
    }
}

fn genSamefile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_samefile: {{ const p1 = ", .{id});
        try self.genExpr(args[0]);
        try self.emit("; const p2 = ");
        try self.genExpr(args[1]);
        try self.emitFmt("; break :__m{d}_samefile std.mem.eql(u8, p1, p2); }}", .{id});
    } else {
        try self.emit("false");
    }
}

fn genSplit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_split: {{ const path = ", .{id});
        try self.genExpr(args[0]);
        try self.emit("; const dir = std.fs.path.dirname(path) orelse \"\"; const base = std.fs.path.basename(path); break :__m");
        try self.emitFmt("{d}_split .{{ dir, base }}; }}", .{id});
    } else {
        try self.emit(".{ \"\", \"\" }");
    }
}

fn genSplitdrive(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_splitdrive: {{ const path = ", .{id});
        try self.genExpr(args[0]);
        try self.emit("; break :__m");
        try self.emitFmt("{d}_splitdrive .{{ \"\", path }}; }}", .{id});
    } else {
        try self.emit(".{ \"\", \"\" }");
    }
}

fn genSplitext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_splitext: {{ const path = ", .{id});
        try self.genExpr(args[0]);
        try self.emit("; const ext = std.fs.path.extension(path); const stem_len = path.len - ext.len; break :__m");
        try self.emitFmt("{d}_splitext .{{ path[0..stem_len], ext }}; }}", .{id});
    } else {
        try self.emit(".{ \"\", \"\" }");
    }
}
