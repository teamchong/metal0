/// Python resource module - Unix resource usage and limits
/// MIGRATED TO ZIGBUILDER
/// DRY: Uses h.c(), h.I64() factories for constants
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    // Functions returning structs/tuples/void
    .{ "getrusage", h.c(".{ .ru_utime = 0.0, .ru_stime = 0.0, .ru_maxrss = 0, .ru_ixrss = 0, .ru_idrss = 0, .ru_isrss = 0, .ru_minflt = 0, .ru_majflt = 0, .ru_nswap = 0, .ru_inblock = 0, .ru_oublock = 0, .ru_msgsnd = 0, .ru_msgrcv = 0, .ru_nsignals = 0, .ru_nvcsw = 0, .ru_nivcsw = 0 }") },
    .{ "getrlimit", h.c(".{ @as(i64, -1), @as(i64, -1) }") },
    .{ "setrlimit", h.c("{}") },
    .{ "prlimit", h.c(".{ @as(i64, -1), @as(i64, -1) }") },
    .{ "getpagesize", h.I64(4096) },
    // RUSAGE_* who constants
    .{ "RUSAGE_SELF", h.I64(0) },
    .{ "RUSAGE_CHILDREN", h.I64(-1) },
    .{ "RUSAGE_BOTH", h.I64(-2) },
    .{ "RUSAGE_THREAD", h.I64(1) },
    // RLIMIT_* resource constants
    .{ "RLIMIT_CPU", h.I64(0) },
    .{ "RLIMIT_FSIZE", h.I64(1) },
    .{ "RLIMIT_DATA", h.I64(2) },
    .{ "RLIMIT_STACK", h.I64(3) },
    .{ "RLIMIT_CORE", h.I64(4) },
    .{ "RLIMIT_RSS", h.I64(5) },
    .{ "RLIMIT_NPROC", h.I64(6) },
    .{ "RLIMIT_NOFILE", h.I64(7) },
    .{ "RLIMIT_MEMLOCK", h.I64(8) },
    .{ "RLIMIT_AS", h.I64(9) },
    .{ "RLIMIT_LOCKS", h.I64(10) },
    .{ "RLIMIT_SIGPENDING", h.I64(11) },
    .{ "RLIMIT_MSGQUEUE", h.I64(12) },
    .{ "RLIMIT_NICE", h.I64(13) },
    .{ "RLIMIT_RTPRIO", h.I64(14) },
    .{ "RLIMIT_RTTIME", h.I64(15) },
    // RLIM_INFINITY
    .{ "RLIM_INFINITY", h.I64(-1) },
});
