/// Python resource module - Unix resource usage and limits
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "getrusage", genConst(".{ .ru_utime = 0.0, .ru_stime = 0.0, .ru_maxrss = 0, .ru_ixrss = 0, .ru_idrss = 0, .ru_isrss = 0, .ru_minflt = 0, .ru_majflt = 0, .ru_nswap = 0, .ru_inblock = 0, .ru_oublock = 0, .ru_msgsnd = 0, .ru_msgrcv = 0, .ru_nsignals = 0, .ru_nvcsw = 0, .ru_nivcsw = 0 }") },
    .{ "getrlimit", genConst(".{ @as(i64, -1), @as(i64, -1) }") }, .{ "setrlimit", genConst("{}") }, .{ "prlimit", genConst(".{ @as(i64, -1), @as(i64, -1) }") },
    .{ "getpagesize", genConst("@as(i64, 4096)") },
    .{ "RUSAGE_SELF", genConst("@as(i32, 0)") }, .{ "RUSAGE_CHILDREN", genConst("@as(i32, -1)") }, .{ "RUSAGE_BOTH", genConst("@as(i32, -2)") }, .{ "RUSAGE_THREAD", genConst("@as(i32, 1)") },
    .{ "RLIMIT_CPU", genConst("@as(i32, 0)") }, .{ "RLIMIT_FSIZE", genConst("@as(i32, 1)") }, .{ "RLIMIT_DATA", genConst("@as(i32, 2)") }, .{ "RLIMIT_STACK", genConst("@as(i32, 3)") },
    .{ "RLIMIT_CORE", genConst("@as(i32, 4)") }, .{ "RLIMIT_RSS", genConst("@as(i32, 5)") }, .{ "RLIMIT_NPROC", genConst("@as(i32, 6)") }, .{ "RLIMIT_NOFILE", genConst("@as(i32, 7)") },
    .{ "RLIMIT_MEMLOCK", genConst("@as(i32, 8)") }, .{ "RLIMIT_AS", genConst("@as(i32, 9)") }, .{ "RLIMIT_LOCKS", genConst("@as(i32, 10)") }, .{ "RLIMIT_SIGPENDING", genConst("@as(i32, 11)") },
    .{ "RLIMIT_MSGQUEUE", genConst("@as(i32, 12)") }, .{ "RLIMIT_NICE", genConst("@as(i32, 13)") }, .{ "RLIMIT_RTPRIO", genConst("@as(i32, 14)") }, .{ "RLIMIT_RTTIME", genConst("@as(i32, 15)") },
    .{ "RLIM_INFINITY", genConst("@as(i64, -1)") },
});
