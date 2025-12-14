/// Python posix module - POSIX system calls (low-level os operations)
const std = @import("std");
const h = @import("mod_helper.zig");

const statDefault = ".{ .st_size = 0, .st_mode = 0 }";
const genStat = h.wrap("stat_blk: { const path = ", "; const stat = std.fs.cwd().statFile(path) catch break :stat_blk " ++ statDefault ++ "; break :stat_blk .{ .st_size = @intCast(stat.size), .st_mode = @intCast(@intFromEnum(stat.kind)) }; }", statDefault);

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getcwd", h.c("getcwd_blk: { var buf: [4096]u8 = undefined; break :getcwd_blk std.fs.cwd().realpath(\".\", &buf) catch \".\"; }") },
    .{ "chdir", h.wrap("chdir_blk: { const path = ", "; std.posix.chdir(path) catch {}; break :chdir_blk {}; }", "{}") },
    .{ "listdir", h.c("runtime.NativeList.init()") },
    .{ "mkdir", h.wrap("mkdir_blk: { const path = ", "; std.fs.cwd().makeDir(path) catch {}; break :mkdir_blk {}; }", "{}") },
    .{ "rmdir", h.wrap("rmdir_blk: { const path = ", "; std.fs.cwd().deleteDir(path) catch {}; break :rmdir_blk {}; }", "{}") },
    .{ "unlink", h.wrap("unlink_blk: { const path = ", "; std.fs.cwd().deleteFile(path) catch {}; break :unlink_blk {}; }", "{}") },
    .{ "rename", h.wrap2("rename_blk: { const src = ", "; const dst = ", "; std.fs.cwd().rename(src, dst) catch {}; break :rename_blk {}; }", "{}") },
    .{ "stat", genStat }, .{ "lstat", genStat },
    .{ "getenv", h.wrap("getenv_blk: { const path = ", "; _ = path; break :getenv_blk if (comptime @import(\"builtin\").os.tag == .windows) @as(?[]const u8, null) else std.posix.getenv(path); }", "@as(?[]const u8, null)") },
    .{ "kill", h.wrap2("kill_blk: { const pid = ", "; const sig = ", "; _ = std.c.kill(@intCast(pid), @intCast(sig)); break :kill_blk {}; }", "{}") },
    .{ "open", h.wrap("open_blk: { const path = ", "; const file = std.fs.cwd().openFile(path, .{}) catch break :open_blk @as(i32, -1); break :open_blk if (comptime @import(\"builtin\").os.tag == .windows) @as(i32, @truncate(@as(i64, @intFromPtr(file.handle)))) else @intCast(file.handle); }", "@as(i32, -1)") },
    .{ "close", h.wrap("close_blk: { const fd = ", "; std.posix.close(@intCast(fd)); break :close_blk {}; }", "{}") },
    .{ "access", h.wrap("access_blk: { const path = ", "; _ = std.fs.cwd().statFile(path) catch break :access_blk false; break :access_blk true; }", "false") },
    .{ "symlink", h.wrap2("symlink_blk: { const src = ", "; const dst = ", "; std.fs.cwd().symLink(src, dst, .{}) catch {}; break :symlink_blk {}; }", "{}") },
    .{ "readlink", h.wrap("readlink_blk: { const path = ", "; var buf: [4096]u8 = undefined; break :readlink_blk std.fs.cwd().readLink(path, &buf) catch \"\"; }", "\"\"") },
    .{ "urandom", h.wrap("urandom_blk: { const n = ", "; var buf = __global_allocator.alloc(u8, @intCast(n)) catch break :urandom_blk \"\"; std.crypto.random.bytes(buf); break :urandom_blk buf; }", "\"\"") },
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
