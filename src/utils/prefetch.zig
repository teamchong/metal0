//! Cross-platform async I/O prefetching utilities
//! Hints the OS to load files into page cache before Zig compiler needs them.
//! All syscalls are no-op on failure - they only provide hints to the kernel.

const std = @import("std");
const builtin = @import("builtin");

/// Prefetch a file descriptor into page cache
/// On Linux: uses readahead()
/// On macOS/BSD: uses posix_fadvise() with POSIX_FADV_WILLNEED
pub fn prefetchFile(fd: std.posix.fd_t, offset: u64, length: u64) void {
    if (comptime builtin.os.tag == .linux) {
        prefetchLinux(fd, offset, length);
    } else if (comptime builtin.os.tag == .macos or builtin.os.tag == .freebsd) {
        prefetchPosix(fd, offset, length);
    }
}

fn prefetchLinux(fd: std.posix.fd_t, offset: u64, length: u64) void {
    const readahead = @extern(*const fn (std.posix.fd_t, i64, usize) callconv(.C) isize, .{
        .name = "readahead",
        .library_name = "c",
    });
    _ = readahead(fd, @intCast(offset), @intCast(length));
}

fn prefetchPosix(fd: std.posix.fd_t, offset: u64, length: u64) void {
    const fadvise = @extern(*const fn (std.posix.fd_t, i64, i64, c_int) callconv(.C) c_int, .{
        .name = "posix_fadvise",
        .library_name = "c",
    });
    const POSIX_FADV_WILLNEED = 3;
    _ = fadvise(fd, @intCast(offset), @intCast(length), POSIX_FADV_WILLNEED);
}

/// Prefetch memory-mapped data into page cache
/// Uses madvise() with MADV_WILLNEED on macOS/BSD
pub fn prefetchMappedData(data: []align(std.mem.page_size) const u8) void {
    if (comptime builtin.os.tag == .macos or builtin.os.tag == .freebsd) {
        const madvise = @extern(*const fn ([*]align(std.mem.page_size) const u8, usize, c_int) callconv(.C) c_int, .{
            .name = "madvise",
            .library_name = "c",
        });
        const MADV_WILLNEED = 3;
        _ = madvise(data.ptr, data.len, MADV_WILLNEED);
    }
}

/// Prefetch multiple source files in parallel using separate threads
/// Each file is opened and prefetched concurrently for maximum I/O throughput
pub fn prefetchSourceFiles(allocator: std.mem.Allocator, paths: []const []const u8) !void {
    var threads: std.ArrayList(std.Thread) = .{};
    defer {
        for (threads.items) |t| t.join();
        threads.deinit(allocator);
    }

    for (paths) |path| {
        const thread = try std.Thread.spawn(.{}, prefetchSourceFile, .{path});
        try threads.append(allocator, thread);
    }
}

fn prefetchSourceFile(path: []const u8) void {
    const fd = std.posix.open(path, .{ .ACCMODE = .RDONLY }, 0) catch return;
    defer std.posix.close(fd);

    const stat = std.posix.fstat(fd) catch return;
    prefetchFile(fd, 0, @intCast(stat.size));
}
