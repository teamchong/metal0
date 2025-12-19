/// Python ntpath module - Windows pathname functions
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

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
    .{ "normcase", genNormcase },
    .{ "normpath", h.pass("\"\"") },
    .{ "realpath", genRealpath },
    .{ "relpath", h.pass("\"\"") },
    .{ "samefile", genSamefile },
    .{ "split", genSplit },
    .{ "splitdrive", genSplitdrive },
    .{ "splitext", genSplitext },
    .{ "commonpath", h.c("\"\"") }, .{ "commonprefix", h.c("\"\"") },
    .{ "getatime", h.F64(0.0) }, .{ "getctime", h.F64(0.0) }, .{ "getmtime", h.F64(0.0) },
    .{ "ismount", h.c("false") }, .{ "sameopenfile", h.c("false") }, .{ "samestat", h.c("false") },
    .{ "sep", h.c("\"\\\\\"") }, .{ "altsep", h.c("\"/\"") }, .{ "extsep", h.c("\".\"") },
    .{ "pathsep", h.c("\";\"") }, .{ "defpath", h.c("\".;C:\\\\bin\"") }, .{ "devnull", h.c("\"nul\"") },
    .{ "curdir", h.c("\".\"") }, .{ "pardir", h.c("\"..\"") },
});

fn genAbspath(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("abspath", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const path = ");
                try c.genExpr(a[0]);
                {
                    const b = try c.getBuilder();
                    try b.writeFmt("; var buf: [4096]u8 = undefined; const result = std.fs.cwd().realpath(path, &buf) catch path; break :{s} result; ", .{label});
                    const output = b.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output);
                }
            }
        }.emit);
    } else try emitConst(self, "\"\"");
}

fn genBasename(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("basename", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const path = ");
                try c.genExpr(a[0]);
                {
                    const b = try c.getBuilder();
                    try b.writeFmt("; const result = std.fs.path.basename(path); break :{s} result; ", .{label});
                    const output = b.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output);
                }
            }
        }.emit);
    } else try emitConst(self, "\"\"");
}

fn genDirname(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("dirname", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const path = ");
                try c.genExpr(a[0]);
                {
                    const b = try c.getBuilder();
                    try b.writeFmt("; const result = std.fs.path.dirname(path) orelse \"\"; break :{s} result; ", .{label});
                    const output = b.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output);
                }
            }
        }.emit);
    } else try emitConst(self, "\"\"");
}

fn genExists(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("exists", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const path = ");
                try c.genExpr(a[0]);
                {
                    const b = try c.getBuilder();
                    try b.writeFmt("; _ = std.fs.cwd().statFile(path) catch {{ break :{s} false; }}; const result = true; break :{s} result; ", .{ label, label });
                    const output = b.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output);
                }
            }
        }.emit);
    } else try emitConst(self, "false");
}

fn genExpanduser(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("expanduser", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const path = ");
                try c.genExpr(a[0]);
                {
                    const b = try c.getBuilder();
                    try b.writeFmt("; const result = if (path.len > 0 and path[0] == '~') blk: {{ const home = if (comptime @import(\"builtin\").os.tag == .windows) \"C:\\\\Users\\\\Public\" else (std.posix.getenv(\"HOME\") orelse \"\"); break :blk std.fmt.allocPrint(__global_allocator, \"{{s}}{{s}}\", .{{ home, path[1..] }}) catch path; }} else path; break :{s} result; ", .{label});
                    const output = b.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output);
                }
            }
        }.emit);
    } else try emitConst(self, "\"\"");
}

fn genGetsize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("getsize", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const path = ");
                try c.genExpr(a[0]);
                {
                    const b = try c.getBuilder();
                    try b.writeFmt("; const stat = std.fs.cwd().statFile(path) catch {{ break :{s} @as(i64, 0); }}; const result: i64 = @intCast(stat.size); break :{s} result; ", .{ label, label });
                    const output = b.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output);
                }
            }
        }.emit);
    } else try emitConst(self, "@as(i64, 0)");
}

fn genIsabs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("isabs", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const path = ");
                try c.genExpr(a[0]);
                {
                    const b = try c.getBuilder();
                    try b.writeFmt("; const result = (path.len > 0 and path[0] == '/') or (path.len > 2 and path[1] == ':'); break :{s} result; ", .{label});
                    const output = b.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output);
                }
            }
        }.emit);
    } else try emitConst(self, "false");
}

fn genIsdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("isdir", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const path = ");
                try c.genExpr(a[0]);
                {
                    const b = try c.getBuilder();
                    try b.writeFmt("; const dir = std.fs.cwd().openDir(path, .{{}}) catch {{ break :{s} false; }}; dir.close(); const result = true; break :{s} result; ", .{ label, label });
                    const output = b.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output);
                }
            }
        }.emit);
    } else try emitConst(self, "false");
}

fn genIsfile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("isfile", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const path = ");
                try c.genExpr(a[0]);
                {
                    const b = try c.getBuilder();
                    try b.writeFmt("; const stat = std.fs.cwd().statFile(path) catch {{ break :{s} false; }}; const result = stat.kind == .file; break :{s} result; ", .{ label, label });
                    const output = b.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output);
                }
            }
        }.emit);
    } else try emitConst(self, "false");
}

fn genIslink(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("islink", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const path = ");
                try c.genExpr(a[0]);
                {
                    const b = try c.getBuilder();
                    try b.writeFmt("; const stat = std.fs.cwd().statFile(path) catch {{ break :{s} false; }}; const result = stat.kind == .sym_link; break :{s} result; ", .{ label, label });
                    const output = b.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output);
                }
            }
        }.emit);
    } else try emitConst(self, "false");
}

fn genJoin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("join", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "var parts: [16][]const u8 = undefined; var count: usize = 0; ");
                for (a, 0..) |arg, i| {
                    {
                        const b = try c.getBuilder();
                        try b.writeFmt("parts[{d}] = ", .{i});
                        const output = b.getBodyAndClear();
                        try c.output.appendSlice(c.allocator, output);
                    }
                    try c.genExpr(arg);
                    try emitConst(c, "; count += 1; ");
                }
                {
                    const b = try c.getBuilder();
                    try b.writeFmt("const result = std.fs.path.join(__global_allocator, parts[0..count]) catch \"\"; break :{s} result; ", .{label});
                    const output = b.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output);
                }
            }
        }.emit);
    } else try emitConst(self, "\"\"");
}

fn genLexists(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("lexists", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const path = ");
                try c.genExpr(a[0]);
                {
                    const b = try c.getBuilder();
                    try b.writeFmt("; _ = std.fs.cwd().statFile(path) catch {{ break :{s} false; }}; const result = true; break :{s} result; ", .{ label, label });
                    const output = b.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output);
                }
            }
        }.emit);
    } else try emitConst(self, "false");
}

fn genNormcase(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("normcase", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const path = ");
                try c.genExpr(a[0]);
                {
                    const b = try c.getBuilder();
                    try b.writeFmt("; var result = __global_allocator.alloc(u8, path.len) catch {{ break :{s} path; }}; for (path, 0..) |ch, i| {{ result[i] = if (ch >= 'A' and ch <= 'Z') ch + 32 else if (ch == '/') '\\\\' else ch; }} break :{s} result; ", .{ label, label });
                    const output = b.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output);
                }
            }
        }.emit);
    } else try emitConst(self, "\"\"");
}

fn genRealpath(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("realpath", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const path = ");
                try c.genExpr(a[0]);
                {
                    const b = try c.getBuilder();
                    try b.writeFmt("; var buf: [4096]u8 = undefined; const result = std.fs.cwd().realpath(path, &buf) catch path; break :{s} result; ", .{label});
                    const output = b.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output);
                }
            }
        }.emit);
    } else try emitConst(self, "\"\"");
}

fn genSamefile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.withInlineBlock("samefile", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const p1 = ");
                try c.genExpr(a[0]);
                try emitConst(c, "; const p2 = ");
                try c.genExpr(a[1]);
                {
                    const b = try c.getBuilder();
                    try b.writeFmt("; const result = std.mem.eql(u8, p1, p2); break :{s} result; ", .{label});
                    const output = b.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output);
                }
            }
        }.emit);
    } else try emitConst(self, "false");
}

fn genSplit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("split", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const path = ");
                try c.genExpr(a[0]);
                {
                    const b = try c.getBuilder();
                    try b.writeFmt("; const dir = std.fs.path.dirname(path) orelse \"\"; const base = std.fs.path.basename(path); const result = .{{ dir, base }}; break :{s} result; ", .{label});
                    const output = b.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output);
                }
            }
        }.emit);
    } else try emitConst(self, ".{ \"\", \"\" }");
}

fn genSplitdrive(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("splitdrive", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const path = ");
                try c.genExpr(a[0]);
                {
                    const b = try c.getBuilder();
                    try b.writeFmt("; const result = if (path.len >= 2 and path[1] == ':') .{{ path[0..2], path[2..] }} else .{{ \"\", path }}; break :{s} result; ", .{label});
                    const output = b.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output);
                }
            }
        }.emit);
    } else try emitConst(self, ".{ \"\", \"\" }");
}

fn genSplitext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("splitext", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const path = ");
                try c.genExpr(a[0]);
                {
                    const b = try c.getBuilder();
                    try b.writeFmt("; const ext = std.fs.path.extension(path); const stem_len = path.len - ext.len; const result = .{{ path[0..stem_len], ext }}; break :{s} result; ", .{label});
                    const output = b.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output);
                }
            }
        }.emit);
    } else try emitConst(self, ".{ \"\", \"\" }");
}
