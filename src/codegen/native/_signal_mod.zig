/// Python _signal module - C accelerator for signal (internal)
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "signal", genSignal }, .{ "getsignal", h.c("null") }, .{ "raise_signal", h.c("{}") }, .{ "alarm", genAlarm },
    .{ "pause", h.c("{}") }, .{ "getitimer", h.c(".{ .interval = 0.0, .value = 0.0 }") }, .{ "setitimer", h.c(".{ .interval = 0.0, .value = 0.0 }") },
    .{ "siginterrupt", h.c("{}") }, .{ "set_wakeup_fd", h.I32(-1) }, .{ "sigwait", h.I32(0) },
    .{ "pthread_kill", h.c("{}") }, .{ "pthread_sigmask", h.c("&[_]i32{}") }, .{ "sigpending", h.c("&[_]i32{}") },
    .{ "valid_signals", h.c("&[_]i32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31 }") },
    .{ "SIGHUP", h.I32(1) }, .{ "SIGINT", h.I32(2) }, .{ "SIGQUIT", h.I32(3) }, .{ "SIGILL", h.I32(4) },
    .{ "SIGTRAP", h.I32(5) }, .{ "SIGABRT", h.I32(6) }, .{ "SIGFPE", h.I32(8) }, .{ "SIGKILL", h.I32(9) },
    .{ "SIGBUS", h.I32(10) }, .{ "SIGSEGV", h.I32(11) }, .{ "SIGSYS", h.I32(12) }, .{ "SIGPIPE", h.I32(13) },
    .{ "SIGALRM", h.I32(14) }, .{ "SIGTERM", h.I32(15) }, .{ "SIGURG", h.I32(16) }, .{ "SIGSTOP", h.I32(17) },
    .{ "SIGTSTP", h.I32(18) }, .{ "SIGCONT", h.I32(19) }, .{ "SIGCHLD", h.I32(20) }, .{ "SIGTTIN", h.I32(21) },
    .{ "SIGTTOU", h.I32(22) }, .{ "SIGIO", h.I32(23) }, .{ "SIGXCPU", h.I32(24) }, .{ "SIGXFSZ", h.I32(25) },
    .{ "SIGVTALRM", h.I32(26) }, .{ "SIGPROF", h.I32(27) }, .{ "SIGWINCH", h.I32(28) }, .{ "SIGINFO", h.I32(29) },
    .{ "SIGUSR1", h.I32(30) }, .{ "SIGUSR2", h.I32(31) },
    .{ "SIG_DFL", h.I32(0) }, .{ "SIG_IGN", h.I32(1) },
    .{ "ITIMER_REAL", h.I32(0) }, .{ "ITIMER_VIRTUAL", h.I32(1) }, .{ "ITIMER_PROF", h.I32(2) },
    .{ "SIG_BLOCK", h.I32(1) }, .{ "SIG_UNBLOCK", h.I32(2) }, .{ "SIG_SETMASK", h.I32(3) },
});

fn genSignal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { const signum = "); try self.genExpr(args[0]); try self.emit("; _ = signum; break :blk null; }"); } else try self.emit("null");
}
fn genAlarm(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const seconds = "); try self.genExpr(args[0]); try self.emit("; _ = seconds; break :blk @as(i32, 0); }"); } else try self.emit("@as(i32, 0)");
}
