/// Python telnetlib module - Telnet client class
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}
fn genU8(comptime n: comptime_int) ModuleHandler { return genConst(std.fmt.comptimePrint("@as(u8, {})", .{n})); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Telnet", genConst(".{ .host = @as(?[]const u8, null), .port = @as(i32, 23), .timeout = @as(f64, -1.0), .sock = @as(?*anyopaque, null) }") },
    .{ "TELNET_PORT", genConst("@as(i32, 23)") },
    .{ "THEOPT", genU8(0) }, .{ "ECHO", genU8(1) }, .{ "SGA", genU8(3) }, .{ "TTYPE", genU8(24) },
    .{ "NAWS", genU8(31) }, .{ "LINEMODE", genU8(34) }, .{ "XDISPLOC", genU8(35) },
    .{ "AUTHENTICATION", genU8(37) }, .{ "ENCRYPT", genU8(38) }, .{ "NEW_ENVIRON", genU8(39) },
    .{ "SE", genU8(240) }, .{ "NOP", genU8(241) }, .{ "DM", genU8(242) }, .{ "BRK", genU8(243) },
    .{ "IP", genU8(244) }, .{ "AO", genU8(245) }, .{ "AYT", genU8(246) }, .{ "EC", genU8(247) },
    .{ "EL", genU8(248) }, .{ "GA", genU8(249) }, .{ "SB", genU8(250) }, .{ "WILL", genU8(251) },
    .{ "WONT", genU8(252) }, .{ "DO", genU8(253) }, .{ "DONT", genU8(254) }, .{ "IAC", genU8(255) },
});
