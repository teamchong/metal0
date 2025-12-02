/// Python signal module - Set handlers for asynchronous events
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}
fn genI32(comptime n: comptime_int) ModuleHandler { return genConst(std.fmt.comptimePrint("@as(i32, {})", .{n})); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "signal", genConst("@as(?*const fn(i32) callconv(.C) void, null)") },
    .{ "getsignal", genConst("@as(?*const fn(i32) callconv(.C) void, null)") },
    .{ "strsignal", genConst("\"Unknown signal\"") }, .{ "valid_signals", genConst("&[_]i32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 }") },
    .{ "raise_signal", genRaiseSignal }, .{ "alarm", genConst("0") },
    .{ "pause", genConst("{}") }, .{ "setitimer", genConst(".{ 0.0, 0.0 }") }, .{ "getitimer", genConst(".{ 0.0, 0.0 }") },
    .{ "set_wakeup_fd", genConst("-1") }, .{ "sigwait", genConst("0") },
    .{ "sigwaitinfo", genConst("struct { si_signo: i32 = 0, si_code: i32 = 0, si_errno: i32 = 0, si_pid: i32 = 0, si_uid: u32 = 0, si_status: i32 = 0 }{}") },
    .{ "sigtimedwait", genConst("struct { si_signo: i32 = 0, si_code: i32 = 0 }{}") },
    .{ "pthread_sigmask", genConst("&[_]i32{}") }, .{ "pthread_kill", genConst("{}") },
    .{ "sigpending", genConst("&[_]i32{}") }, .{ "siginterrupt", genConst("{}") },
    .{ "SIGHUP", genI32(1) }, .{ "SIGINT", genI32(2) }, .{ "SIGQUIT", genI32(3) }, .{ "SIGILL", genI32(4) },
    .{ "SIGTRAP", genI32(5) }, .{ "SIGABRT", genI32(6) }, .{ "SIGBUS", genI32(7) }, .{ "SIGFPE", genI32(8) },
    .{ "SIGKILL", genI32(9) }, .{ "SIGUSR1", genI32(10) }, .{ "SIGSEGV", genI32(11) }, .{ "SIGUSR2", genI32(12) },
    .{ "SIGPIPE", genI32(13) }, .{ "SIGALRM", genI32(14) }, .{ "SIGTERM", genI32(15) },
    .{ "SIGCHLD", genI32(17) }, .{ "SIGCONT", genI32(18) }, .{ "SIGSTOP", genI32(19) }, .{ "SIGTSTP", genI32(20) },
    .{ "SIGTTIN", genI32(21) }, .{ "SIGTTOU", genI32(22) }, .{ "SIGURG", genI32(23) }, .{ "SIGXCPU", genI32(24) },
    .{ "SIGXFSZ", genI32(25) }, .{ "SIGVTALRM", genI32(26) }, .{ "SIGPROF", genI32(27) }, .{ "SIGWINCH", genI32(28) },
    .{ "SIGIO", genI32(29) }, .{ "SIGSYS", genI32(31) }, .{ "NSIG", genI32(65) },
    .{ "SIG_DFL", genConst("@as(?*const fn(i32) callconv(.C) void, null)") },
    .{ "SIG_IGN", genConst("@as(?*const fn(i32) callconv(.C) void, @ptrFromInt(1))") },
    .{ "SIG_BLOCK", genI32(0) }, .{ "SIG_UNBLOCK", genI32(1) }, .{ "SIG_SETMASK", genI32(2) },
    .{ "ITIMER_REAL", genI32(0) }, .{ "ITIMER_VIRTUAL", genI32(1) }, .{ "ITIMER_PROF", genI32(2) },
});

fn genRaiseSignal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const sig = @as(u6, @intCast("); try self.genExpr(args[0]); try self.emit(")); _ = std.posix.raise(sig); break :blk {}; }"); } else try self.emit("{}");
}
