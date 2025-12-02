/// Python _signal module - C accelerator for signal (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "signal", genSignal }, .{ "getsignal", genNull }, .{ "raise_signal", genUnit }, .{ "alarm", genAlarm },
    .{ "pause", genUnit }, .{ "getitimer", genItimer }, .{ "setitimer", genItimer },
    .{ "siginterrupt", genUnit }, .{ "set_wakeup_fd", genNeg1 }, .{ "sigwait", genI32_0 },
    .{ "pthread_kill", genUnit }, .{ "pthread_sigmask", genEmptySigset }, .{ "sigpending", genEmptySigset },
    .{ "valid_signals", genValidSignals },
    .{ "SIGHUP", genSig1 }, .{ "SIGINT", genSig2 }, .{ "SIGQUIT", genSig3 }, .{ "SIGILL", genSig4 },
    .{ "SIGTRAP", genSig5 }, .{ "SIGABRT", genSig6 }, .{ "SIGFPE", genSig8 }, .{ "SIGKILL", genSig9 },
    .{ "SIGBUS", genSig10 }, .{ "SIGSEGV", genSig11 }, .{ "SIGSYS", genSig12 }, .{ "SIGPIPE", genSig13 },
    .{ "SIGALRM", genSig14 }, .{ "SIGTERM", genSig15 }, .{ "SIGURG", genSig16 }, .{ "SIGSTOP", genSig17 },
    .{ "SIGTSTP", genSig18 }, .{ "SIGCONT", genSig19 }, .{ "SIGCHLD", genSig20 }, .{ "SIGTTIN", genSig21 },
    .{ "SIGTTOU", genSig22 }, .{ "SIGIO", genSig23 }, .{ "SIGXCPU", genSig24 }, .{ "SIGXFSZ", genSig25 },
    .{ "SIGVTALRM", genSig26 }, .{ "SIGPROF", genSig27 }, .{ "SIGWINCH", genSig28 }, .{ "SIGINFO", genSig29 },
    .{ "SIGUSR1", genSig30 }, .{ "SIGUSR2", genSig31 },
    .{ "SIG_DFL", genI32_0 }, .{ "SIG_IGN", genI32_1 },
    .{ "ITIMER_REAL", genI32_0 }, .{ "ITIMER_VIRTUAL", genI32_1 }, .{ "ITIMER_PROF", genI32_2 },
    .{ "SIG_BLOCK", genI32_1 }, .{ "SIG_UNBLOCK", genI32_2 }, .{ "SIG_SETMASK", genI32_3 },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }
fn genNeg1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, -1)"); }
fn genI32_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
fn genI32_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 1)"); }
fn genI32_2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 2)"); }
fn genI32_3(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 3)"); }
fn genEmptySigset(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]i32{}"); }
fn genItimer(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .interval = 0.0, .value = 0.0 }"); }
fn genValidSignals(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]i32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31 }"); }

// Signal constants (1-31)
fn genSig1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 1)"); }
fn genSig2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 2)"); }
fn genSig3(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 3)"); }
fn genSig4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 4)"); }
fn genSig5(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 5)"); }
fn genSig6(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 6)"); }
fn genSig8(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 8)"); }
fn genSig9(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 9)"); }
fn genSig10(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 10)"); }
fn genSig11(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 11)"); }
fn genSig12(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 12)"); }
fn genSig13(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 13)"); }
fn genSig14(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 14)"); }
fn genSig15(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 15)"); }
fn genSig16(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 16)"); }
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
fn genSig30(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 30)"); }
fn genSig31(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 31)"); }

// Functions with args
fn genSignal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) { try self.emit("blk: { const signum = "); try self.genExpr(args[0]); try self.emit("; _ = signum; break :blk null; }"); } else try self.emit("null");
}
fn genAlarm(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const seconds = "); try self.genExpr(args[0]); try self.emit("; _ = seconds; break :blk @as(i32, 0); }"); } else try self.emit("@as(i32, 0)");
}
