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
    try self.withInlineBlock("getcwd", &.{}, struct {
        fn emit(c: *NativeCodegen, label: []const u8, _: []ast.Node) !void {
            try c.emitFmt("var buf: [4096]u8 = undefined; break :{s} std.fs.cwd().realpath(\".\", &buf) catch \".\"; ", .{label});
        }
    }.emit);
}

fn genChdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("{}");
        return;
    }
    try self.withInlineBlock("chdir", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const path = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; std.posix.chdir(path) catch unreachable; break :{s} {{}}; ", .{label});
        }
    }.emit);
}

fn genMkdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("{}");
        return;
    }
    try self.withInlineBlock("mkdir", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const path = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; std.fs.cwd().makeDir(path) catch unreachable; break :{s} {{}}; ", .{label});
        }
    }.emit);
}

fn genRmdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("{}");
        return;
    }
    try self.withInlineBlock("rmdir", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const path = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; std.fs.cwd().deleteDir(path) catch unreachable; break :{s} {{}}; ", .{label});
        }
    }.emit);
}

fn genUnlink(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("{}");
        return;
    }
    try self.withInlineBlock("unlink", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const path = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; std.fs.cwd().deleteFile(path) catch unreachable; break :{s} {{}}; ", .{label});
        }
    }.emit);
}

fn genRename(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("{}");
        return;
    }
    try self.withInlineBlock("rename", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const src = ");
            try c.genExpr(a[0]);
            try c.emit("; const dst = ");
            try c.genExpr(a[1]);
            try c.emitFmt("; std.fs.cwd().rename(src, dst) catch unreachable; break :{s} {{}}; ", .{label});
        }
    }.emit);
}

fn genStat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit(statDefault);
        return;
    }
    try self.withInlineBlock("stat", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const path = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; const stat = std.fs.cwd().statFile(path) catch break :{s} .{{ .st_size = 0, .st_mode = 0 }}; break :{s} .{{ .st_size = @intCast(stat.size), .st_mode = @intCast(@intFromEnum(stat.kind)) }}; ", .{ label, label });
        }
    }.emit);
}

fn genGetenv(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(?[]const u8, null)");
        return;
    }
    try self.withInlineBlock("getenv", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const path = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; _ = path; break :{s} if (comptime @import(\"builtin\").os.tag == .windows) @as(?[]const u8, null) else std.posix.getenv(path); ", .{label});
        }
    }.emit);
}

fn genKill(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("{}");
        return;
    }
    try self.withInlineBlock("kill", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const pid = ");
            try c.genExpr(a[0]);
            try c.emit("; const sig = ");
            try c.genExpr(a[1]);
            try c.emitFmt("; _ = std.c.kill(@intCast(pid), @intCast(sig)); break :{s} {{}}; ", .{label});
        }
    }.emit);
}

fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(i32, -1)");
        return;
    }
    try self.withInlineBlock("open", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const path = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; const file = std.fs.cwd().openFile(path, .{{}}) catch break :{s} @as(i32, -1); break :{s} if (comptime @import(\"builtin\").os.tag == .windows) @as(i32, @truncate(@as(i64, @intFromPtr(file.handle)))) else @intCast(file.handle); ", .{ label, label });
        }
    }.emit);
}

fn genClose(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("{}");
        return;
    }
    try self.withInlineBlock("close", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const fd = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; std.posix.close(@intCast(fd)); break :{s} {{}}; ", .{label});
        }
    }.emit);
}

fn genAccess(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("false");
        return;
    }
    try self.withInlineBlock("access", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const path = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; _ = std.fs.cwd().statFile(path) catch break :{s} false; break :{s} true; ", .{ label, label });
        }
    }.emit);
}

fn genSymlink(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("{}");
        return;
    }
    try self.withInlineBlock("symlink", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const src = ");
            try c.genExpr(a[0]);
            try c.emit("; const dst = ");
            try c.genExpr(a[1]);
            try c.emitFmt("; std.fs.cwd().symLink(src, dst, .{{}}) catch unreachable; break :{s} {{}}; ", .{label});
        }
    }.emit);
}

fn genReadlink(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("\"\"");
        return;
    }
    try self.withInlineBlock("readlink", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const path = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; var buf: [4096]u8 = undefined; break :{s} std.fs.cwd().readLink(path, &buf) catch \"\"; ", .{label});
        }
    }.emit);
}

fn genUrandom(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("\"\"");
        return;
    }
    try self.withInlineBlock("urandom", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const n = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; var buf = __global_allocator.alloc(u8, @intCast(n)) catch break :{s} \"\"; std.crypto.random.bytes(buf); break :{s} buf; ", .{ label, label });
        }
    }.emit);
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
