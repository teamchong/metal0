/// Python syslog module - Unix system logging
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "openlog", genOpenlog },
    .{ "syslog", genSyslog },
    .{ "closelog", genCloselog },
    .{ "setlogmask", genSetlogmask },
    .{ "LOG_EMERG", genLOG_EMERG },
    .{ "LOG_ALERT", genLOG_ALERT },
    .{ "LOG_CRIT", genLOG_CRIT },
    .{ "LOG_ERR", genLOG_ERR },
    .{ "LOG_WARNING", genLOG_WARNING },
    .{ "LOG_NOTICE", genLOG_NOTICE },
    .{ "LOG_INFO", genLOG_INFO },
    .{ "LOG_DEBUG", genLOG_DEBUG },
    .{ "LOG_KERN", genLOG_KERN },
    .{ "LOG_USER", genLOG_USER },
    .{ "LOG_MAIL", genLOG_MAIL },
    .{ "LOG_DAEMON", genLOG_DAEMON },
    .{ "LOG_AUTH", genLOG_AUTH },
    .{ "LOG_SYSLOG", genLOG_SYSLOG },
    .{ "LOG_LPR", genLOG_LPR },
    .{ "LOG_NEWS", genLOG_NEWS },
    .{ "LOG_UUCP", genLOG_UUCP },
    .{ "LOG_CRON", genLOG_CRON },
    .{ "LOG_LOCAL0", genLOG_LOCAL0 },
    .{ "LOG_LOCAL1", genLOG_LOCAL1 },
    .{ "LOG_LOCAL2", genLOG_LOCAL2 },
    .{ "LOG_LOCAL3", genLOG_LOCAL3 },
    .{ "LOG_LOCAL4", genLOG_LOCAL4 },
    .{ "LOG_LOCAL5", genLOG_LOCAL5 },
    .{ "LOG_LOCAL6", genLOG_LOCAL6 },
    .{ "LOG_LOCAL7", genLOG_LOCAL7 },
    .{ "LOG_PID", genLOG_PID },
    .{ "LOG_CONS", genLOG_CONS },
    .{ "LOG_ODELAY", genLOG_ODELAY },
    .{ "LOG_NDELAY", genLOG_NDELAY },
    .{ "LOG_NOWAIT", genLOG_NOWAIT },
    .{ "LOG_PERROR", genLOG_PERROR },
    .{ "LOG_MASK", genLOG_MASK },
    .{ "LOG_UPTO", genLOG_UPTO },
});

/// Generate syslog.openlog(ident, logoption, facility)
pub fn genOpenlog(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate syslog.syslog(priority, message)
pub fn genSyslog(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate syslog.closelog()
pub fn genCloselog(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate syslog.setlogmask(maskpri)
pub fn genSetlogmask(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

// ============================================================================
// Priority levels
// ============================================================================

pub fn genLOG_EMERG(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

pub fn genLOG_ALERT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genLOG_CRIT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

pub fn genLOG_ERR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 3)");
}

pub fn genLOG_WARNING(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 4)");
}

pub fn genLOG_NOTICE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 5)");
}

pub fn genLOG_INFO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 6)");
}

pub fn genLOG_DEBUG(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 7)");
}

// ============================================================================
// Facility codes
// ============================================================================

pub fn genLOG_KERN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

pub fn genLOG_USER(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 8)");
}

pub fn genLOG_MAIL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 16)");
}

pub fn genLOG_DAEMON(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 24)");
}

pub fn genLOG_AUTH(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 32)");
}

pub fn genLOG_SYSLOG(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 40)");
}

pub fn genLOG_LPR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 48)");
}

pub fn genLOG_NEWS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 56)");
}

pub fn genLOG_UUCP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 64)");
}

pub fn genLOG_CRON(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 72)");
}

pub fn genLOG_LOCAL0(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 128)");
}

pub fn genLOG_LOCAL1(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 136)");
}

pub fn genLOG_LOCAL2(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 144)");
}

pub fn genLOG_LOCAL3(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 152)");
}

pub fn genLOG_LOCAL4(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 160)");
}

pub fn genLOG_LOCAL5(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 168)");
}

pub fn genLOG_LOCAL6(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 176)");
}

pub fn genLOG_LOCAL7(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 184)");
}

// ============================================================================
// Option flags
// ============================================================================

pub fn genLOG_PID(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genLOG_CONS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

pub fn genLOG_ODELAY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 4)");
}

pub fn genLOG_NDELAY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 8)");
}

pub fn genLOG_NOWAIT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 16)");
}

pub fn genLOG_PERROR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 32)");
}

/// Generate syslog.LOG_MASK(pri) - calculate mask for priority
pub fn genLOG_MASK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("(@as(i32, 1) << @intCast(");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("@as(i32, 0)");
    }
}

/// Generate syslog.LOG_UPTO(pri) - mask for priority and all higher
pub fn genLOG_UPTO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("((@as(i32, 1) << (@intCast(");
        try self.genExpr(args[0]);
        try self.emit(") + 1)) - 1)");
    } else {
        try self.emit("@as(i32, 0)");
    }
}
