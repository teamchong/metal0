/// Python syslog module - Unix system logging
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "openlog", h.c("{}") }, .{ "syslog", h.c("{}") }, .{ "closelog", h.c("{}") }, .{ "setlogmask", h.I32(0) },
    .{ "LOG_EMERG", h.I32(0) }, .{ "LOG_ALERT", h.I32(1) }, .{ "LOG_CRIT", h.I32(2) }, .{ "LOG_ERR", h.I32(3) },
    .{ "LOG_WARNING", h.I32(4) }, .{ "LOG_NOTICE", h.I32(5) }, .{ "LOG_INFO", h.I32(6) }, .{ "LOG_DEBUG", h.I32(7) },
    .{ "LOG_KERN", h.I32(0) }, .{ "LOG_USER", h.I32(8) }, .{ "LOG_MAIL", h.I32(16) }, .{ "LOG_DAEMON", h.I32(24) },
    .{ "LOG_AUTH", h.I32(32) }, .{ "LOG_SYSLOG", h.I32(40) }, .{ "LOG_LPR", h.I32(48) }, .{ "LOG_NEWS", h.I32(56) },
    .{ "LOG_UUCP", h.I32(64) }, .{ "LOG_CRON", h.I32(72) },
    .{ "LOG_LOCAL0", h.I32(128) }, .{ "LOG_LOCAL1", h.I32(136) }, .{ "LOG_LOCAL2", h.I32(144) }, .{ "LOG_LOCAL3", h.I32(152) },
    .{ "LOG_LOCAL4", h.I32(160) }, .{ "LOG_LOCAL5", h.I32(168) }, .{ "LOG_LOCAL6", h.I32(176) }, .{ "LOG_LOCAL7", h.I32(184) },
    .{ "LOG_PID", h.I32(1) }, .{ "LOG_CONS", h.I32(2) }, .{ "LOG_ODELAY", h.I32(4) }, .{ "LOG_NDELAY", h.I32(8) },
    .{ "LOG_NOWAIT", h.I32(16) }, .{ "LOG_PERROR", h.I32(32) },
    .{ "LOG_MASK", h.shiftL("(@as(i32, 1) << @intCast(", "))", "@as(i32, 0)") },
    .{ "LOG_UPTO", h.shiftL("((@as(i32, 1) << (@intCast(", ") + 1)) - 1)", "@as(i32, 0)") },
});
