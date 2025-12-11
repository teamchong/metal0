/// Process control and information
/// CPython Reference: https://docs.python.org/3.12/library/os.html#process-management
const std = @import("std");

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

// ============================================================================
// Wait Constants and Macros
// ============================================================================

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
