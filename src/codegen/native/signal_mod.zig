/// Python signal module - Set handlers for asynchronous events
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "signal", h.c("@as(?*const fn(i32) callconv(.C) void, null)") },
    .{ "getsignal", h.c("@as(?*const fn(i32) callconv(.C) void, null)") },
    .{ "strsignal", h.c("\"Unknown signal\"") }, .{ "valid_signals", h.c("&[_]i32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 }") },
    .{ "raise_signal", genRaiseSignal }, .{ "alarm", h.I32(0) },
    .{ "pause", h.c("{}") }, .{ "setitimer", h.c(".{ 0.0, 0.0 }") }, .{ "getitimer", h.c(".{ 0.0, 0.0 }") },
    .{ "set_wakeup_fd", h.I32(-1) }, .{ "sigwait", h.I32(0) },
    .{ "sigwaitinfo", h.c("struct { si_signo: i32 = 0, si_code: i32 = 0, si_errno: i32 = 0, si_pid: i32 = 0, si_uid: u32 = 0, si_status: i32 = 0 }{}") },
    .{ "sigtimedwait", h.c("struct { si_signo: i32 = 0, si_code: i32 = 0 }{}") },
    .{ "pthread_sigmask", h.c("&[_]i32{}") }, .{ "pthread_kill", h.c("{}") },
    .{ "sigpending", h.c("&[_]i32{}") }, .{ "siginterrupt", h.c("{}") },
    .{ "SIGHUP", h.I32(1) }, .{ "SIGINT", h.I32(2) }, .{ "SIGQUIT", h.I32(3) }, .{ "SIGILL", h.I32(4) },
    .{ "SIGTRAP", h.I32(5) }, .{ "SIGABRT", h.I32(6) }, .{ "SIGBUS", h.I32(7) }, .{ "SIGFPE", h.I32(8) },
    .{ "SIGKILL", h.I32(9) }, .{ "SIGUSR1", h.I32(10) }, .{ "SIGSEGV", h.I32(11) }, .{ "SIGUSR2", h.I32(12) },
    .{ "SIGPIPE", h.I32(13) }, .{ "SIGALRM", h.I32(14) }, .{ "SIGTERM", h.I32(15) },
    .{ "SIGCHLD", h.I32(17) }, .{ "SIGCONT", h.I32(18) }, .{ "SIGSTOP", h.I32(19) }, .{ "SIGTSTP", h.I32(20) },
    .{ "SIGTTIN", h.I32(21) }, .{ "SIGTTOU", h.I32(22) }, .{ "SIGURG", h.I32(23) }, .{ "SIGXCPU", h.I32(24) },
    .{ "SIGXFSZ", h.I32(25) }, .{ "SIGVTALRM", h.I32(26) }, .{ "SIGPROF", h.I32(27) }, .{ "SIGWINCH", h.I32(28) },
    .{ "SIGIO", h.I32(29) }, .{ "SIGSYS", h.I32(31) }, .{ "NSIG", h.I32(65) },
    .{ "SIG_DFL", h.c("@as(?*const fn(i32) callconv(.C) void, null)") },
    .{ "SIG_IGN", h.c("@as(?*const fn(i32) callconv(.C) void, @ptrFromInt(1))") },
    .{ "SIG_BLOCK", h.I32(0) }, .{ "SIG_UNBLOCK", h.I32(1) }, .{ "SIG_SETMASK", h.I32(2) },
    .{ "ITIMER_REAL", h.I32(0) }, .{ "ITIMER_VIRTUAL", h.I32(1) }, .{ "ITIMER_PROF", h.I32(2) },
});

fn genRaiseSignal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const sig = @as(u6, @intCast("); try self.genExpr(args[0]); try self.emit(")); _ = std.posix.raise(sig); break :blk {}; }"); } else try self.emit("{}");
}
