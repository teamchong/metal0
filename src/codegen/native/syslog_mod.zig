/// Python syslog module - Unix system logging
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "openlog", genConst("{}") }, .{ "syslog", genConst("{}") }, .{ "closelog", genConst("{}") }, .{ "setlogmask", genConst("@as(i32, 0)") },
    .{ "LOG_EMERG", genConst("@as(i32, 0)") }, .{ "LOG_ALERT", genConst("@as(i32, 1)") }, .{ "LOG_CRIT", genConst("@as(i32, 2)") }, .{ "LOG_ERR", genConst("@as(i32, 3)") },
    .{ "LOG_WARNING", genConst("@as(i32, 4)") }, .{ "LOG_NOTICE", genConst("@as(i32, 5)") }, .{ "LOG_INFO", genConst("@as(i32, 6)") }, .{ "LOG_DEBUG", genConst("@as(i32, 7)") },
    .{ "LOG_KERN", genConst("@as(i32, 0)") }, .{ "LOG_USER", genConst("@as(i32, 8)") }, .{ "LOG_MAIL", genConst("@as(i32, 16)") }, .{ "LOG_DAEMON", genConst("@as(i32, 24)") },
    .{ "LOG_AUTH", genConst("@as(i32, 32)") }, .{ "LOG_SYSLOG", genConst("@as(i32, 40)") }, .{ "LOG_LPR", genConst("@as(i32, 48)") }, .{ "LOG_NEWS", genConst("@as(i32, 56)") },
    .{ "LOG_UUCP", genConst("@as(i32, 64)") }, .{ "LOG_CRON", genConst("@as(i32, 72)") },
    .{ "LOG_LOCAL0", genConst("@as(i32, 128)") }, .{ "LOG_LOCAL1", genConst("@as(i32, 136)") }, .{ "LOG_LOCAL2", genConst("@as(i32, 144)") }, .{ "LOG_LOCAL3", genConst("@as(i32, 152)") },
    .{ "LOG_LOCAL4", genConst("@as(i32, 160)") }, .{ "LOG_LOCAL5", genConst("@as(i32, 168)") }, .{ "LOG_LOCAL6", genConst("@as(i32, 176)") }, .{ "LOG_LOCAL7", genConst("@as(i32, 184)") },
    .{ "LOG_PID", genConst("@as(i32, 1)") }, .{ "LOG_CONS", genConst("@as(i32, 2)") }, .{ "LOG_ODELAY", genConst("@as(i32, 4)") }, .{ "LOG_NDELAY", genConst("@as(i32, 8)") },
    .{ "LOG_NOWAIT", genConst("@as(i32, 16)") }, .{ "LOG_PERROR", genConst("@as(i32, 32)") },
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
