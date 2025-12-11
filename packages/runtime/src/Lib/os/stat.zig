/// File status (stat) operations
/// CPython Reference: https://docs.python.org/3.12/library/os.html#os.stat
const std = @import("std");

/// Python os.stat_result - complete file status information
/// Mirrors all fields from CPython's stat_result
pub const stat_result = struct {
    // Core fields (always available)
    st_mode: u32, // File mode (permissions + file type)
    st_ino: u64, // Inode number
    st_dev: u64, // Device ID
    st_nlink: u64, // Number of hard links
    st_uid: u32, // User ID of owner
    st_gid: u32, // Group ID of owner
    st_size: i64, // Total size in bytes
    // Time fields (seconds since epoch)
    st_atime: i64, // Time of last access
    st_mtime: i64, // Time of last modification
    st_ctime: i64, // Time of last status change (Unix) / creation (Windows)
    // Nanosecond precision time fields
    st_atime_ns: i128, // Access time in nanoseconds
    st_mtime_ns: i128, // Modification time in nanoseconds
    st_ctime_ns: i128, // Change/creation time in nanoseconds
    // Platform-specific fields (0 on unsupported platforms)
    st_blocks: i64, // Number of 512-byte blocks allocated
    st_blksize: i64, // Preferred block size for I/O
    st_rdev: u64, // Device ID (if special file)
    // Additional fields for compatibility
    st_flags: u32 = 0, // User-defined flags (BSD/macOS)
    st_gen: u32 = 0, // File generation number (BSD/macOS)

    /// Check if this is a regular file
    pub fn isFile(self: stat_result) bool {
        return (self.st_mode & 0o170000) == 0o100000; // S_IFREG
    }

    /// Check if this is a directory
    pub fn isDir(self: stat_result) bool {
        return (self.st_mode & 0o170000) == 0o040000; // S_IFDIR
    }

    /// Check if this is a symbolic link
    pub fn isLink(self: stat_result) bool {
        return (self.st_mode & 0o170000) == 0o120000; // S_IFLNK
    }

    /// Check if this is a block device
    pub fn isBlockDevice(self: stat_result) bool {
        return (self.st_mode & 0o170000) == 0o060000; // S_IFBLK
    }

    /// Check if this is a character device
    pub fn isCharDevice(self: stat_result) bool {
        return (self.st_mode & 0o170000) == 0o020000; // S_IFCHR
    }

    /// Check if this is a FIFO (named pipe)
    pub fn isFifo(self: stat_result) bool {
        return (self.st_mode & 0o170000) == 0o010000; // S_IFIFO
    }

    /// Check if this is a socket
    pub fn isSocket(self: stat_result) bool {
        return (self.st_mode & 0o170000) == 0o140000; // S_IFSOCK
    }
};

/// Alias for backwards compatibility
pub const StatResult = stat_result;

var path_buf: [std.fs.max_path_bytes]u8 = undefined;

/// Get file status (follows symlinks)
pub fn stat(path_: []const u8) !stat_result {
    // Use std.posix.stat for full stat info
    const path_z = std.fs.cwd().realpathZ(path_, &path_buf) catch {
        // If realpath fails, try direct stat
        return statInternal(path_);
    };
    _ = path_z;
    return statInternal(path_);
}

fn statInternal(path_: []const u8) !stat_result {
    // Use POSIX stat for full info including blocks
    const s = std.posix.stat(path_) catch {
        // Fallback to std.fs if POSIX stat fails
        const fs_stat = try std.fs.cwd().statFile(path_);
        return .{
            .st_mode = @intCast(fs_stat.mode),
            .st_ino = fs_stat.inode,
            .st_dev = 0,
            .st_nlink = 1,
            .st_uid = 0,
            .st_gid = 0,
            .st_size = @intCast(fs_stat.size),
            .st_atime = @intCast(@divFloor(fs_stat.atime, std.time.ns_per_s)),
            .st_mtime = @intCast(@divFloor(fs_stat.mtime, std.time.ns_per_s)),
            .st_ctime = @intCast(@divFloor(fs_stat.ctime, std.time.ns_per_s)),
            .st_atime_ns = fs_stat.atime,
            .st_mtime_ns = fs_stat.mtime,
            .st_ctime_ns = fs_stat.ctime,
            .st_blocks = @divTrunc(@as(i64, @intCast(fs_stat.size)) + 511, 512),
            .st_blksize = 4096,
            .st_rdev = 0,
        };
    };

    return .{
        .st_mode = s.mode,
        .st_ino = s.ino,
        .st_dev = s.dev,
        .st_nlink = s.nlink,
        .st_uid = s.uid,
        .st_gid = s.gid,
        .st_size = @intCast(s.size),
        .st_atime = s.atime().sec,
        .st_mtime = s.mtime().sec,
        .st_ctime = s.ctime().sec,
        .st_atime_ns = @as(i128, s.atime().sec) * std.time.ns_per_s + s.atime().nsec,
        .st_mtime_ns = @as(i128, s.mtime().sec) * std.time.ns_per_s + s.mtime().nsec,
        .st_ctime_ns = @as(i128, s.ctime().sec) * std.time.ns_per_s + s.ctime().nsec,
        .st_blocks = @intCast(s.blocks),
        .st_blksize = @intCast(s.blksize),
        .st_rdev = s.rdev,
    };
}

/// Get file status without following symlinks
pub fn lstat(path_: []const u8) !stat_result {
    // Use lstat syscall directly to avoid following symlinks
    const s = try std.posix.lstat(path_);
    return .{
        .st_mode = s.mode,
        .st_ino = s.ino,
        .st_dev = s.dev,
        .st_nlink = s.nlink,
        .st_uid = s.uid,
        .st_gid = s.gid,
        .st_size = @intCast(s.size),
        .st_atime = s.atime().sec,
        .st_mtime = s.mtime().sec,
        .st_ctime = s.ctime().sec,
        .st_atime_ns = @as(i128, s.atime().sec) * std.time.ns_per_s + s.atime().nsec,
        .st_mtime_ns = @as(i128, s.mtime().sec) * std.time.ns_per_s + s.mtime().nsec,
        .st_ctime_ns = @as(i128, s.ctime().sec) * std.time.ns_per_s + s.ctime().nsec,
        .st_blocks = 0,
        .st_blksize = 4096,
        .st_rdev = 0,
    };
}

/// Get file status from file descriptor
pub fn fstat(fd: std.posix.fd_t) !stat_result {
    const s = try std.posix.fstat(fd);
    return .{
        .st_mode = s.mode,
        .st_ino = s.ino,
        .st_dev = s.dev,
        .st_nlink = s.nlink,
        .st_uid = s.uid,
        .st_gid = s.gid,
        .st_size = @intCast(s.size),
        .st_atime = s.atime().sec,
        .st_mtime = s.mtime().sec,
        .st_ctime = s.ctime().sec,
        .st_atime_ns = @as(i128, s.atime().sec) * std.time.ns_per_s + s.atime().nsec,
        .st_mtime_ns = @as(i128, s.mtime().sec) * std.time.ns_per_s + s.mtime().nsec,
        .st_ctime_ns = @as(i128, s.ctime().sec) * std.time.ns_per_s + s.ctime().nsec,
        .st_blocks = s.blocks,
        .st_blksize = s.blksize,
        .st_rdev = s.rdev,
    };
}
