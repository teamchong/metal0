/// Python termios module - POSIX style tty control
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genTcgetattr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]u32{ 0, 0, 0, 0, 0, 0 }"); }
fn genTcgetwinsize(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ @as(u16, 24), @as(u16, 80) }"); }
fn genI32(comptime n: comptime_int) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, std.fmt.comptimePrint("@as(i32, {})", .{n})); } }.f;
}
fn genU32(comptime n: comptime_int) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, std.fmt.comptimePrint("@as(u32, {})", .{n})); } }.f;
}
fn genHex(comptime v: []const u8) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, " ++ v ++ ")"); } }.f;
}
fn genUsize(comptime n: comptime_int) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, std.fmt.comptimePrint("@as(usize, {})", .{n})); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "tcgetattr", genTcgetattr }, .{ "tcsetattr", genUnit }, .{ "tcsendbreak", genUnit }, .{ "tcdrain", genUnit },
    .{ "tcflush", genUnit }, .{ "tcflow", genUnit }, .{ "tcgetwinsize", genTcgetwinsize }, .{ "tcsetwinsize", genUnit },
    .{ "TCSANOW", genI32(0) }, .{ "TCSADRAIN", genI32(1) }, .{ "TCSAFLUSH", genI32(2) },
    .{ "TCIFLUSH", genI32(0) }, .{ "TCOFLUSH", genI32(1) }, .{ "TCIOFLUSH", genI32(2) },
    .{ "TCOOFF", genI32(0) }, .{ "TCOON", genI32(1) }, .{ "TCIOFF", genI32(2) }, .{ "TCION", genI32(3) },
    .{ "ECHO", genHex("0x00000008") }, .{ "ECHOE", genHex("0x00000002") }, .{ "ECHOK", genHex("0x00000004") }, .{ "ECHONL", genHex("0x00000010") },
    .{ "ICANON", genHex("0x00000100") }, .{ "ISIG", genHex("0x00000080") }, .{ "IEXTEN", genHex("0x00000400") },
    .{ "ICRNL", genHex("0x00000100") }, .{ "IXON", genHex("0x00000200") }, .{ "IXOFF", genHex("0x00000400") },
    .{ "OPOST", genHex("0x00000001") }, .{ "ONLCR", genHex("0x00000002") },
    .{ "CS8", genHex("0x00000300") }, .{ "CREAD", genHex("0x00000800") }, .{ "CLOCAL", genHex("0x00008000") },
    .{ "B9600", genU32(9600) }, .{ "B19200", genU32(19200) }, .{ "B38400", genU32(38400) }, .{ "B57600", genU32(57600) }, .{ "B115200", genU32(115200) },
    .{ "VMIN", genUsize(16) }, .{ "VTIME", genUsize(17) }, .{ "NCCS", genUsize(20) },
});
