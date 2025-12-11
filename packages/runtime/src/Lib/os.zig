/// os module - Operating system interfaces
/// CPython Reference: https://docs.python.org/3.12/library/os.html
const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Constants
// ============================================================================

/// Path separator for the current platform
pub const sep: []const u8 = if (builtin.os.tag == .windows) "\\" else "/";

/// Alternative path separator (Windows only)
pub const altsep: ?[]const u8 = if (builtin.os.tag == .windows) "/" else null;

/// Path list separator (PATH environment variable)
pub const pathsep: []const u8 = if (builtin.os.tag == .windows) ";" else ":";

/// Line separator
pub const linesep: []const u8 = if (builtin.os.tag == .windows) "\r\n" else "\n";

/// Current directory string
pub const curdir: []const u8 = ".";

/// Parent directory string
pub const pardir: []const u8 = "..";

/// Extension separator
pub const extsep: []const u8 = ".";

/// Device null file
pub const devnull: []const u8 = if (builtin.os.tag == .windows) "NUL" else "/dev/null";

/// Platform name
pub const name: []const u8 = switch (builtin.os.tag) {
    .windows => "nt",
    else => "posix",
};

// ============================================================================
// Process Parameters
// ============================================================================

/// Get current working directory
pub fn getcwd(allocator: std.mem.Allocator) ![]const u8 {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = try std.fs.cwd().realpath(".", &buf);
    return try allocator.dupe(u8, cwd);
}

/// Change current working directory
pub fn chdir(dir_path: []const u8) !void {
    try std.posix.chdir(dir_path);
}

/// Get process ID
pub fn getpid() std.posix.pid_t {
    return std.posix.system.getpid();
}

/// Get parent process ID
pub fn getppid() std.posix.pid_t {
    return std.posix.system.getppid();
}

// ============================================================================
// File and Directory Operations
// ============================================================================

/// List directory contents
pub fn listdir(allocator: std.mem.Allocator, dir_path: []const u8) ![][]const u8 {
    var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();

    var entries = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (entries.items) |entry| allocator.free(entry);
        entries.deinit();
    }

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        try entries.append(try allocator.dupe(u8, entry.name));
    }

    return entries.toOwnedSlice();
}

/// Create a directory
pub fn mkdir(dir_path: []const u8) !void {
    try std.fs.cwd().makeDir(dir_path);
}

/// Create a directory and all parent directories
pub fn makedirs(dir_path: []const u8) !void {
    std.fs.cwd().makePath(dir_path) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
}

/// Remove a file
pub fn remove(file_path: []const u8) !void {
    try std.fs.cwd().deleteFile(file_path);
}

/// Alias for remove
pub const unlink = remove;

/// Remove an empty directory
pub fn rmdir(dir_path: []const u8) !void {
    try std.fs.cwd().deleteDir(dir_path);
}

/// Remove a directory tree recursively
pub fn removedirs(dir_path: []const u8) !void {
    try std.fs.cwd().deleteTree(dir_path);
}

/// Rename a file or directory
pub fn rename(src: []const u8, dst: []const u8) !void {
    try std.fs.cwd().rename(src, dst);
}

/// Check if a path exists
pub fn exists(file_path: []const u8) bool {
    std.fs.cwd().access(file_path, .{}) catch return false;
    return true;
}

/// Check if path is a file
pub fn isfile(file_path: []const u8) bool {
    const file_stat = std.fs.cwd().statFile(file_path) catch return false;
    return file_stat.kind == .file;
}

/// Check if path is a directory
pub fn isdir(dir_path: []const u8) bool {
    var dir = std.fs.cwd().openDir(dir_path, .{}) catch return false;
    dir.close();
    return true;
}

/// Get file size
pub fn getsize(file_path: []const u8) !u64 {
    const file_stat = try std.fs.cwd().statFile(file_path);
    return file_stat.size;
}

// ============================================================================
// os.path module
// ============================================================================

pub const path = struct {
    /// Join path components
    pub fn join(allocator: std.mem.Allocator, paths: []const []const u8) ![]const u8 {
        if (paths.len == 0) return try allocator.dupe(u8, "");

        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        for (paths, 0..) |p, i| {
            if (p.len == 0) continue;

            // If path is absolute, start fresh
            if (isabs(p)) {
                result.clearRetainingCapacity();
                try result.appendSlice(p);
            } else {
                // Add separator if needed
                if (result.items.len > 0 and result.items[result.items.len - 1] != sep[0]) {
                    try result.appendSlice(sep);
                }
                try result.appendSlice(p);
            }
            _ = i;
        }

        return result.toOwnedSlice();
    }

    /// Check if path is absolute
    pub fn isabs(p: []const u8) bool {
        if (p.len == 0) return false;
        if (builtin.os.tag == .windows) {
            // Check for drive letter or UNC path
            if (p.len >= 2 and p[1] == ':') return true;
            if (p.len >= 2 and p[0] == '\\' and p[1] == '\\') return true;
        }
        return p[0] == '/';
    }

    /// Get the base name of a path
    pub fn basename(p: []const u8) []const u8 {
        if (p.len == 0) return "";

        // Find last separator
        var i = p.len;
        while (i > 0) {
            i -= 1;
            if (p[i] == '/' or (builtin.os.tag == .windows and p[i] == '\\')) {
                return p[i + 1 ..];
            }
        }
        return p;
    }

    /// Get the directory name of a path
    pub fn dirname(p: []const u8) []const u8 {
        if (p.len == 0) return "";

        // Find last separator
        var i = p.len;
        while (i > 0) {
            i -= 1;
            if (p[i] == '/' or (builtin.os.tag == .windows and p[i] == '\\')) {
                if (i == 0) return "/";
                return p[0..i];
            }
        }
        return "";
    }

    /// Split path into (head, tail) where tail is the last component
    pub fn split(p: []const u8) struct { head: []const u8, tail: []const u8 } {
        return .{
            .head = dirname(p),
            .tail = basename(p),
        };
    }

    /// Split path into (root, ext) where ext is the file extension
    pub fn splitext(p: []const u8) struct { root: []const u8, ext: []const u8 } {
        const base = basename(p);
        if (base.len == 0) return .{ .root = p, .ext = "" };

        // Find last dot (but not leading dot)
        var i = base.len;
        while (i > 1) {
            i -= 1;
            if (base[i] == '.') {
                const dir = dirname(p);
                if (dir.len == 0) {
                    return .{ .root = base[0..i], .ext = base[i..] };
                } else {
                    // Need to reconstruct full path
                    return .{ .root = p[0 .. p.len - (base.len - i)], .ext = base[i..] };
                }
            }
        }
        return .{ .root = p, .ext = "" };
    }

    /// Check if path exists
    pub fn pathExists(p: []const u8) bool {
        return exists(p);
    }

    /// Check if path is a file
    pub fn isFile(p: []const u8) bool {
        return isfile(p);
    }

    /// Check if path is a directory
    pub fn isDir(p: []const u8) bool {
        return isdir(p);
    }

    /// Get absolute path
    pub fn abspath(allocator: std.mem.Allocator, p: []const u8) ![]const u8 {
        if (isabs(p)) {
            return try allocator.dupe(u8, p);
        }

        const cwd = try getcwd(allocator);
        defer allocator.free(cwd);

        const paths = [_][]const u8{ cwd, p };
        return try join(allocator, &paths);
    }

    /// Normalize a path (remove redundant separators, resolve . and ..)
    pub fn normpath(allocator: std.mem.Allocator, p: []const u8) ![]const u8 {
        if (p.len == 0) return try allocator.dupe(u8, ".");

        var components = std.ArrayList([]const u8).init(allocator);
        defer components.deinit();

        const is_absolute = isabs(p);
        var iter = std.mem.splitScalar(u8, p, '/');

        while (iter.next()) |component| {
            if (component.len == 0 or std.mem.eql(u8, component, ".")) {
                continue;
            }
            if (std.mem.eql(u8, component, "..")) {
                if (components.items.len > 0 and !std.mem.eql(u8, components.items[components.items.len - 1], "..")) {
                    _ = components.pop();
                } else if (!is_absolute) {
                    try components.append("..");
                }
            } else {
                try components.append(component);
            }
        }

        if (components.items.len == 0) {
            return try allocator.dupe(u8, if (is_absolute) "/" else ".");
        }

        var result = std.ArrayList(u8).init(allocator);
        if (is_absolute) try result.append('/');

        for (components.items, 0..) |comp, i| {
            if (i > 0) try result.append('/');
            try result.appendSlice(comp);
        }

        return result.toOwnedSlice();
    }
};

// ============================================================================
// Environment Variables
// ============================================================================

/// Get an environment variable
pub fn getenv(key: []const u8) ?[]const u8 {
    return std.posix.getenv(key);
}

/// Get environment variable with default
pub fn getenvDefault(key: []const u8, default: []const u8) []const u8 {
    return getenv(key) orelse default;
}

// ============================================================================
// File Descriptor Operations
// ============================================================================

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

// ============================================================================
// Stat Result
// ============================================================================

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

var path_buf: [std.fs.max_path_bytes]u8 = undefined;

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

// ============================================================================
// Directory Traversal
// ============================================================================

/// Entry from os.walk() - (dirpath, dirnames, filenames)
pub const WalkEntry = struct {
    dirpath: []const u8,
    dirnames: [][]const u8,
    filenames: [][]const u8,
};

/// Iterator for os.walk() - recursive directory traversal
pub const WalkIterator = struct {
    allocator: std.mem.Allocator,
    stack: std.ArrayList([]const u8),
    topdown: bool,

    pub fn next(self: *WalkIterator) !?WalkEntry {
        while (self.stack.items.len > 0) {
            const dir_path = self.stack.pop();
            defer self.allocator.free(dir_path);

            var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch continue;
            defer dir.close();

            var dirnames = std.ArrayList([]const u8).init(self.allocator);
            var filenames = std.ArrayList([]const u8).init(self.allocator);
            errdefer {
                for (dirnames.items) |d| self.allocator.free(d);
                dirnames.deinit();
                for (filenames.items) |f| self.allocator.free(f);
                filenames.deinit();
            }

            var iter = dir.iterate();
            while (iter.next() catch null) |entry| {
                const entry_name = try self.allocator.dupe(u8, entry.name);
                if (entry.kind == .directory) {
                    try dirnames.append(entry_name);
                } else {
                    try filenames.append(entry_name);
                }
            }

            // Add subdirectories to stack for traversal
            if (self.topdown) {
                // For topdown, add in reverse order so we process in order
                var i: usize = dirnames.items.len;
                while (i > 0) {
                    i -= 1;
                    const subdir = try path.join(self.allocator, &.{ dir_path, dirnames.items[i] });
                    try self.stack.append(subdir);
                }
            }

            return WalkEntry{
                .dirpath = try self.allocator.dupe(u8, dir_path),
                .dirnames = try dirnames.toOwnedSlice(),
                .filenames = try filenames.toOwnedSlice(),
            };
        }
        return null;
    }

    pub fn deinit(self: *WalkIterator) void {
        for (self.stack.items) |p| self.allocator.free(p);
        self.stack.deinit();
    }
};

/// os.walk(top, topdown=True) - Directory tree generator
/// Yields (dirpath, dirnames, filenames) for each directory in the tree
pub fn walk(allocator: std.mem.Allocator, top: []const u8) !WalkIterator {
    return walkTopdown(allocator, top, true);
}

/// os.walk with topdown parameter
pub fn walkTopdown(allocator: std.mem.Allocator, top: []const u8, topdown: bool) !WalkIterator {
    var stack = std.ArrayList([]const u8).init(allocator);
    try stack.append(try allocator.dupe(u8, top));
    return WalkIterator{
        .allocator = allocator,
        .stack = stack,
        .topdown = topdown,
    };
}

// ============================================================================
// Process Control
// ============================================================================

/// fork() - Create a child process
/// Returns: 0 in child, child PID in parent
/// Note: Only available on POSIX systems (Linux, macOS, BSD)
pub fn fork() !std.posix.pid_t {
    return try std.posix.fork();
}

/// execv(path, args) - Execute a program, replacing current process
/// path: Path to executable
/// args: Array of arguments (first is usually program name)
pub fn execv(path_: [*:0]const u8, argv: [*:null]const ?[*:0]const u8) error{SystemResources, InvalidExe, FileNotFound, AccessDenied, NotDir, Unexpected}!noreturn {
    return std.posix.execveZ(path_, argv, @ptrCast(std.os.environ.ptr));
}

/// execve(path, args, env) - Execute with environment
pub fn execve(path_: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8) error{SystemResources, InvalidExe, FileNotFound, AccessDenied, NotDir, Unexpected}!noreturn {
    return std.posix.execveZ(path_, argv, envp);
}

/// execvp(file, args) - Execute searching PATH
/// file: Program name (searched in PATH)
/// args: Array of arguments
pub fn execvp(file: [*:0]const u8, argv: [*:null]const ?[*:0]const u8) error{SystemResources, InvalidExe, FileNotFound, AccessDenied, NotDir, Unexpected}!noreturn {
    return std.posix.execvpeZ(file, argv, @ptrCast(std.os.environ.ptr));
}

/// _exit(status) - Exit immediately without cleanup
pub fn _exit(status: u8) noreturn {
    std.posix.exit(status);
}

/// wait() - Wait for any child process to terminate
/// Returns: (pid, status) tuple
pub fn wait() !struct { pid: std.posix.pid_t, status: u32 } {
    const result = std.posix.waitpid(-1, .{});
    return .{ .pid = result.pid, .status = result.status };
}

/// waitpid(pid, options) - Wait for specific child process
pub fn waitpid(pid: std.posix.pid_t, options: u32) !struct { pid: std.posix.pid_t, status: u32 } {
    const result = std.posix.waitpid(pid, .{ .NOHANG = (options & 1) != 0 });
    return .{ .pid = result.pid, .status = result.status };
}

/// kill(pid, sig) - Send signal to process
pub fn kill(pid: std.posix.pid_t, sig: u8) !void {
    return std.posix.kill(pid, sig);
}

/// getuid() - Get real user ID
pub fn getuid() std.posix.uid_t {
    return std.posix.system.getuid();
}

/// geteuid() - Get effective user ID
pub fn geteuid() std.posix.uid_t {
    return std.posix.system.geteuid();
}

/// getgid() - Get real group ID
pub fn getgid() std.posix.gid_t {
    return std.posix.system.getgid();
}

/// getegid() - Get effective group ID
pub fn getegid() std.posix.gid_t {
    return std.posix.system.getegid();
}

/// setsid() - Create new session
pub fn setsid() !std.posix.pid_t {
    return std.posix.setsid();
}

/// setuid(uid) - Set user ID
pub fn setuid(uid: std.posix.uid_t) !void {
    return std.posix.setuid(uid);
}

/// setgid(gid) - Set group ID
pub fn setgid(gid: std.posix.gid_t) !void {
    return std.posix.setgid(gid);
}

/// WNOHANG flag for waitpid
pub const WNOHANG: u32 = 1;

/// WUNTRACED flag for waitpid
pub const WUNTRACED: u32 = 2;

/// Extract exit status from wait status
pub fn WEXITSTATUS(status: u32) u8 {
    return @intCast((status >> 8) & 0xff);
}

/// Check if child exited normally
pub fn WIFEXITED(status: u32) bool {
    return (status & 0x7f) == 0;
}

/// Check if child was signaled
pub fn WIFSIGNALED(status: u32) bool {
    return ((status & 0x7f) + 1) >> 1 > 0;
}

/// Get signal that terminated child
pub fn WTERMSIG(status: u32) u8 {
    return @intCast(status & 0x7f);
}

/// Check if child is stopped
pub fn WIFSTOPPED(status: u32) bool {
    return (status & 0xff) == 0x7f;
}

/// Get signal that stopped child
pub fn WSTOPSIG(status: u32) u8 {
    return WEXITSTATUS(status);
}

// ============================================================================
// Tests
// ============================================================================

test "os.path.basename" {
    try std.testing.expectEqualStrings("file.txt", path.basename("/home/user/file.txt"));
    try std.testing.expectEqualStrings("file.txt", path.basename("file.txt"));
    try std.testing.expectEqualStrings("", path.basename("/home/user/"));
    try std.testing.expectEqualStrings("", path.basename(""));
}

test "os.path.dirname" {
    try std.testing.expectEqualStrings("/home/user", path.dirname("/home/user/file.txt"));
    try std.testing.expectEqualStrings("", path.dirname("file.txt"));
    try std.testing.expectEqualStrings("/home/user", path.dirname("/home/user/"));
}

test "os.path.splitext" {
    const r1 = path.splitext("/home/user/file.txt");
    try std.testing.expectEqualStrings("/home/user/file", r1.root);
    try std.testing.expectEqualStrings(".txt", r1.ext);

    const r2 = path.splitext("file");
    try std.testing.expectEqualStrings("file", r2.root);
    try std.testing.expectEqualStrings("", r2.ext);

    const r3 = path.splitext(".hidden");
    try std.testing.expectEqualStrings(".hidden", r3.root);
    try std.testing.expectEqualStrings("", r3.ext);
}

test "os.path.isabs" {
    try std.testing.expect(path.isabs("/home/user"));
    try std.testing.expect(!path.isabs("relative/path"));
    try std.testing.expect(!path.isabs(""));
}

test "os.path.join" {
    const allocator = std.testing.allocator;

    const p1 = try path.join(allocator, &.{ "/home", "user", "file.txt" });
    defer allocator.free(p1);
    try std.testing.expectEqualStrings("/home/user/file.txt", p1);

    const p2 = try path.join(allocator, &.{ "relative", "path" });
    defer allocator.free(p2);
    try std.testing.expectEqualStrings("relative/path", p2);
}
