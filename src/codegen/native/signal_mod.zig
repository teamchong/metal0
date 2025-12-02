/// Python signal module - Set handlers for asynchronous events
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "signal", genSIG_DFL }, .{ "getsignal", genSIG_DFL }, .{ "strsignal", genUnknownSig },
    .{ "valid_signals", genValidSignals }, .{ "raise_signal", genRaiseSignal }, .{ "alarm", genZero },
    .{ "pause", genUnit }, .{ "setitimer", genItimer }, .{ "getitimer", genItimer },
    .{ "set_wakeup_fd", genNeg1 }, .{ "sigwait", genZero }, .{ "sigwaitinfo", genSiginfo },
    .{ "sigtimedwait", genSiginfo2 }, .{ "pthread_sigmask", genEmptySigset }, .{ "pthread_kill", genUnit },
    .{ "sigpending", genEmptySigset }, .{ "siginterrupt", genUnit },
    .{ "SIGHUP", genSig1 }, .{ "SIGINT", genSig2 }, .{ "SIGQUIT", genSig3 }, .{ "SIGILL", genSig4 },
    .{ "SIGTRAP", genSig5 }, .{ "SIGABRT", genSig6 }, .{ "SIGBUS", genSig7 }, .{ "SIGFPE", genSig8 },
    .{ "SIGKILL", genSig9 }, .{ "SIGUSR1", genSig10 }, .{ "SIGSEGV", genSig11 }, .{ "SIGUSR2", genSig12 },
    .{ "SIGPIPE", genSig13 }, .{ "SIGALRM", genSig14 }, .{ "SIGTERM", genSig15 },
    .{ "SIGCHLD", genSig17 }, .{ "SIGCONT", genSig18 }, .{ "SIGSTOP", genSig19 }, .{ "SIGTSTP", genSig20 },
    .{ "SIGTTIN", genSig21 }, .{ "SIGTTOU", genSig22 }, .{ "SIGURG", genSig23 }, .{ "SIGXCPU", genSig24 },
    .{ "SIGXFSZ", genSig25 }, .{ "SIGVTALRM", genSig26 }, .{ "SIGPROF", genSig27 }, .{ "SIGWINCH", genSig28 },
    .{ "SIGIO", genSig29 }, .{ "SIGSYS", genSig31 },
    .{ "SIG_DFL", genSIG_DFL }, .{ "SIG_IGN", genSIG_IGN },
    .{ "SIG_BLOCK", genSigBlock }, .{ "SIG_UNBLOCK", genSig1 }, .{ "SIG_SETMASK", genSig2 },
    .{ "ITIMER_REAL", genSigBlock }, .{ "ITIMER_VIRTUAL", genSig1 }, .{ "ITIMER_PROF", genSig2 },
    .{ "NSIG", genSig65 },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genZero(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0"); }
fn genNeg1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "-1"); }
fn genUnknownSig(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"Unknown signal\""); }
fn genEmptySigset(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]i32{}"); }
fn genItimer(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ 0.0, 0.0 }"); }
fn genValidSignals(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]i32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 }"); }

// Signal constants
fn genSigBlock(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
fn genSig1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 1)"); }
fn genSig2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 2)"); }
fn genSig3(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 3)"); }
fn genSig4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 4)"); }
fn genSig5(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 5)"); }
fn genSig6(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 6)"); }
fn genSig7(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 7)"); }
fn genSig8(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 8)"); }
fn genSig9(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 9)"); }
fn genSig10(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 10)"); }
fn genSig11(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 11)"); }
fn genSig12(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 12)"); }
fn genSig13(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 13)"); }
fn genSig14(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 14)"); }
fn genSig15(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 15)"); }
fn genSig17(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 17)"); }
fn genSig18(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 18)"); }
fn genSig19(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 19)"); }
fn genSig20(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 20)"); }
fn genSig21(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 21)"); }
fn genSig22(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 22)"); }
fn genSig23(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 23)"); }
fn genSig24(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 24)"); }
fn genSig25(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 25)"); }
fn genSig26(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 26)"); }
fn genSig27(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 27)"); }
fn genSig28(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 28)"); }
fn genSig29(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 29)"); }
fn genSig31(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 31)"); }
fn genSig65(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 65)"); }

fn genSIG_DFL(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?*const fn(i32) callconv(.C) void, null)"); }
fn genSIG_IGN(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?*const fn(i32) callconv(.C) void, @ptrFromInt(1))"); }

// Complex types
fn genSiginfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { si_signo: i32 = 0, si_code: i32 = 0, si_errno: i32 = 0, si_pid: i32 = 0, si_uid: u32 = 0, si_status: i32 = 0 }{}");
}

fn genSiginfo2(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { si_signo: i32 = 0, si_code: i32 = 0 }{}");
}

fn genRaiseSignal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const sig = @as(u6, @intCast(");
        try self.genExpr(args[0]);
        try self.emit(")); _ = std.posix.raise(sig); break :blk {}; }");
    } else try self.emit("{}");
}
