/// Python syslog module - Unix system logging
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "openlog", genUnit }, .{ "syslog", genUnit }, .{ "closelog", genUnit }, .{ "setlogmask", genI32_0 },
    .{ "LOG_EMERG", genI32_0 }, .{ "LOG_ALERT", genI32_1 }, .{ "LOG_CRIT", genI32_2 }, .{ "LOG_ERR", genI32_3 },
    .{ "LOG_WARNING", genI32_4 }, .{ "LOG_NOTICE", genI32_5 }, .{ "LOG_INFO", genI32_6 }, .{ "LOG_DEBUG", genI32_7 },
    .{ "LOG_KERN", genI32_0 }, .{ "LOG_USER", genI32_8 }, .{ "LOG_MAIL", genI32_16 }, .{ "LOG_DAEMON", genI32_24 },
    .{ "LOG_AUTH", genI32_32 }, .{ "LOG_SYSLOG", genI32_40 }, .{ "LOG_LPR", genI32_48 }, .{ "LOG_NEWS", genI32_56 },
    .{ "LOG_UUCP", genI32_64 }, .{ "LOG_CRON", genI32_72 },
    .{ "LOG_LOCAL0", genI32_128 }, .{ "LOG_LOCAL1", genI32_136 }, .{ "LOG_LOCAL2", genI32_144 }, .{ "LOG_LOCAL3", genI32_152 },
    .{ "LOG_LOCAL4", genI32_160 }, .{ "LOG_LOCAL5", genI32_168 }, .{ "LOG_LOCAL6", genI32_176 }, .{ "LOG_LOCAL7", genI32_184 },
    .{ "LOG_PID", genI32_1 }, .{ "LOG_CONS", genI32_2 }, .{ "LOG_ODELAY", genI32_4 }, .{ "LOG_NDELAY", genI32_8 },
    .{ "LOG_NOWAIT", genI32_16 }, .{ "LOG_PERROR", genI32_32 },
    .{ "LOG_MASK", genLOG_MASK }, .{ "LOG_UPTO", genLOG_UPTO },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }

// Integer constants
fn genI32_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
fn genI32_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 1)"); }
fn genI32_2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 2)"); }
fn genI32_3(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 3)"); }
fn genI32_4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 4)"); }
fn genI32_5(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 5)"); }
fn genI32_6(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 6)"); }
fn genI32_7(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 7)"); }
fn genI32_8(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 8)"); }
fn genI32_16(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 16)"); }
fn genI32_24(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 24)"); }
fn genI32_32(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 32)"); }
fn genI32_40(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 40)"); }
fn genI32_48(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 48)"); }
fn genI32_56(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 56)"); }
fn genI32_64(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 64)"); }
fn genI32_72(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 72)"); }
fn genI32_128(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 128)"); }
fn genI32_136(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 136)"); }
fn genI32_144(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 144)"); }
fn genI32_152(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 152)"); }
fn genI32_160(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 160)"); }
fn genI32_168(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 168)"); }
fn genI32_176(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 176)"); }
fn genI32_184(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 184)"); }

// Functions with logic
fn genLOG_MASK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("(@as(i32, 1) << @intCast("); try self.genExpr(args[0]); try self.emit("))"); }
    else try self.emit("@as(i32, 0)");
}

fn genLOG_UPTO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("((@as(i32, 1) << (@intCast("); try self.genExpr(args[0]); try self.emit(") + 1)) - 1)"); }
    else try self.emit("@as(i32, 0)");
}
