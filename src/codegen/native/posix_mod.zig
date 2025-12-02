/// Python posix module - POSIX system calls (low-level os operations)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}
fn genPathOp(comptime body: []const u8, comptime default: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len > 0) { try self.emit("blk: { const path = "); try self.genExpr(args[0]); try self.emit("; " ++ body ++ " }"); } else try self.emit(default);
    } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "getcwd", genConst("blk: { var buf: [4096]u8 = undefined; break :blk std.fs.cwd().realpath(\".\", &buf) catch \".\"; }") },
    .{ "chdir", genPathOp("std.posix.chdir(path) catch {}; break :blk {};", "{}") },
    .{ "listdir", genConst("metal0_runtime.PyList([]const u8).init()") },
    .{ "mkdir", genPathOp("std.fs.cwd().makeDir(path) catch {}; break :blk {};", "{}") },
    .{ "rmdir", genPathOp("std.fs.cwd().deleteDir(path) catch {}; break :blk {};", "{}") },
    .{ "unlink", genPathOp("std.fs.cwd().deleteFile(path) catch {}; break :blk {};", "{}") },
    .{ "rename", genRename }, .{ "stat", genStat }, .{ "lstat", genStat },
    .{ "getenv", genPathOp("break :blk std.posix.getenv(path);", "@as(?[]const u8, null)") },
    .{ "kill", genKill }, .{ "open", genOpen }, .{ "close", genClose },
    .{ "access", genPathOp("_ = std.fs.cwd().statFile(path) catch break :blk false; break :blk true;", "false") },
    .{ "symlink", genSymlink }, .{ "readlink", genPathOp("var buf: [4096]u8 = undefined; break :blk std.fs.cwd().readLink(path, &buf) catch \"\";", "\"\"") },
    .{ "urandom", genUrandom },
    .{ "fstat", genConst(".{ .st_size = 0, .st_mode = 0 }") },
    .{ "getpid", genConst("@as(i32, @intCast(std.c.getpid()))") },
    .{ "getppid", genConst("@as(i32, @intCast(std.c.getppid()))") },
    .{ "getuid", genConst("@as(u32, std.c.getuid())") },
    .{ "getgid", genConst("@as(u32, std.c.getgid())") },
    .{ "geteuid", genConst("@as(u32, std.c.geteuid())") },
    .{ "getegid", genConst("@as(u32, std.c.getegid())") },
    .{ "fork", genConst("@as(i32, @intCast(std.c.fork()))") },
    .{ "read", genConst("\"\"") }, .{ "write", genConst("@as(i64, 0)") },
    .{ "pipe", genConst(".{ @as(i32, -1), @as(i32, -1) }") },
    .{ "dup", genConst("@as(i32, -1)") }, .{ "dup2", genConst("@as(i32, -1)") },
    .{ "chmod", genConst("{}") }, .{ "chown", genConst("{}") },
    .{ "umask", genConst("@as(i32, 0o022)") },
    .{ "uname", genConst(".{ .sysname = \"Darwin\", .nodename = \"localhost\", .release = \"21.0.0\", .version = \"Darwin Kernel\", .machine = \"x86_64\" }") },
    .{ "error", genConst("error.OSError") },
    .{ "wait", genConst(".{ @as(i32, 0), @as(i32, 0) }") },
    .{ "waitpid", genConst(".{ @as(i32, 0), @as(i32, 0) }") },
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
