/// File descriptor operations
/// CPython Reference: https://docs.python.org/3.12/library/os.html#file-descriptor-operations
const std = @import("std");

/// Open a file and return a file descriptor
pub fn open(path_: []const u8, flags: std.posix.O, mode: std.posix.mode_t) !std.posix.fd_t {
    return try std.posix.open(path_, flags, mode);
}

/// Close a file descriptor
pub fn close(fd: std.posix.fd_t) void {
    std.posix.close(fd);
}

/// Read from a file descriptor
pub fn read(fd: std.posix.fd_t, buf: []u8) !usize {
    return try std.posix.read(fd, buf);
}

/// Write to a file descriptor
pub fn write(fd: std.posix.fd_t, buf: []const u8) !usize {
    return try std.posix.write(fd, buf);
}
