/// Python signal module - Set handlers for asynchronous events
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate signal.signal(signalnum, handler)
pub fn genSignal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("SIG_DFL");
}

/// Generate signal.getsignal(signalnum)
pub fn genGetsignal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("SIG_DFL");
}

/// Generate signal.strsignal(signalnum)
pub fn genStrsignal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"Unknown signal\"");
}

/// Generate signal.valid_signals()
pub fn genValidSignals(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]i32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 }");
}

/// Generate signal.raise_signal(signalnum)
pub fn genRaiseSignal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: {\n");
        self.indent();
        try self.emitIndent();
        try self.emit("const sig = @as(u6, @intCast(");
        try self.genExpr(args[0]);
        try self.emit("));\n");
        try self.emitIndent();
        try self.emit("_ = std.posix.raise(sig);\n");
        try self.emitIndent();
        try self.emit("break :blk {};\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}");
    } else {
        try self.emit("{}");
    }
}

/// Generate signal.alarm(time)
pub fn genAlarm(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate signal.pause()
pub fn genPause(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate signal.setitimer(which, seconds, interval=0.0)
pub fn genSetitimer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ 0.0, 0.0 }");
}

/// Generate signal.getitimer(which)
pub fn genGetitimer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ 0.0, 0.0 }");
}

/// Generate signal.set_wakeup_fd(fd, *, warn_on_full_buffer=True)
pub fn genSetWakeupFd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("-1");
}

/// Generate signal.sigwait(sigset)
pub fn genSigwait(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate signal.sigwaitinfo(sigset)
pub fn genSigwaitinfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("si_signo: i32 = 0,\n");
    try self.emitIndent();
    try self.emit("si_code: i32 = 0,\n");
    try self.emitIndent();
    try self.emit("si_errno: i32 = 0,\n");
    try self.emitIndent();
    try self.emit("si_pid: i32 = 0,\n");
    try self.emitIndent();
    try self.emit("si_uid: u32 = 0,\n");
    try self.emitIndent();
    try self.emit("si_status: i32 = 0,\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate signal.sigtimedwait(sigset, timeout)
pub fn genSigtimedwait(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("si_signo: i32 = 0,\n");
    try self.emitIndent();
    try self.emit("si_code: i32 = 0,\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate signal.pthread_sigmask(how, mask)
pub fn genPthreadSigmask(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]i32{}");
}

/// Generate signal.pthread_kill(thread_id, signalnum)
pub fn genPthreadKill(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate signal.sigpending()
pub fn genSigpending(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]i32{}");
}

/// Generate signal.siginterrupt(signalnum, flag)
pub fn genSiginterrupt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

// ============================================================================
// Signal constants
// ============================================================================

pub fn genSIGHUP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genSIGINT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

pub fn genSIGQUIT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 3)");
}

pub fn genSIGILL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 4)");
}

pub fn genSIGTRAP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 5)");
}

pub fn genSIGABRT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 6)");
}

pub fn genSIGBUS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 7)");
}

pub fn genSIGFPE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 8)");
}

pub fn genSIGKILL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 9)");
}

pub fn genSIGUSR1(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 10)");
}

pub fn genSIGSEGV(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 11)");
}

pub fn genSIGUSR2(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 12)");
}

pub fn genSIGPIPE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 13)");
}

pub fn genSIGALRM(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 14)");
}

pub fn genSIGTERM(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 15)");
}

pub fn genSIGCHLD(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 17)");
}

pub fn genSIGCONT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 18)");
}

pub fn genSIGSTOP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 19)");
}

pub fn genSIGTSTP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 20)");
}

pub fn genSIGTTIN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 21)");
}

pub fn genSIGTTOU(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 22)");
}

pub fn genSIGURG(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 23)");
}

pub fn genSIGXCPU(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 24)");
}

pub fn genSIGXFSZ(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 25)");
}

pub fn genSIGVTALRM(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 26)");
}

pub fn genSIGPROF(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 27)");
}

pub fn genSIGWINCH(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 28)");
}

pub fn genSIGIO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 29)");
}

pub fn genSIGSYS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 31)");
}

/// Generate signal.SIG_DFL
pub fn genSIG_DFL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*const fn(i32) callconv(.C) void, null)");
}

/// Generate signal.SIG_IGN
pub fn genSIG_IGN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*const fn(i32) callconv(.C) void, @ptrFromInt(1))");
}

/// Generate signal.SIG_BLOCK
pub fn genSIG_BLOCK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate signal.SIG_UNBLOCK
pub fn genSIG_UNBLOCK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

/// Generate signal.SIG_SETMASK
pub fn genSIG_SETMASK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

/// Generate signal.ITIMER_REAL
pub fn genITIMER_REAL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate signal.ITIMER_VIRTUAL
pub fn genITIMER_VIRTUAL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

/// Generate signal.ITIMER_PROF
pub fn genITIMER_PROF(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

/// Generate signal.NSIG
pub fn genNSIG(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 65)");
}

/// Generate signal.Signals enum
pub fn genSignals(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("pub const SIGHUP = 1;\n");
    try self.emitIndent();
    try self.emit("pub const SIGINT = 2;\n");
    try self.emitIndent();
    try self.emit("pub const SIGQUIT = 3;\n");
    try self.emitIndent();
    try self.emit("pub const SIGILL = 4;\n");
    try self.emitIndent();
    try self.emit("pub const SIGTRAP = 5;\n");
    try self.emitIndent();
    try self.emit("pub const SIGABRT = 6;\n");
    try self.emitIndent();
    try self.emit("pub const SIGBUS = 7;\n");
    try self.emitIndent();
    try self.emit("pub const SIGFPE = 8;\n");
    try self.emitIndent();
    try self.emit("pub const SIGKILL = 9;\n");
    try self.emitIndent();
    try self.emit("pub const SIGUSR1 = 10;\n");
    try self.emitIndent();
    try self.emit("pub const SIGSEGV = 11;\n");
    try self.emitIndent();
    try self.emit("pub const SIGUSR2 = 12;\n");
    try self.emitIndent();
    try self.emit("pub const SIGPIPE = 13;\n");
    try self.emitIndent();
    try self.emit("pub const SIGALRM = 14;\n");
    try self.emitIndent();
    try self.emit("pub const SIGTERM = 15;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate signal.Handlers enum
pub fn genHandlers(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("pub const SIG_DFL = 0;\n");
    try self.emitIndent();
    try self.emit("pub const SIG_IGN = 1;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}
