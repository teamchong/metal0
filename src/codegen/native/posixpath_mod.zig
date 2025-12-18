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
        const label = try self.emitInlineBlockStart("abspath");
        try self.emit("const path = ");
        try self.genExpr(args[0]);
        try self.emit("; var buf: [4096]u8 = undefined; ");
        try self.emitFmt("break :{s} std.fs.cwd().realpath(path, &buf) catch path; ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try self.emit("\"\"");
    }
}

fn genBasename(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("basename");
        try self.emit("const path = ");
        try self.genExpr(args[0]);
        try self.emit("; ");
        try self.emitFmt("break :{s} std.fs.path.basename(path); ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try self.emit("\"\"");
    }
}

fn genDirname(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("dirname");
        try self.emit("const path = ");
        try self.genExpr(args[0]);
        try self.emit("; ");
        try self.emitFmt("break :{s} std.fs.path.dirname(path) orelse \"\"; ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try self.emit("\"\"");
    }
}

fn genExists(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("exists");
        try self.emit("const path = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; _ = std.fs.cwd().statFile(path) catch break :{s} false; ", .{label});
        try self.emitFmt("break :{s} true; ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try self.emit("false");
    }
}

fn genExpanduser(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("expanduser");
        try self.emit("const path = ");
        try self.genExpr(args[0]);
        try self.emit("; if (path.len > 0 and path[0] == '~') { const home = if (comptime @import(\"builtin\").os.tag == .windows) \"C:\\\\Users\\\\Public\" else (std.posix.getenv(\"HOME\") orelse \"\"); ");
        try self.emitFmt("break :{s} std.fmt.allocPrint(__global_allocator, \"{{s}}{{s}}\", .{{ home, path[1..] }}) catch path; }} ", .{label});
        try self.emitFmt("break :{s} path; ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try self.emit("\"\"");
    }
}

fn genGetsize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("getsize");
        try self.emit("const path = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; const stat = std.fs.cwd().statFile(path) catch break :{s} @as(i64, 0); ", .{label});
        try self.emitFmt("break :{s} @intCast(stat.size); ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try self.emit("@as(i64, 0)");
    }
}

fn genIsabs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("isabs");
        try self.emit("const path = ");
        try self.genExpr(args[0]);
        try self.emit("; ");
        try self.emitFmt("break :{s} path.len > 0 and path[0] == '/'; ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try self.emit("false");
    }
}

fn genIsdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("isdir");
        try self.emit("const path = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; const dir = std.fs.cwd().openDir(path, .{{}}) catch break :{s} false; ", .{label});
        try self.emitFmt("dir.close(); break :{s} true; ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try self.emit("false");
    }
}

fn genIsfile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("isfile");
        try self.emit("const path = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; const stat = std.fs.cwd().statFile(path) catch break :{s} false; ", .{label});
        try self.emitFmt("break :{s} stat.kind == .file; ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try self.emit("false");
    }
}

fn genIslink(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("islink");
        try self.emit("const path = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; const stat = std.fs.cwd().statFile(path) catch break :{s} false; ", .{label});
        try self.emitFmt("break :{s} stat.kind == .sym_link; ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try self.emit("false");
    }
}

fn genJoin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("join");
        try self.emit("var parts: [16][]const u8 = undefined; var count: usize = 0; ");
        for (args, 0..) |arg, i| {
            try self.emitFmt("parts[{d}] = ", .{i});
            try self.genExpr(arg);
            try self.emit("; count += 1; ");
        }
        try self.emitFmt("break :{s} std.fs.path.join(__global_allocator, parts[0..count]) catch \"\"; ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try self.emit("\"\"");
    }
}

fn genLexists(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("lexists");
        try self.emit("const path = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; _ = std.fs.cwd().statFile(path) catch break :{s} false; ", .{label});
        try self.emitFmt("break :{s} true; ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try self.emit("false");
    }
}

fn genRealpath(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("realpath");
        try self.emit("const path = ");
        try self.genExpr(args[0]);
        try self.emit("; var buf: [4096]u8 = undefined; ");
        try self.emitFmt("break :{s} std.fs.cwd().realpath(path, &buf) catch path; ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try self.emit("\"\"");
    }
}

fn genSamefile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        const label = try self.emitInlineBlockStart("samefile");
        try self.emit("const p1 = ");
        try self.genExpr(args[0]);
        try self.emit("; const p2 = ");
        try self.genExpr(args[1]);
        try self.emit("; ");
        try self.emitFmt("break :{s} std.mem.eql(u8, p1, p2); ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try self.emit("false");
    }
}

fn genSplit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("split");
        try self.emit("const path = ");
        try self.genExpr(args[0]);
        try self.emit("; const dir = std.fs.path.dirname(path) orelse \"\"; const base = std.fs.path.basename(path); ");
        try self.emitFmt("break :{s} .{{ dir, base }}; ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try self.emit(".{ \"\", \"\" }");
    }
}

fn genSplitdrive(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("splitdrive");
        try self.emit("const path = ");
        try self.genExpr(args[0]);
        try self.emit("; ");
        try self.emitFmt("break :{s} .{{ \"\", path }}; ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try self.emit(".{ \"\", \"\" }");
    }
}

fn genSplitext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("splitext");
        try self.emit("const path = ");
        try self.genExpr(args[0]);
        try self.emit("; const ext = std.fs.path.extension(path); const stem_len = path.len - ext.len; ");
        try self.emitFmt("break :{s} .{{ path[0..stem_len], ext }}; ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try self.emit(".{ \"\", \"\" }");
    }
}
