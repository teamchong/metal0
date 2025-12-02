/// Python posix module - POSIX system calls (low-level os operations)
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

fn genPathOp(comptime body: []const u8, comptime default: []const u8) h.H {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len > 0) { try self.emit("blk: { const path = "); try self.genExpr(args[0]); try self.emit("; " ++ body ++ " }"); } else try self.emit(default);
    } }.f;
}

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getcwd", h.c("blk: { var buf: [4096]u8 = undefined; break :blk std.fs.cwd().realpath(\".\", &buf) catch \".\"; }") },
    .{ "chdir", genPathOp("std.posix.chdir(path) catch {}; break :blk {};", "{}") },
    .{ "listdir", h.c("metal0_runtime.PyList([]const u8).init()") },
    .{ "mkdir", genPathOp("std.fs.cwd().makeDir(path) catch {}; break :blk {};", "{}") },
    .{ "rmdir", genPathOp("std.fs.cwd().deleteDir(path) catch {}; break :blk {};", "{}") },
    .{ "unlink", genPathOp("std.fs.cwd().deleteFile(path) catch {}; break :blk {};", "{}") },
    .{ "rename", genRename }, .{ "stat", genStat }, .{ "lstat", genStat },
    .{ "getenv", genPathOp("break :blk std.posix.getenv(path);", "@as(?[]const u8, null)") },
    .{ "kill", genKill }, .{ "open", genOpen }, .{ "close", genClose },
    .{ "access", genPathOp("_ = std.fs.cwd().statFile(path) catch break :blk false; break :blk true;", "false") },
    .{ "symlink", genSymlink }, .{ "readlink", genPathOp("var buf: [4096]u8 = undefined; break :blk std.fs.cwd().readLink(path, &buf) catch \"\";", "\"\"") },
    .{ "urandom", genUrandom },
    .{ "fstat", h.c(".{ .st_size = 0, .st_mode = 0 }") },
    .{ "getpid", h.c("@as(i32, @intCast(std.c.getpid()))") },
    .{ "getppid", h.c("@as(i32, @intCast(std.c.getppid()))") },
    .{ "getuid", h.c("@as(u32, std.c.getuid())") },
    .{ "getgid", h.c("@as(u32, std.c.getgid())") },
    .{ "geteuid", h.c("@as(u32, std.c.geteuid())") },
    .{ "getegid", h.c("@as(u32, std.c.getegid())") },
    .{ "fork", h.c("@as(i32, @intCast(std.c.fork()))") },
    .{ "read", h.c("\"\"") }, .{ "write", h.I64(0) },
    .{ "pipe", h.c(".{ @as(i32, -1), @as(i32, -1) }") },
    .{ "dup", h.I32(-1) }, .{ "dup2", h.I32(-1) },
    .{ "chmod", h.c("{}") }, .{ "chown", h.c("{}") },
    .{ "umask", h.c("@as(i32, 0o022)") },
    .{ "uname", h.c(".{ .sysname = \"Darwin\", .nodename = \"localhost\", .release = \"21.0.0\", .version = \"Darwin Kernel\", .machine = \"x86_64\" }") },
    .{ "error", h.err("OSError") },
    .{ "wait", h.c(".{ @as(i32, 0), @as(i32, 0) }") },
    .{ "waitpid", h.c(".{ @as(i32, 0), @as(i32, 0) }") },
});

fn genRename(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { const src = "); try self.genExpr(args[0]); try self.emit("; const dst = "); try self.genExpr(args[1]); try self.emit("; std.fs.cwd().rename(src, dst) catch {}; break :blk {}; }"); } else try self.emit("{}");
}
fn genStat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const path = "); try self.genExpr(args[0]); try self.emit("; const stat = std.fs.cwd().statFile(path) catch break :blk .{ .st_size = 0, .st_mode = 0 }; break :blk .{ .st_size = @intCast(stat.size), .st_mode = @intCast(@intFromEnum(stat.kind)) }; }"); } else try self.emit(".{ .st_size = 0, .st_mode = 0 }");
}
fn genKill(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { const pid = "); try self.genExpr(args[0]); try self.emit("; const sig = "); try self.genExpr(args[1]); try self.emit("; _ = std.c.kill(@intCast(pid), @intCast(sig)); break :blk {}; }"); } else try self.emit("{}");
}
fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const path = "); try self.genExpr(args[0]); try self.emit("; const file = std.fs.cwd().openFile(path, .{}) catch break :blk @as(i32, -1); break :blk @intCast(file.handle); }"); } else try self.emit("@as(i32, -1)");
}
fn genClose(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const fd = "); try self.genExpr(args[0]); try self.emit("; std.posix.close(@intCast(fd)); break :blk {}; }"); } else try self.emit("{}");
}
fn genSymlink(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { const src = "); try self.genExpr(args[0]); try self.emit("; const dst = "); try self.genExpr(args[1]); try self.emit("; std.fs.cwd().symLink(src, dst, .{}) catch {}; break :blk {}; }"); } else try self.emit("{}");
}
fn genUrandom(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const n = "); try self.genExpr(args[0]); try self.emit("; var buf = metal0_allocator.alloc(u8, @intCast(n)) catch break :blk \"\"; std.crypto.random.bytes(buf); break :blk buf; }"); } else try self.emit("\"\"");
}
