/// Python resource module - Unix resource usage and limits
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getrusage", h.c(".{ .ru_utime = 0.0, .ru_stime = 0.0, .ru_maxrss = 0, .ru_ixrss = 0, .ru_idrss = 0, .ru_isrss = 0, .ru_minflt = 0, .ru_majflt = 0, .ru_nswap = 0, .ru_inblock = 0, .ru_oublock = 0, .ru_msgsnd = 0, .ru_msgrcv = 0, .ru_nsignals = 0, .ru_nvcsw = 0, .ru_nivcsw = 0 }") },
    .{ "getrlimit", h.c(".{ @as(i64, -1), @as(i64, -1) }") }, .{ "setrlimit", h.c("{}") }, .{ "prlimit", h.c(".{ @as(i64, -1), @as(i64, -1) }") },
    .{ "getpagesize", h.I64(4096) },
    .{ "RUSAGE_SELF", h.I32(0) }, .{ "RUSAGE_CHILDREN", h.I32(-1) }, .{ "RUSAGE_BOTH", h.I32(-2) }, .{ "RUSAGE_THREAD", h.I32(1) },
    .{ "RLIMIT_CPU", h.I32(0) }, .{ "RLIMIT_FSIZE", h.I32(1) }, .{ "RLIMIT_DATA", h.I32(2) }, .{ "RLIMIT_STACK", h.I32(3) },
    .{ "RLIMIT_CORE", h.I32(4) }, .{ "RLIMIT_RSS", h.I32(5) }, .{ "RLIMIT_NPROC", h.I32(6) }, .{ "RLIMIT_NOFILE", h.I32(7) },
    .{ "RLIMIT_MEMLOCK", h.I32(8) }, .{ "RLIMIT_AS", h.I32(9) }, .{ "RLIMIT_LOCKS", h.I32(10) }, .{ "RLIMIT_SIGPENDING", h.I32(11) },
    .{ "RLIMIT_MSGQUEUE", h.I32(12) }, .{ "RLIMIT_NICE", h.I32(13) }, .{ "RLIMIT_RTPRIO", h.I32(14) }, .{ "RLIMIT_RTTIME", h.I32(15) },
    .{ "RLIM_INFINITY", h.I64(-1) },
});
