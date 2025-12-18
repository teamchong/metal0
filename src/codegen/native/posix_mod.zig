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
    const label = try self.emitInlineBlockStart("getcwd");
    try self.emitFmt("var buf: [4096]u8 = undefined; break :{s} std.fs.cwd().realpath(\".\", &buf) catch \".\"; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genChdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("{}");
        return;
    }
    const label = try self.emitInlineBlockStart("chdir");
    try self.emit("const path = ");
    try self.genExpr(args[0]);
    try self.emitFmt("; std.posix.chdir(path) catch unreachable; break :{s} {{}}; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genMkdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("{}");
        return;
    }
    const label = try self.emitInlineBlockStart("mkdir");
    try self.emit("const path = ");
    try self.genExpr(args[0]);
    try self.emitFmt("; std.fs.cwd().makeDir(path) catch unreachable; break :{s} {{}}; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genRmdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("{}");
        return;
    }
    const label = try self.emitInlineBlockStart("rmdir");
    try self.emit("const path = ");
    try self.genExpr(args[0]);
    try self.emitFmt("; std.fs.cwd().deleteDir(path) catch unreachable; break :{s} {{}}; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genUnlink(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("{}");
        return;
    }
    const label = try self.emitInlineBlockStart("unlink");
    try self.emit("const path = ");
    try self.genExpr(args[0]);
    try self.emitFmt("; std.fs.cwd().deleteFile(path) catch unreachable; break :{s} {{}}; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genRename(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("{}");
        return;
    }
    const label = try self.emitInlineBlockStart("rename");
    try self.emit("const src = ");
    try self.genExpr(args[0]);
    try self.emit("; const dst = ");
    try self.genExpr(args[1]);
    try self.emitFmt("; std.fs.cwd().rename(src, dst) catch unreachable; break :{s} {{}}; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genStat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit(statDefault);
        return;
    }
    const label = try self.emitInlineBlockStart("stat");
    try self.emit("const path = ");
    try self.genExpr(args[0]);
    try self.emitFmt("; const stat = std.fs.cwd().statFile(path) catch break :{s} ", .{label});
    try self.emit(statDefault);
    try self.emitFmt("; break :{s} .{{ .st_size = @intCast(stat.size), .st_mode = @intCast(@intFromEnum(stat.kind)) }}; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genGetenv(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(?[]const u8, null)");
        return;
    }
    const label = try self.emitInlineBlockStart("getenv");
    try self.emit("const path = ");
    try self.genExpr(args[0]);
    try self.emitFmt("; _ = path; break :{s} if (comptime @import(\"builtin\").os.tag == .windows) @as(?[]const u8, null) else std.posix.getenv(path); ", .{label});
    try self.emitInlineBlockEnd();
}

fn genKill(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("{}");
        return;
    }
    const label = try self.emitInlineBlockStart("kill");
    try self.emit("const pid = ");
    try self.genExpr(args[0]);
    try self.emit("; const sig = ");
    try self.genExpr(args[1]);
    try self.emitFmt("; _ = std.c.kill(@intCast(pid), @intCast(sig)); break :{s} {{}}; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(i32, -1)");
        return;
    }
    const label = try self.emitInlineBlockStart("open");
    try self.emit("const path = ");
    try self.genExpr(args[0]);
    try self.emitFmt("; const file = std.fs.cwd().openFile(path, .{{}}) catch break :{s} @as(i32, -1); break :{s} if (comptime @import(\"builtin\").os.tag == .windows) @as(i32, @truncate(@as(i64, @intFromPtr(file.handle)))) else @intCast(file.handle); ", .{ label, label });
    try self.emitInlineBlockEnd();
}

fn genClose(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("{}");
        return;
    }
    const label = try self.emitInlineBlockStart("close");
    try self.emit("const fd = ");
    try self.genExpr(args[0]);
    try self.emitFmt("; std.posix.close(@intCast(fd)); break :{s} {{}}; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genAccess(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("false");
        return;
    }
    const label = try self.emitInlineBlockStart("access");
    try self.emit("const path = ");
    try self.genExpr(args[0]);
    try self.emitFmt("; _ = std.fs.cwd().statFile(path) catch break :{s} false; break :{s} true; ", .{ label, label });
    try self.emitInlineBlockEnd();
}

fn genSymlink(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("{}");
        return;
    }
    const label = try self.emitInlineBlockStart("symlink");
    try self.emit("const src = ");
    try self.genExpr(args[0]);
    try self.emit("; const dst = ");
    try self.genExpr(args[1]);
    try self.emitFmt("; std.fs.cwd().symLink(src, dst, .{{}}) catch unreachable; break :{s} {{}}; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genReadlink(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("\"\"");
        return;
    }
    const label = try self.emitInlineBlockStart("readlink");
    try self.emit("const path = ");
    try self.genExpr(args[0]);
    try self.emitFmt("; var buf: [4096]u8 = undefined; break :{s} std.fs.cwd().readLink(path, &buf) catch \"\"; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genUrandom(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("\"\"");
        return;
    }
    const label = try self.emitInlineBlockStart("urandom");
    try self.emit("const n = ");
    try self.genExpr(args[0]);
    try self.emitFmt("; var buf = __global_allocator.alloc(u8, @intCast(n)) catch break :{s} \"\"; std.crypto.random.bytes(buf); break :{s} buf; ", .{ label, label });
    try self.emitInlineBlockEnd();
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
