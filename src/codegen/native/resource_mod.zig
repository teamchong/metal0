/// Python resource module - Unix resource usage and limits
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getrusage", genGetrusage },
    .{ "getrlimit", genGetrlimit },
    .{ "setrlimit", genSetrlimit },
    .{ "prlimit", genPrlimit },
    .{ "getpagesize", genGetpagesize },
    .{ "RUSAGE_SELF", genRusageSelf },
    .{ "RUSAGE_CHILDREN", genRusageChildren },
    .{ "RUSAGE_BOTH", genRusageBoth },
    .{ "RUSAGE_THREAD", genRusageThread },
    .{ "RLIMIT_CPU", genRlimitCpu },
    .{ "RLIMIT_FSIZE", genRlimitFsize },
    .{ "RLIMIT_DATA", genRlimitData },
    .{ "RLIMIT_STACK", genRlimitStack },
    .{ "RLIMIT_CORE", genRlimitCore },
    .{ "RLIMIT_RSS", genRlimitRss },
    .{ "RLIMIT_NPROC", genRlimitNproc },
    .{ "RLIMIT_NOFILE", genRlimitNofile },
    .{ "RLIMIT_MEMLOCK", genRlimitMemlock },
    .{ "RLIMIT_AS", genRlimitAs },
    .{ "RLIMIT_LOCKS", genRlimitLocks },
    .{ "RLIMIT_SIGPENDING", genRlimitSigpending },
    .{ "RLIMIT_MSGQUEUE", genRlimitMsgqueue },
    .{ "RLIMIT_NICE", genRlimitNice },
    .{ "RLIMIT_RTPRIO", genRlimitRtprio },
    .{ "RLIMIT_RTTIME", genRlimitRttime },
    .{ "RLIM_INFINITY", genRlimInfinity },
});

fn genGetrusage(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .ru_utime = 0.0, .ru_stime = 0.0, .ru_maxrss = 0, .ru_ixrss = 0, .ru_idrss = 0, .ru_isrss = 0, .ru_minflt = 0, .ru_majflt = 0, .ru_nswap = 0, .ru_inblock = 0, .ru_oublock = 0, .ru_msgsnd = 0, .ru_msgrcv = 0, .ru_nsignals = 0, .ru_nvcsw = 0, .ru_nivcsw = 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genGetrlimit(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ @as(i64, -1), @as(i64, -1) }"), builder_mod.EmitConfig.forExpression());
}

fn genSetrlimit(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genPrlimit(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ @as(i64, -1), @as(i64, -1) }"), builder_mod.EmitConfig.forExpression());
}

fn genGetpagesize(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(4096), builder_mod.EmitConfig.forExpression());
}

fn genRusageSelf(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genRusageChildren(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(-1), builder_mod.EmitConfig.forExpression());
}

fn genRusageBoth(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(-2), builder_mod.EmitConfig.forExpression());
}

fn genRusageThread(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

fn genRlimitCpu(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genRlimitFsize(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

fn genRlimitData(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2), builder_mod.EmitConfig.forExpression());
}

fn genRlimitStack(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(3), builder_mod.EmitConfig.forExpression());
}

fn genRlimitCore(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(4), builder_mod.EmitConfig.forExpression());
}

fn genRlimitRss(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(5), builder_mod.EmitConfig.forExpression());
}

fn genRlimitNproc(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(6), builder_mod.EmitConfig.forExpression());
}

fn genRlimitNofile(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(7), builder_mod.EmitConfig.forExpression());
}

fn genRlimitMemlock(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(8), builder_mod.EmitConfig.forExpression());
}

fn genRlimitAs(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(9), builder_mod.EmitConfig.forExpression());
}

fn genRlimitLocks(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(10), builder_mod.EmitConfig.forExpression());
}

fn genRlimitSigpending(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(11), builder_mod.EmitConfig.forExpression());
}

fn genRlimitMsgqueue(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(12), builder_mod.EmitConfig.forExpression());
}

fn genRlimitNice(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(13), builder_mod.EmitConfig.forExpression());
}

fn genRlimitRtprio(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(14), builder_mod.EmitConfig.forExpression());
}

fn genRlimitRttime(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(15), builder_mod.EmitConfig.forExpression());
}

fn genRlimInfinity(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(-1), builder_mod.EmitConfig.forExpression());
}
