/// Python _signal module - C accelerator for signal (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }
fn genEmptySigset(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]i32{}"); }
fn genItimer(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .interval = 0.0, .value = 0.0 }"); }
fn genValidSignals(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]i32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31 }"); }
fn genI32(comptime n: comptime_int) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, std.fmt.comptimePrint("@as(i32, {})", .{n})); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "signal", genSignal }, .{ "getsignal", genNull }, .{ "raise_signal", genUnit }, .{ "alarm", genAlarm },
    .{ "pause", genUnit }, .{ "getitimer", genItimer }, .{ "setitimer", genItimer },
    .{ "siginterrupt", genUnit }, .{ "set_wakeup_fd", genI32(-1) }, .{ "sigwait", genI32(0) },
    .{ "pthread_kill", genUnit }, .{ "pthread_sigmask", genEmptySigset }, .{ "sigpending", genEmptySigset },
    .{ "valid_signals", genValidSignals },
    .{ "SIGHUP", genI32(1) }, .{ "SIGINT", genI32(2) }, .{ "SIGQUIT", genI32(3) }, .{ "SIGILL", genI32(4) },
    .{ "SIGTRAP", genI32(5) }, .{ "SIGABRT", genI32(6) }, .{ "SIGFPE", genI32(8) }, .{ "SIGKILL", genI32(9) },
    .{ "SIGBUS", genI32(10) }, .{ "SIGSEGV", genI32(11) }, .{ "SIGSYS", genI32(12) }, .{ "SIGPIPE", genI32(13) },
    .{ "SIGALRM", genI32(14) }, .{ "SIGTERM", genI32(15) }, .{ "SIGURG", genI32(16) }, .{ "SIGSTOP", genI32(17) },
    .{ "SIGTSTP", genI32(18) }, .{ "SIGCONT", genI32(19) }, .{ "SIGCHLD", genI32(20) }, .{ "SIGTTIN", genI32(21) },
    .{ "SIGTTOU", genI32(22) }, .{ "SIGIO", genI32(23) }, .{ "SIGXCPU", genI32(24) }, .{ "SIGXFSZ", genI32(25) },
    .{ "SIGVTALRM", genI32(26) }, .{ "SIGPROF", genI32(27) }, .{ "SIGWINCH", genI32(28) }, .{ "SIGINFO", genI32(29) },
    .{ "SIGUSR1", genI32(30) }, .{ "SIGUSR2", genI32(31) },
    .{ "SIG_DFL", genI32(0) }, .{ "SIG_IGN", genI32(1) },
    .{ "ITIMER_REAL", genI32(0) }, .{ "ITIMER_VIRTUAL", genI32(1) }, .{ "ITIMER_PROF", genI32(2) },
    .{ "SIG_BLOCK", genI32(1) }, .{ "SIG_UNBLOCK", genI32(2) }, .{ "SIG_SETMASK", genI32(3) },
});

fn genSignal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { const signum = "); try self.genExpr(args[0]); try self.emit("; _ = signum; break :blk null; }"); } else try self.emit("null");
}
fn genAlarm(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const seconds = "); try self.genExpr(args[0]); try self.emit("; _ = seconds; break :blk @as(i32, 0); }"); } else try self.emit("@as(i32, 0)");
}
