/// Python termios module - POSIX style tty control
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "tcgetattr", genConst("&[_]u32{ 0, 0, 0, 0, 0, 0 }") }, .{ "tcsetattr", genConst("{}") },
    .{ "tcsendbreak", genConst("{}") }, .{ "tcdrain", genConst("{}") },
    .{ "tcflush", genConst("{}") }, .{ "tcflow", genConst("{}") },
    .{ "tcgetwinsize", genConst(".{ @as(u16, 24), @as(u16, 80) }") }, .{ "tcsetwinsize", genConst("{}") },
    .{ "TCSANOW", genConst("@as(i32, 0)") }, .{ "TCSADRAIN", genConst("@as(i32, 1)") }, .{ "TCSAFLUSH", genConst("@as(i32, 2)") },
    .{ "TCIFLUSH", genConst("@as(i32, 0)") }, .{ "TCOFLUSH", genConst("@as(i32, 1)") }, .{ "TCIOFLUSH", genConst("@as(i32, 2)") },
    .{ "TCOOFF", genConst("@as(i32, 0)") }, .{ "TCOON", genConst("@as(i32, 1)") }, .{ "TCIOFF", genConst("@as(i32, 2)") }, .{ "TCION", genConst("@as(i32, 3)") },
    .{ "ECHO", genConst("@as(u32, 0x00000008)") }, .{ "ECHOE", genConst("@as(u32, 0x00000002)") },
    .{ "ECHOK", genConst("@as(u32, 0x00000004)") }, .{ "ECHONL", genConst("@as(u32, 0x00000010)") },
    .{ "ICANON", genConst("@as(u32, 0x00000100)") }, .{ "ISIG", genConst("@as(u32, 0x00000080)") }, .{ "IEXTEN", genConst("@as(u32, 0x00000400)") },
    .{ "ICRNL", genConst("@as(u32, 0x00000100)") }, .{ "IXON", genConst("@as(u32, 0x00000200)") }, .{ "IXOFF", genConst("@as(u32, 0x00000400)") },
    .{ "OPOST", genConst("@as(u32, 0x00000001)") }, .{ "ONLCR", genConst("@as(u32, 0x00000002)") },
    .{ "CS8", genConst("@as(u32, 0x00000300)") }, .{ "CREAD", genConst("@as(u32, 0x00000800)") }, .{ "CLOCAL", genConst("@as(u32, 0x00008000)") },
    .{ "B9600", genConst("@as(u32, 9600)") }, .{ "B19200", genConst("@as(u32, 19200)") },
    .{ "B38400", genConst("@as(u32, 38400)") }, .{ "B57600", genConst("@as(u32, 57600)") }, .{ "B115200", genConst("@as(u32, 115200)") },
    .{ "VMIN", genConst("@as(usize, 16)") }, .{ "VTIME", genConst("@as(usize, 17)") }, .{ "NCCS", genConst("@as(usize, 20)") },
});
