/// Python termios module - POSIX style tty control
/// MIGRATED TO ZIGBUILDER
/// DRY: Uses h.c(), h.I64(), h.U32() factories for constants
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    // Functions that return complex values/void
    .{ "tcgetattr", h.c("&[_]u32{ 0, 0, 0, 0, 0, 0 }") },
    .{ "tcsetattr", h.c("{}") },
    .{ "tcsendbreak", h.c("{}") },
    .{ "tcdrain", h.c("{}") },
    .{ "tcflush", h.c("{}") },
    .{ "tcflow", h.c("{}") },
    .{ "tcgetwinsize", h.c(".{ @as(u16, 24), @as(u16, 80) }") },
    .{ "tcsetwinsize", h.c("{}") },
    // tcsetattr action constants
    .{ "TCSANOW", h.I64(0) },
    .{ "TCSADRAIN", h.I64(1) },
    .{ "TCSAFLUSH", h.I64(2) },
    // tcflush queue constants
    .{ "TCIFLUSH", h.I64(0) },
    .{ "TCOFLUSH", h.I64(1) },
    .{ "TCIOFLUSH", h.I64(2) },
    // tcflow action constants
    .{ "TCOOFF", h.I64(0) },
    .{ "TCOON", h.I64(1) },
    .{ "TCIOFF", h.I64(2) },
    .{ "TCION", h.I64(3) },
    // Local mode flags (c_lflag)
    .{ "ECHO", h.c("@as(u32, 0x00000008)") },
    .{ "ECHOE", h.c("@as(u32, 0x00000002)") },
    .{ "ECHOK", h.c("@as(u32, 0x00000004)") },
    .{ "ECHONL", h.c("@as(u32, 0x00000010)") },
    .{ "ICANON", h.c("@as(u32, 0x00000100)") },
    .{ "ISIG", h.c("@as(u32, 0x00000080)") },
    .{ "IEXTEN", h.c("@as(u32, 0x00000400)") },
    // Input mode flags (c_iflag)
    .{ "ICRNL", h.c("@as(u32, 0x00000100)") },
    .{ "IXON", h.c("@as(u32, 0x00000200)") },
    .{ "IXOFF", h.c("@as(u32, 0x00000400)") },
    // Output mode flags (c_oflag)
    .{ "OPOST", h.c("@as(u32, 0x00000001)") },
    .{ "ONLCR", h.c("@as(u32, 0x00000002)") },
    // Control mode flags (c_cflag)
    .{ "CS8", h.c("@as(u32, 0x00000300)") },
    .{ "CREAD", h.c("@as(u32, 0x00000800)") },
    .{ "CLOCAL", h.c("@as(u32, 0x00008000)") },
    // Baud rate constants
    .{ "B9600", h.U32(9600) },
    .{ "B19200", h.U32(19200) },
    .{ "B38400", h.U32(38400) },
    .{ "B57600", h.U32(57600) },
    .{ "B115200", h.U32(115200) },
    // Control character indices
    .{ "VMIN", h.c("@as(usize, 16)") },
    .{ "VTIME", h.c("@as(usize, 17)") },
    .{ "NCCS", h.c("@as(usize, 20)") },
});
