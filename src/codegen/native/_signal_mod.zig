/// Python _signal module - C accelerator for signal (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "signal", genSignal },
    .{ "getsignal", genGetsignal },
    .{ "raise_signal", genRaiseSignal },
    .{ "alarm", genAlarm },
    .{ "pause", genPause },
    .{ "getitimer", genGetitimer },
    .{ "setitimer", genSetitimer },
    .{ "siginterrupt", genSiginterrupt },
    .{ "set_wakeup_fd", genSetWakeupFd },
    .{ "sigwait", genSigwait },
    .{ "pthread_kill", genPthreadKill },
    .{ "pthread_sigmask", genPthreadSigmask },
    .{ "sigpending", genSigpending },
    .{ "valid_signals", genValidSignals },
    .{ "SIGHUP", genSighup },
    .{ "SIGINT", genSigint },
    .{ "SIGQUIT", genSigquit },
    .{ "SIGILL", genSigill },
    .{ "SIGTRAP", genSigtrap },
    .{ "SIGABRT", genSigabrt },
    .{ "SIGFPE", genSigfpe },
    .{ "SIGKILL", genSigkill },
    .{ "SIGBUS", genSigbus },
    .{ "SIGSEGV", genSigsegv },
    .{ "SIGSYS", genSigsys },
    .{ "SIGPIPE", genSigpipe },
    .{ "SIGALRM", genSigalrm },
    .{ "SIGTERM", genSigterm },
    .{ "SIGURG", genSigurg },
    .{ "SIGSTOP", genSigstop },
    .{ "SIGTSTP", genSigtstp },
    .{ "SIGCONT", genSigcont },
    .{ "SIGCHLD", genSigchld },
    .{ "SIGTTIN", genSigttin },
    .{ "SIGTTOU", genSigttou },
    .{ "SIGIO", genSigio },
    .{ "SIGXCPU", genSigxcpu },
    .{ "SIGXFSZ", genSigxfsz },
    .{ "SIGVTALRM", genSigvtalrm },
    .{ "SIGPROF", genSigprof },
    .{ "SIGWINCH", genSigwinch },
    .{ "SIGINFO", genSiginfo },
    .{ "SIGUSR1", genSigusr1 },
    .{ "SIGUSR2", genSigusr2 },
    .{ "SIG_DFL", genSigDfl },
    .{ "SIG_IGN", genSigIgn },
    .{ "ITIMER_REAL", genItimerReal },
    .{ "ITIMER_VIRTUAL", genItimerVirtual },
    .{ "ITIMER_PROF", genItimerProf },
    .{ "SIG_BLOCK", genSigBlock },
    .{ "SIG_UNBLOCK", genSigUnblock },
    .{ "SIG_SETMASK", genSigSetmask },
});

fn genSignal(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.withInlineBlock("sig", args, struct {
            fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try c.emit("const __v = ");
                try c.genExpr(a[0]);
                try c.emitFmt("; _ = __v; break :{s} null", .{label});
            }
        }.emit);
    } else {
        try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
    }
}

fn genGetsignal(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
}

fn genRaiseSignal(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genAlarm(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.withInlineBlock("alm", args, struct {
            fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try c.emit("const __v = ");
                try c.genExpr(a[0]);
                try c.emitFmt("; _ = __v; break :{s} @as(i32, 0)", .{label});
            }
        }.emit);
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0)"), builder_mod.EmitConfig.forExpression());
    }
}

fn genPause(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetitimer(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .interval = 0.0, .value = 0.0 }"), builder_mod.EmitConfig.forExpression());
}

fn genSetitimer(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .interval = 0.0, .value = 0.0 }"), builder_mod.EmitConfig.forExpression());
}

fn genSiginterrupt(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genSetWakeupFd(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, -1)"), builder_mod.EmitConfig.forExpression());
}

fn genSigwait(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0)"), builder_mod.EmitConfig.forExpression());
}

fn genPthreadKill(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genPthreadSigmask(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]i32{}"), builder_mod.EmitConfig.forExpression());
}

fn genSigpending(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]i32{}"), builder_mod.EmitConfig.forExpression());
}

fn genValidSignals(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]i32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31 }"), builder_mod.EmitConfig.forExpression());
}

fn genSighup(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 1)"), builder_mod.EmitConfig.forExpression());
}

fn genSigint(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 2)"), builder_mod.EmitConfig.forExpression());
}

fn genSigquit(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 3)"), builder_mod.EmitConfig.forExpression());
}

fn genSigill(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 4)"), builder_mod.EmitConfig.forExpression());
}

fn genSigtrap(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 5)"), builder_mod.EmitConfig.forExpression());
}

fn genSigabrt(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 6)"), builder_mod.EmitConfig.forExpression());
}

fn genSigfpe(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 8)"), builder_mod.EmitConfig.forExpression());
}

fn genSigkill(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 9)"), builder_mod.EmitConfig.forExpression());
}

fn genSigbus(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 10)"), builder_mod.EmitConfig.forExpression());
}

fn genSigsegv(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 11)"), builder_mod.EmitConfig.forExpression());
}

fn genSigsys(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 12)"), builder_mod.EmitConfig.forExpression());
}

fn genSigpipe(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 13)"), builder_mod.EmitConfig.forExpression());
}

fn genSigalrm(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 14)"), builder_mod.EmitConfig.forExpression());
}

fn genSigterm(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 15)"), builder_mod.EmitConfig.forExpression());
}

fn genSigurg(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 16)"), builder_mod.EmitConfig.forExpression());
}

fn genSigstop(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 17)"), builder_mod.EmitConfig.forExpression());
}

fn genSigtstp(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 18)"), builder_mod.EmitConfig.forExpression());
}

fn genSigcont(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 19)"), builder_mod.EmitConfig.forExpression());
}

fn genSigchld(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 20)"), builder_mod.EmitConfig.forExpression());
}

fn genSigttin(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 21)"), builder_mod.EmitConfig.forExpression());
}

fn genSigttou(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 22)"), builder_mod.EmitConfig.forExpression());
}

fn genSigio(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 23)"), builder_mod.EmitConfig.forExpression());
}

fn genSigxcpu(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 24)"), builder_mod.EmitConfig.forExpression());
}

fn genSigxfsz(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 25)"), builder_mod.EmitConfig.forExpression());
}

fn genSigvtalrm(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 26)"), builder_mod.EmitConfig.forExpression());
}

fn genSigprof(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 27)"), builder_mod.EmitConfig.forExpression());
}

fn genSigwinch(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 28)"), builder_mod.EmitConfig.forExpression());
}

fn genSiginfo(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 29)"), builder_mod.EmitConfig.forExpression());
}

fn genSigusr1(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 30)"), builder_mod.EmitConfig.forExpression());
}

fn genSigusr2(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 31)"), builder_mod.EmitConfig.forExpression());
}

fn genSigDfl(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0)"), builder_mod.EmitConfig.forExpression());
}

fn genSigIgn(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 1)"), builder_mod.EmitConfig.forExpression());
}

fn genItimerReal(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0)"), builder_mod.EmitConfig.forExpression());
}

fn genItimerVirtual(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 1)"), builder_mod.EmitConfig.forExpression());
}

fn genItimerProf(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 2)"), builder_mod.EmitConfig.forExpression());
}

fn genSigBlock(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 1)"), builder_mod.EmitConfig.forExpression());
}

fn genSigUnblock(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 2)"), builder_mod.EmitConfig.forExpression());
}

fn genSigSetmask(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 3)"), builder_mod.EmitConfig.forExpression());
}
