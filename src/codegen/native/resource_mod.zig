/// Python resource module - Unix resource usage and limits
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genI32(comptime n: comptime_int) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, std.fmt.comptimePrint("@as(i32, {})", .{n})); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "getrusage", genGetrusage }, .{ "getrlimit", genGetrlimit }, .{ "setrlimit", genUnit }, .{ "prlimit", genGetrlimit },
    .{ "getpagesize", genPagesize },
    .{ "RUSAGE_SELF", genI32(0) }, .{ "RUSAGE_CHILDREN", genI32(-1) }, .{ "RUSAGE_BOTH", genI32(-2) }, .{ "RUSAGE_THREAD", genI32(1) },
    .{ "RLIMIT_CPU", genI32(0) }, .{ "RLIMIT_FSIZE", genI32(1) }, .{ "RLIMIT_DATA", genI32(2) }, .{ "RLIMIT_STACK", genI32(3) },
    .{ "RLIMIT_CORE", genI32(4) }, .{ "RLIMIT_RSS", genI32(5) }, .{ "RLIMIT_NPROC", genI32(6) }, .{ "RLIMIT_NOFILE", genI32(7) },
    .{ "RLIMIT_MEMLOCK", genI32(8) }, .{ "RLIMIT_AS", genI32(9) }, .{ "RLIMIT_LOCKS", genI32(10) }, .{ "RLIMIT_SIGPENDING", genI32(11) },
    .{ "RLIMIT_MSGQUEUE", genI32(12) }, .{ "RLIMIT_NICE", genI32(13) }, .{ "RLIMIT_RTPRIO", genI32(14) }, .{ "RLIMIT_RTTIME", genI32(15) },
    .{ "RLIM_INFINITY", genI64_n1 },
});

fn genPagesize(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 4096)"); }
fn genGetrlimit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ @as(i64, -1), @as(i64, -1) }"); }
fn genGetrusage(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .ru_utime = 0.0, .ru_stime = 0.0, .ru_maxrss = 0, .ru_ixrss = 0, .ru_idrss = 0, .ru_isrss = 0, .ru_minflt = 0, .ru_majflt = 0, .ru_nswap = 0, .ru_inblock = 0, .ru_oublock = 0, .ru_msgsnd = 0, .ru_msgrcv = 0, .ru_nsignals = 0, .ru_nvcsw = 0, .ru_nivcsw = 0 }"); }
fn genI64_n1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, -1)"); }
