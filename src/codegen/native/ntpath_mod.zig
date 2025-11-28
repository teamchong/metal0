/// Python ntpath module - Windows pathname functions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

// ============================================================================
// NT Path Functions (Windows compatibility - mostly same as posixpath)
// ============================================================================

pub fn genAbspath(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; var buf: [4096]u8 = undefined; break :blk std.fs.cwd().realpath(path, &buf) catch path; }");
    } else {
        try self.emit("\"\"");
    }
}

pub fn genBasename(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk std.fs.path.basename(path); }");
    } else {
        try self.emit("\"\"");
    }
}

pub fn genCommonpath(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

pub fn genCommonprefix(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

pub fn genDirname(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk std.fs.path.dirname(path) orelse \"\"; }");
    } else {
        try self.emit("\"\"");
    }
}

pub fn genExists(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = std.fs.cwd().statFile(path) catch break :blk false; break :blk true; }");
    } else {
        try self.emit("false");
    }
}

pub fn genExpanduser(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; if (path.len > 0 and path[0] == '~') { const home = std.posix.getenv(\"USERPROFILE\") orelse std.posix.getenv(\"HOME\") orelse \"\"; break :blk std.fmt.allocPrint(pyaot_allocator, \"{s}{s}\", .{ home, path[1..] }) catch path; } break :blk path; }");
    } else {
        try self.emit("\"\"");
    }
}

pub fn genExpandvars(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"\"");
    }
}

pub fn genGetatime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(f64, 0.0)");
}

pub fn genGetctime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(f64, 0.0)");
}

pub fn genGetmtime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(f64, 0.0)");
}

pub fn genGetsize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; const stat = std.fs.cwd().statFile(path) catch break :blk @as(i64, 0); break :blk @intCast(stat.size); }");
    } else {
        try self.emit("@as(i64, 0)");
    }
}

pub fn genIsabs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk (path.len > 0 and path[0] == '/') or (path.len > 2 and path[1] == ':'); }");
    } else {
        try self.emit("false");
    }
}

pub fn genIsdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; const dir = std.fs.cwd().openDir(path, .{}) catch break :blk false; dir.close(); break :blk true; }");
    } else {
        try self.emit("false");
    }
}

pub fn genIsfile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; const stat = std.fs.cwd().statFile(path) catch break :blk false; break :blk stat.kind == .file; }");
    } else {
        try self.emit("false");
    }
}

pub fn genIslink(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; const stat = std.fs.cwd().statFile(path) catch break :blk false; break :blk stat.kind == .sym_link; }");
    } else {
        try self.emit("false");
    }
}

pub fn genIsmount(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

pub fn genJoin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { var parts: [16][]const u8 = undefined; var count: usize = 0; ");
        for (args, 0..) |arg, i| {
            try self.emit("parts[");
            try self.emitFmt("{}", .{i});
            try self.emit("] = ");
            try self.genExpr(arg);
            try self.emit("; count += 1; ");
        }
        try self.emit("break :blk std.fs.path.join(pyaot_allocator, parts[0..count]) catch \"\"; }");
    } else {
        try self.emit("\"\"");
    }
}

pub fn genLexists(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    return genExists(self, args);
}

pub fn genNormcase(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        // Windows: lowercase and normalize separators
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; var result = pyaot_allocator.alloc(u8, path.len) catch break :blk path; for (path, 0..) |c, i| { result[i] = if (c >= 'A' and c <= 'Z') c + 32 else if (c == '/') '\\\\' else c; } break :blk result; }");
    } else {
        try self.emit("\"\"");
    }
}

pub fn genNormpath(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"\"");
    }
}

pub fn genRealpath(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    return genAbspath(self, args);
}

pub fn genRelpath(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"\"");
    }
}

pub fn genSamefile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("blk: { const p1 = ");
        try self.genExpr(args[0]);
        try self.emit("; const p2 = ");
        try self.genExpr(args[1]);
        try self.emit("; break :blk std.mem.eql(u8, p1, p2); }");
    } else {
        try self.emit("false");
    }
}

pub fn genSameopenfile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

pub fn genSamestat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

pub fn genSplit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; const dir = std.fs.path.dirname(path) orelse \"\"; const base = std.fs.path.basename(path); break :blk .{ dir, base }; }");
    } else {
        try self.emit(".{ \"\", \"\" }");
    }
}

pub fn genSplitdrive(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; if (path.len >= 2 and path[1] == ':') { break :blk .{ path[0..2], path[2..] }; } break :blk .{ \"\", path }; }");
    } else {
        try self.emit(".{ \"\", \"\" }");
    }
}

pub fn genSplitext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; const ext = std.fs.path.extension(path); const stem_len = path.len - ext.len; break :blk .{ path[0..stem_len], ext }; }");
    } else {
        try self.emit(".{ \"\", \"\" }");
    }
}

// Windows-specific constants
pub fn genSep(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\\\\\"");
}

pub fn genAltsep(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"/\"");
}

pub fn genExtsep(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\".\"");
}

pub fn genPathsep(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\";\"");
}

pub fn genDefpath(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\".;C:\\\\bin\"");
}

pub fn genDevnull(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"nul\"");
}

pub fn genCurdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\".\"");
}

pub fn genPardir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"..\"");
}
