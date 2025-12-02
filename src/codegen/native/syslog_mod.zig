/// Python syslog module - Unix system logging
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
    .{ "openlog", genUnit }, .{ "syslog", genUnit }, .{ "closelog", genUnit }, .{ "setlogmask", genI32(0) },
    .{ "LOG_EMERG", genI32(0) }, .{ "LOG_ALERT", genI32(1) }, .{ "LOG_CRIT", genI32(2) }, .{ "LOG_ERR", genI32(3) },
    .{ "LOG_WARNING", genI32(4) }, .{ "LOG_NOTICE", genI32(5) }, .{ "LOG_INFO", genI32(6) }, .{ "LOG_DEBUG", genI32(7) },
    .{ "LOG_KERN", genI32(0) }, .{ "LOG_USER", genI32(8) }, .{ "LOG_MAIL", genI32(16) }, .{ "LOG_DAEMON", genI32(24) },
    .{ "LOG_AUTH", genI32(32) }, .{ "LOG_SYSLOG", genI32(40) }, .{ "LOG_LPR", genI32(48) }, .{ "LOG_NEWS", genI32(56) },
    .{ "LOG_UUCP", genI32(64) }, .{ "LOG_CRON", genI32(72) },
    .{ "LOG_LOCAL0", genI32(128) }, .{ "LOG_LOCAL1", genI32(136) }, .{ "LOG_LOCAL2", genI32(144) }, .{ "LOG_LOCAL3", genI32(152) },
    .{ "LOG_LOCAL4", genI32(160) }, .{ "LOG_LOCAL5", genI32(168) }, .{ "LOG_LOCAL6", genI32(176) }, .{ "LOG_LOCAL7", genI32(184) },
    .{ "LOG_PID", genI32(1) }, .{ "LOG_CONS", genI32(2) }, .{ "LOG_ODELAY", genI32(4) }, .{ "LOG_NDELAY", genI32(8) },
    .{ "LOG_NOWAIT", genI32(16) }, .{ "LOG_PERROR", genI32(32) },
    .{ "LOG_MASK", genLOG_MASK }, .{ "LOG_UPTO", genLOG_UPTO },
});

fn genLOG_MASK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("(@as(i32, 1) << @intCast("); try self.genExpr(args[0]); try self.emit("))"); }
    else try self.emit("@as(i32, 0)");
}
fn genLOG_UPTO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("((@as(i32, 1) << (@intCast("); try self.genExpr(args[0]); try self.emit(") + 1)) - 1)"); }
    else try self.emit("@as(i32, 0)");
}
