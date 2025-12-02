/// Python _signal module - C accelerator for signal (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "signal", genSignal }, .{ "getsignal", genConst("null") }, .{ "raise_signal", genConst("{}") }, .{ "alarm", genAlarm },
    .{ "pause", genConst("{}") }, .{ "getitimer", genConst(".{ .interval = 0.0, .value = 0.0 }") }, .{ "setitimer", genConst(".{ .interval = 0.0, .value = 0.0 }") },
    .{ "siginterrupt", genConst("{}") }, .{ "set_wakeup_fd", genConst("@as(i32, -1)") }, .{ "sigwait", genConst("@as(i32, 0)") },
    .{ "pthread_kill", genConst("{}") }, .{ "pthread_sigmask", genConst("&[_]i32{}") }, .{ "sigpending", genConst("&[_]i32{}") },
    .{ "valid_signals", genConst("&[_]i32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31 }") },
    .{ "SIGHUP", genConst("@as(i32, 1)") }, .{ "SIGINT", genConst("@as(i32, 2)") }, .{ "SIGQUIT", genConst("@as(i32, 3)") }, .{ "SIGILL", genConst("@as(i32, 4)") },
    .{ "SIGTRAP", genConst("@as(i32, 5)") }, .{ "SIGABRT", genConst("@as(i32, 6)") }, .{ "SIGFPE", genConst("@as(i32, 8)") }, .{ "SIGKILL", genConst("@as(i32, 9)") },
    .{ "SIGBUS", genConst("@as(i32, 10)") }, .{ "SIGSEGV", genConst("@as(i32, 11)") }, .{ "SIGSYS", genConst("@as(i32, 12)") }, .{ "SIGPIPE", genConst("@as(i32, 13)") },
    .{ "SIGALRM", genConst("@as(i32, 14)") }, .{ "SIGTERM", genConst("@as(i32, 15)") }, .{ "SIGURG", genConst("@as(i32, 16)") }, .{ "SIGSTOP", genConst("@as(i32, 17)") },
    .{ "SIGTSTP", genConst("@as(i32, 18)") }, .{ "SIGCONT", genConst("@as(i32, 19)") }, .{ "SIGCHLD", genConst("@as(i32, 20)") }, .{ "SIGTTIN", genConst("@as(i32, 21)") },
    .{ "SIGTTOU", genConst("@as(i32, 22)") }, .{ "SIGIO", genConst("@as(i32, 23)") }, .{ "SIGXCPU", genConst("@as(i32, 24)") }, .{ "SIGXFSZ", genConst("@as(i32, 25)") },
    .{ "SIGVTALRM", genConst("@as(i32, 26)") }, .{ "SIGPROF", genConst("@as(i32, 27)") }, .{ "SIGWINCH", genConst("@as(i32, 28)") }, .{ "SIGINFO", genConst("@as(i32, 29)") },
    .{ "SIGUSR1", genConst("@as(i32, 30)") }, .{ "SIGUSR2", genConst("@as(i32, 31)") },
    .{ "SIG_DFL", genConst("@as(i32, 0)") }, .{ "SIG_IGN", genConst("@as(i32, 1)") },
    .{ "ITIMER_REAL", genConst("@as(i32, 0)") }, .{ "ITIMER_VIRTUAL", genConst("@as(i32, 1)") }, .{ "ITIMER_PROF", genConst("@as(i32, 2)") },
    .{ "SIG_BLOCK", genConst("@as(i32, 1)") }, .{ "SIG_UNBLOCK", genConst("@as(i32, 2)") }, .{ "SIG_SETMASK", genConst("@as(i32, 3)") },
});

fn genSignal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { const signum = "); try self.genExpr(args[0]); try self.emit("; _ = signum; break :blk null; }"); } else try self.emit("null");
}
fn genAlarm(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const seconds = "); try self.genExpr(args[0]); try self.emit("; _ = seconds; break :blk @as(i32, 0); }"); } else try self.emit("@as(i32, 0)");
}
