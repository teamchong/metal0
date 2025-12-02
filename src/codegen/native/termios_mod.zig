/// Python termios module - POSIX style tty control
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "tcgetattr", h.c("&[_]u32{ 0, 0, 0, 0, 0, 0 }") }, .{ "tcsetattr", h.c("{}") },
    .{ "tcsendbreak", h.c("{}") }, .{ "tcdrain", h.c("{}") },
    .{ "tcflush", h.c("{}") }, .{ "tcflow", h.c("{}") },
    .{ "tcgetwinsize", h.c(".{ @as(u16, 24), @as(u16, 80) }") }, .{ "tcsetwinsize", h.c("{}") },
    .{ "TCSANOW", h.I32(0) }, .{ "TCSADRAIN", h.I32(1) }, .{ "TCSAFLUSH", h.I32(2) },
    .{ "TCIFLUSH", h.I32(0) }, .{ "TCOFLUSH", h.I32(1) }, .{ "TCIOFLUSH", h.I32(2) },
    .{ "TCOOFF", h.I32(0) }, .{ "TCOON", h.I32(1) }, .{ "TCIOFF", h.I32(2) }, .{ "TCION", h.I32(3) },
    .{ "ECHO", h.U32(0x00000008) }, .{ "ECHOE", h.U32(0x00000002) },
    .{ "ECHOK", h.U32(0x00000004) }, .{ "ECHONL", h.U32(0x00000010) },
    .{ "ICANON", h.U32(0x00000100) }, .{ "ISIG", h.U32(0x00000080) }, .{ "IEXTEN", h.U32(0x00000400) },
    .{ "ICRNL", h.U32(0x00000100) }, .{ "IXON", h.U32(0x00000200) }, .{ "IXOFF", h.U32(0x00000400) },
    .{ "OPOST", h.U32(0x00000001) }, .{ "ONLCR", h.U32(0x00000002) },
    .{ "CS8", h.U32(0x00000300) }, .{ "CREAD", h.U32(0x00000800) }, .{ "CLOCAL", h.U32(0x00008000) },
    .{ "B9600", h.U32(9600) }, .{ "B19200", h.U32(19200) },
    .{ "B38400", h.U32(38400) }, .{ "B57600", h.U32(57600) }, .{ "B115200", h.U32(115200) },
    .{ "VMIN", h.c("@as(usize, 16)") }, .{ "VTIME", h.c("@as(usize, 17)") }, .{ "NCCS", h.c("@as(usize, 20)") },
});
