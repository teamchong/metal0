/// Python posix module - POSIX system calls (low-level os operations)
const std = @import("std");
const h = @import("mod_helper.zig");

const statDefault = ".{ .st_size = 0, .st_mode = 0 }";
const genStat = h.wrap("blk: { const path = ", "; const stat = std.fs.cwd().statFile(path) catch break :blk " ++ statDefault ++ "; break :blk .{ .st_size = @intCast(stat.size), .st_mode = @intCast(@intFromEnum(stat.kind)) }; }", statDefault);

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getcwd", h.c("blk: { var buf: [4096]u8 = undefined; break :blk std.fs.cwd().realpath(\".\", &buf) catch \".\"; }") },
    .{ "chdir", h.wrap("blk: { const path = ", "; std.posix.chdir(path) catch {}; break :blk {}; }", "{}") },
    .{ "listdir", h.c("metal0_runtime.PyList([]const u8).init()") },
    .{ "mkdir", h.wrap("blk: { const path = ", "; std.fs.cwd().makeDir(path) catch {}; break :blk {}; }", "{}") },
    .{ "rmdir", h.wrap("blk: { const path = ", "; std.fs.cwd().deleteDir(path) catch {}; break :blk {}; }", "{}") },
    .{ "unlink", h.wrap("blk: { const path = ", "; std.fs.cwd().deleteFile(path) catch {}; break :blk {}; }", "{}") },
    .{ "rename", h.wrap2("blk: { const src = ", "; const dst = ", "; std.fs.cwd().rename(src, dst) catch {}; break :blk {}; }", "{}") },
    .{ "stat", genStat }, .{ "lstat", genStat },
    .{ "getenv", h.wrap("blk: { const path = ", "; break :blk std.posix.getenv(path); }", "@as(?[]const u8, null)") },
    .{ "kill", h.wrap2("blk: { const pid = ", "; const sig = ", "; _ = std.c.kill(@intCast(pid), @intCast(sig)); break :blk {}; }", "{}") },
    .{ "open", h.wrap("blk: { const path = ", "; const file = std.fs.cwd().openFile(path, .{}) catch break :blk @as(i32, -1); break :blk @intCast(file.handle); }", "@as(i32, -1)") },
    .{ "close", h.wrap("blk: { const fd = ", "; std.posix.close(@intCast(fd)); break :blk {}; }", "{}") },
    .{ "access", h.wrap("blk: { const path = ", "; _ = std.fs.cwd().statFile(path) catch break :blk false; break :blk true; }", "false") },
    .{ "symlink", h.wrap2("blk: { const src = ", "; const dst = ", "; std.fs.cwd().symLink(src, dst, .{}) catch {}; break :blk {}; }", "{}") },
    .{ "readlink", h.wrap("blk: { const path = ", "; var buf: [4096]u8 = undefined; break :blk std.fs.cwd().readLink(path, &buf) catch \"\"; }", "\"\"") },
    .{ "urandom", h.wrap("blk: { const n = ", "; var buf = metal0_allocator.alloc(u8, @intCast(n)) catch break :blk \"\"; std.crypto.random.bytes(buf); break :blk buf; }", "\"\"") },
    .{ "fstat", h.c(statDefault) },
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
