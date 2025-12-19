/// Python posix module - POSIX system calls (low-level os operations)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const ast = @import("analysis.ast");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

const statDefault = ".{ .st_size = 0, .st_mode = 0 }";

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

// Runtime generator functions with unique block IDs

fn genGetcwd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.withInlineBlock("getcwd", &.{}, struct {
        fn emit(c: *NativeCodegen, label: []const u8, _: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.writeFmt("var buf: [4096]u8 = undefined; break :{s} std.fs.cwd().realpath(\".\", &buf) catch \".\"; ", .{label});
            const output = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output);
        }
    }.emit);
}

fn genChdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, "{}");
        return;
    }
    try self.withInlineBlock("chdir", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "const path = ");
            try c.genExpr(a[0]);
            {
                const b = try c.getBuilder();
                try b.writeFmt("; std.posix.chdir(path) catch unreachable; break :{s} {{}}; ", .{label});
                const output = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output);
            }
        }
    }.emit);
}

fn genMkdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, "{}");
        return;
    }
    try self.withInlineBlock("mkdir", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "const path = ");
            try c.genExpr(a[0]);
            {
                const b = try c.getBuilder();
                try b.writeFmt("; std.fs.cwd().makeDir(path) catch unreachable; break :{s} {{}}; ", .{label});
                const output = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output);
            }
        }
    }.emit);
}

fn genRmdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, "{}");
        return;
    }
    try self.withInlineBlock("rmdir", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "const path = ");
            try c.genExpr(a[0]);
            {
                const b = try c.getBuilder();
                try b.writeFmt("; std.fs.cwd().deleteDir(path) catch unreachable; break :{s} {{}}; ", .{label});
                const output = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output);
            }
        }
    }.emit);
}

fn genUnlink(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, "{}");
        return;
    }
    try self.withInlineBlock("unlink", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "const path = ");
            try c.genExpr(a[0]);
            {
                const b = try c.getBuilder();
                try b.writeFmt("; std.fs.cwd().deleteFile(path) catch unreachable; break :{s} {{}}; ", .{label});
                const output = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output);
            }
        }
    }.emit);
}

fn genRename(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try emitConst(self, "{}");
        return;
    }
    try self.withInlineBlock("rename", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "const src = ");
            try c.genExpr(a[0]);
            try emitConst(c, "; const dst = ");
            try c.genExpr(a[1]);
            {
                const b = try c.getBuilder();
                try b.writeFmt("; std.fs.cwd().rename(src, dst) catch unreachable; break :{s} {{}}; ", .{label});
                const output = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output);
            }
        }
    }.emit);
}

fn genStat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, statDefault);
        return;
    }
    try self.withInlineBlock("stat", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "const path = ");
            try c.genExpr(a[0]);
            {
                const b = try c.getBuilder();
                try b.writeFmt("; const stat = std.fs.cwd().statFile(path) catch break :{s} ", .{label});
                try b.write(statDefault);
                try b.writeFmt("; break :{s} .{{ .st_size = @intCast(stat.size), .st_mode = @intCast(@intFromEnum(stat.kind)) }}; ", .{label});
                const output = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output);
            }
        }
    }.emit);
}

fn genGetenv(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, "@as(?[]const u8, null)");
        return;
    }
    try self.withInlineBlock("getenv", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "const path = ");
            try c.genExpr(a[0]);
            {
                const b = try c.getBuilder();
                try b.writeFmt("; _ = path; break :{s} if (comptime @import(\"builtin\").os.tag == .windows) @as(?[]const u8, null) else std.posix.getenv(path); ", .{label});
                const output = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output);
            }
        }
    }.emit);
}

fn genKill(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try emitConst(self, "{}");
        return;
    }
    try self.withInlineBlock("kill", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "const pid = ");
            try c.genExpr(a[0]);
            try emitConst(c, "; const sig = ");
            try c.genExpr(a[1]);
            {
                const b = try c.getBuilder();
                try b.writeFmt("; _ = std.c.kill(@intCast(pid), @intCast(sig)); break :{s} {{}}; ", .{label});
                const output = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output);
            }
        }
    }.emit);
}

fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, "@as(i32, -1)");
        return;
    }
    try self.withInlineBlock("open", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "const path = ");
            try c.genExpr(a[0]);
            {
                const b = try c.getBuilder();
                try b.writeFmt("; const file = std.fs.cwd().openFile(path, .{{}}) catch break :{s} @as(i32, -1); break :{s} if (comptime @import(\"builtin\").os.tag == .windows) @as(i32, @truncate(@as(i64, @intFromPtr(file.handle)))) else @intCast(file.handle); ", .{ label, label });
                const output = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output);
            }
        }
    }.emit);
}

fn genClose(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, "{}");
        return;
    }
    try self.withInlineBlock("close", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "const fd = ");
            try c.genExpr(a[0]);
            {
                const b = try c.getBuilder();
                try b.writeFmt("; std.posix.close(@intCast(fd)); break :{s} {{}}; ", .{label});
                const output = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output);
            }
        }
    }.emit);
}

fn genAccess(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, "false");
        return;
    }
    try self.withInlineBlock("access", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "const path = ");
            try c.genExpr(a[0]);
            {
                const b = try c.getBuilder();
                try b.writeFmt("; _ = std.fs.cwd().statFile(path) catch break :{s} false; break :{s} true; ", .{ label, label });
                const output = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output);
            }
        }
    }.emit);
}

fn genSymlink(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try emitConst(self, "{}");
        return;
    }
    try self.withInlineBlock("symlink", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "const src = ");
            try c.genExpr(a[0]);
            try emitConst(c, "; const dst = ");
            try c.genExpr(a[1]);
            {
                const b = try c.getBuilder();
                try b.writeFmt("; std.fs.cwd().symLink(src, dst, .{{}}) catch unreachable; break :{s} {{}}; ", .{label});
                const output = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output);
            }
        }
    }.emit);
}

fn genReadlink(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, "\"\"");
        return;
    }
    try self.withInlineBlock("readlink", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "const path = ");
            try c.genExpr(a[0]);
            {
                const b = try c.getBuilder();
                try b.writeFmt("; var buf: [4096]u8 = undefined; break :{s} std.fs.cwd().readLink(path, &buf) catch \"\"; ", .{label});
                const output = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output);
            }
        }
    }.emit);
}

fn genUrandom(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, "\"\"");
        return;
    }
    try self.withInlineBlock("urandom", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "const n = ");
            try c.genExpr(a[0]);
            {
                const b = try c.getBuilder();
                try b.writeFmt("; var buf = __global_allocator.alloc(u8, @intCast(n)) catch break :{s} \"\"; std.crypto.random.bytes(buf); break :{s} buf; ", .{ label, label });
                const output = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output);
            }
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
