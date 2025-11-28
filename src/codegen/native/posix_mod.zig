/// Python posix module - POSIX system calls (low-level os operations)
/// This module re-exports os functions for POSIX compatibility
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

// Re-export common os functions - posix module is the underlying implementation

pub fn genGetcwd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("blk: { var buf: [4096]u8 = undefined; break :blk std.fs.cwd().realpath(\".\", &buf) catch \".\"; }");
}

pub fn genChdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; std.posix.chdir(path) catch {}; break :blk {}; }");
    } else {
        try self.emit("{}");
    }
}

pub fn genListdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("pyaot_runtime.PyList([]const u8).init()");
}

pub fn genMkdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; std.fs.cwd().makeDir(path) catch {}; break :blk {}; }");
    } else {
        try self.emit("{}");
    }
}

pub fn genRmdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; std.fs.cwd().deleteDir(path) catch {}; break :blk {}; }");
    } else {
        try self.emit("{}");
    }
}

pub fn genUnlink(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; std.fs.cwd().deleteFile(path) catch {}; break :blk {}; }");
    } else {
        try self.emit("{}");
    }
}

pub fn genRename(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("blk: { const src = ");
        try self.genExpr(args[0]);
        try self.emit("; const dst = ");
        try self.genExpr(args[1]);
        try self.emit("; std.fs.cwd().rename(src, dst) catch {}; break :blk {}; }");
    } else {
        try self.emit("{}");
    }
}

pub fn genStat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; const stat = std.fs.cwd().statFile(path) catch break :blk .{ .st_size = 0, .st_mode = 0 }; break :blk .{ .st_size = @intCast(stat.size), .st_mode = @intCast(@intFromEnum(stat.kind)) }; }");
    } else {
        try self.emit(".{ .st_size = 0, .st_mode = 0 }");
    }
}

pub fn genLstat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    return genStat(self, args);
}

pub fn genFstat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .st_size = 0, .st_mode = 0 }");
}

pub fn genGetenv(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const key = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk std.posix.getenv(key); }");
    } else {
        try self.emit("@as(?[]const u8, null)");
    }
}

pub fn genGetpid(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, @intCast(std.c.getpid()))");
}

pub fn genGetppid(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, @intCast(std.c.getppid()))");
}

pub fn genGetuid(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, std.c.getuid())");
}

pub fn genGetgid(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, std.c.getgid())");
}

pub fn genGeteuid(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, std.c.geteuid())");
}

pub fn genGetegid(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, std.c.getegid())");
}

pub fn genKill(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("blk: { const pid = ");
        try self.genExpr(args[0]);
        try self.emit("; const sig = ");
        try self.genExpr(args[1]);
        try self.emit("; _ = std.c.kill(@intCast(pid), @intCast(sig)); break :blk {}; }");
    } else {
        try self.emit("{}");
    }
}

pub fn genFork(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, @intCast(std.c.fork()))");
}

pub fn genWait(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(i32, 0), @as(i32, 0) }");
}

pub fn genWaitpid(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(i32, 0), @as(i32, 0) }");
}

pub fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; const file = std.fs.cwd().openFile(path, .{}) catch break :blk @as(i32, -1); break :blk @intCast(file.handle); }");
    } else {
        try self.emit("@as(i32, -1)");
    }
}

pub fn genClose(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const fd = ");
        try self.genExpr(args[0]);
        try self.emit("; std.posix.close(@intCast(fd)); break :blk {}; }");
    } else {
        try self.emit("{}");
    }
}

pub fn genRead(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

pub fn genWrite(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

pub fn genPipe(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(i32, -1), @as(i32, -1) }");
}

pub fn genDup(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, -1)");
}

pub fn genDup2(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, -1)");
}

pub fn genAccess(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = std.fs.cwd().statFile(path) catch break :blk false; break :blk true; }");
    } else {
        try self.emit("false");
    }
}

pub fn genChmod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

pub fn genChown(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

pub fn genUmask(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0o022)");
}

pub fn genSymlink(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("blk: { const src = ");
        try self.genExpr(args[0]);
        try self.emit("; const dst = ");
        try self.genExpr(args[1]);
        try self.emit("; std.fs.cwd().symLink(src, dst, .{}) catch {}; break :blk {}; }");
    } else {
        try self.emit("{}");
    }
}

pub fn genReadlink(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const path = ");
        try self.genExpr(args[0]);
        try self.emit("; var buf: [4096]u8 = undefined; break :blk std.fs.cwd().readLink(path, &buf) catch \"\"; }");
    } else {
        try self.emit("\"\"");
    }
}

pub fn genUname(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .sysname = \"Darwin\", .nodename = \"localhost\", .release = \"21.0.0\", .version = \"Darwin Kernel\", .machine = \"x86_64\" }");
}

pub fn genUrandom(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const n = ");
        try self.genExpr(args[0]);
        try self.emit("; var buf = pyaot_allocator.alloc(u8, @intCast(n)) catch break :blk \"\"; std.crypto.random.bytes(buf); break :blk buf; }");
    } else {
        try self.emit("\"\"");
    }
}

// ============================================================================
// Posix-specific constants
// ============================================================================

pub fn genO_RDONLY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

pub fn genO_WRONLY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genO_RDWR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

pub fn genO_CREAT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 512)");
}

pub fn genO_EXCL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2048)");
}

pub fn genO_TRUNC(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1024)");
}

pub fn genO_APPEND(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 8)");
}

pub fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.OSError");
}
