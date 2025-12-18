/// Python posix module - POSIX system calls (low-level os operations)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const ast = @import("analysis.ast");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

const statDefault = ".{ .st_size = 0, .st_mode = 0 }";

// Runtime generator functions with unique block IDs

fn genGetcwd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_getcwd: {{ var buf: [4096]u8 = undefined; break :__m{d}_getcwd std.fs.cwd().realpath(\".\", &buf) catch \".\"; }}", .{ id, id });
}

fn genChdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("{}");
        return;
    }
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_chdir: {{ const path = ", .{id});
    try self.genExpr(args[0]);
    try self.emitFmt("; std.posix.chdir(path) catch unreachable; break :__m{d}_chdir {{}}; }}", .{id});
}

fn genMkdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("{}");
        return;
    }
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_mkdir: {{ const path = ", .{id});
    try self.genExpr(args[0]);
    try self.emitFmt("; std.fs.cwd().makeDir(path) catch unreachable; break :__m{d}_mkdir {{}}; }}", .{id});
}

fn genRmdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("{}");
        return;
    }
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_rmdir: {{ const path = ", .{id});
    try self.genExpr(args[0]);
    try self.emitFmt("; std.fs.cwd().deleteDir(path) catch unreachable; break :__m{d}_rmdir {{}}; }}", .{id});
}

fn genUnlink(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("{}");
        return;
    }
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_unlink: {{ const path = ", .{id});
    try self.genExpr(args[0]);
    try self.emitFmt("; std.fs.cwd().deleteFile(path) catch unreachable; break :__m{d}_unlink {{}}; }}", .{id});
}

fn genRename(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("{}");
        return;
    }
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_rename: {{ const src = ", .{id});
    try self.genExpr(args[0]);
    try self.emit("; const dst = ");
    try self.genExpr(args[1]);
    try self.emitFmt("; std.fs.cwd().rename(src, dst) catch unreachable; break :__m{d}_rename {{}}; }}", .{id});
}

fn genStat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit(statDefault);
        return;
    }
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_stat: {{ const path = ", .{id});
    try self.genExpr(args[0]);
    try self.emitFmt("; const stat = std.fs.cwd().statFile(path) catch break :__m{d}_stat ", .{id});
    try self.emit(statDefault);
    try self.emitFmt("; break :__m{d}_stat .{{ .st_size = @intCast(stat.size), .st_mode = @intCast(@intFromEnum(stat.kind)) }}; }}", .{id});
}

fn genGetenv(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(?[]const u8, null)");
        return;
    }
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_getenv: {{ const path = ", .{id});
    try self.genExpr(args[0]);
    try self.emitFmt("; _ = path; break :__m{d}_getenv if (comptime @import(\"builtin\").os.tag == .windows) @as(?[]const u8, null) else std.posix.getenv(path); }}", .{id});
}

fn genKill(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("{}");
        return;
    }
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_kill: {{ const pid = ", .{id});
    try self.genExpr(args[0]);
    try self.emit("; const sig = ");
    try self.genExpr(args[1]);
    try self.emitFmt("; _ = std.c.kill(@intCast(pid), @intCast(sig)); break :__m{d}_kill {{}}; }}", .{id});
}

fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(i32, -1)");
        return;
    }
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_open: {{ const path = ", .{id});
    try self.genExpr(args[0]);
    try self.emitFmt("; const file = std.fs.cwd().openFile(path, .{{}}) catch break :__m{d}_open @as(i32, -1); break :__m{d}_open if (comptime @import(\"builtin\").os.tag == .windows) @as(i32, @truncate(@as(i64, @intFromPtr(file.handle)))) else @intCast(file.handle); }}", .{ id, id });
}

fn genClose(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("{}");
        return;
    }
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_close: {{ const fd = ", .{id});
    try self.genExpr(args[0]);
    try self.emitFmt("; std.posix.close(@intCast(fd)); break :__m{d}_close {{}}; }}", .{id});
}

fn genAccess(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("false");
        return;
    }
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_access: {{ const path = ", .{id});
    try self.genExpr(args[0]);
    try self.emitFmt("; _ = std.fs.cwd().statFile(path) catch break :__m{d}_access false; break :__m{d}_access true; }}", .{ id, id });
}

fn genSymlink(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("{}");
        return;
    }
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_symlink: {{ const src = ", .{id});
    try self.genExpr(args[0]);
    try self.emit("; const dst = ");
    try self.genExpr(args[1]);
    try self.emitFmt("; std.fs.cwd().symLink(src, dst, .{{}}) catch unreachable; break :__m{d}_symlink {{}}; }}", .{id});
}

fn genReadlink(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("\"\"");
        return;
    }
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_readlink: {{ const path = ", .{id});
    try self.genExpr(args[0]);
    try self.emitFmt("; var buf: [4096]u8 = undefined; break :__m{d}_readlink std.fs.cwd().readLink(path, &buf) catch \"\"; }}", .{id});
}

fn genUrandom(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("\"\"");
        return;
    }
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_urandom: {{ const n = ", .{id});
    try self.genExpr(args[0]);
    try self.emitFmt("; var buf = __global_allocator.alloc(u8, @intCast(n)) catch break :__m{d}_urandom \"\"; std.crypto.random.bytes(buf); break :__m{d}_urandom buf; }}", .{ id, id });
}

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getcwd", genGetcwd },
    .{ "chdir", genChdir },
    .{ "listdir", h.c("runtime.NativeList.init()") },
    .{ "mkdir", genMkdir },
    .{ "rmdir", genRmdir },
    .{ "unlink", genUnlink },
    .{ "rename", genRename },
    .{ "stat", genStat },
    .{ "lstat", genStat },
    .{ "getenv", genGetenv },
    .{ "kill", genKill },
    .{ "open", genOpen },
    .{ "close", genClose },
    .{ "access", genAccess },
    .{ "symlink", genSymlink },
    .{ "readlink", genReadlink },
    .{ "urandom", genUrandom },
    .{ "fstat", h.c(statDefault) },
    .{ "getpid", h.c("@as(i32, @intCast(std.c.getpid()))") },
    .{ "getppid", h.c("@as(i32, @intCast(std.c.getppid()))") },
    .{ "getuid", h.c("@as(u32, std.c.getuid())") },
    .{ "getgid", h.c("@as(u32, std.c.getgid())") },
    .{ "geteuid", h.c("@as(u32, std.c.geteuid())") },
    .{ "getegid", h.c("@as(u32, std.c.getegid())") },
    .{ "fork", h.c("@as(i32, @intCast(std.c.fork()))") },
    .{ "read", h.c("\"\"") },
    .{ "write", h.I64(0) },
    .{ "pipe", h.c(".{ @as(i32, -1), @as(i32, -1) }") },
    .{ "dup", h.I32(-1) },
    .{ "dup2", h.I32(-1) },
    .{ "chmod", h.c("{}") },
    .{ "chown", h.c("{}") },
    .{ "umask", h.c("@as(i32, 0o022)") },
    .{ "uname", h.c(".{ .sysname = \"Darwin\", .nodename = \"localhost\", .release = \"21.0.0\", .version = \"Darwin Kernel\", .machine = \"x86_64\" }") },
    .{ "error", h.err("OSError") },
    .{ "wait", h.c(".{ @as(i32, 0), @as(i32, 0) }") },
    .{ "waitpid", h.c(".{ @as(i32, 0), @as(i32, 0) }") },
});
