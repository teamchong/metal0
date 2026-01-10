//! multiprocessing.spawn - Spawn helpers
//! Reference: cpython/Lib/multiprocessing/spawn.py
//!
//! CPython __all__: ['_main', 'freeze_support', 'set_executable', 'get_executable',
//!                   'get_preparation_data', 'get_command_line']
//!
//! Provides helper functions for spawning child processes.

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Configuration
// ============================================================================

/// Current executable path
var _executable: ?[]const u8 = null;

/// CPython: def set_executable(exe)
pub fn set_executable(exe: []const u8) void {
    _executable = exe;
}

/// CPython: def get_executable()
pub fn get_executable() []const u8 {
    if (_executable) |exe| {
        return exe;
    }
    // Default to current process
    return "/proc/self/exe";
}

// ============================================================================
// Preparation Data
// ============================================================================

/// CPython: class _MainProcess
pub const MainProcess = struct {
    name: []const u8 = "MainProcess",
    authkey: ?[]const u8 = null,
};

/// CPython: def get_preparation_data(name)
/// Return data needed to spawn a child process
pub fn get_preparation_data(allocator: std.mem.Allocator, name: []const u8) !PreparationData {
    return PreparationData{
        .name = try allocator.dupe(u8, name),
        .sys_path = &[_][]const u8{},
        .sys_argv = &[_][]const u8{},
        .orig_dir = try std.posix.getcwd(&[_]u8{0} ** std.fs.max_path_bytes),
        .start_method = "spawn",
    };
}

pub const PreparationData = struct {
    name: []const u8,
    sys_path: []const []const u8,
    sys_argv: []const []const u8,
    orig_dir: []const u8,
    start_method: []const u8,
};

// ============================================================================
// Command Line
// ============================================================================

/// CPython: def get_command_line(**kwds)
/// Build command line for spawning a child process
pub fn get_command_line(allocator: std.mem.Allocator) ![]const u8 {
    // Return command to execute child process
    const exe = get_executable();
    return try std.fmt.allocPrint(allocator, "{s} -c \"from multiprocessing.spawn import spawn_main; spawn_main()\"", .{exe});
}

// ============================================================================
// Entry Points
// ============================================================================

/// CPython: def _main(fd, parent_sentinel)
/// Entry point for child process
pub fn _main(fd: std.posix.fd_t, parent_sentinel: std.posix.fd_t) !void {
    _ = parent_sentinel;

    // Read preparation data from fd
    var buf: [4096]u8 = undefined;
    const n = try std.posix.read(fd, &buf);
    if (n == 0) return;

    // Process and execute
    // In practice, this would deserialize and run the target
}

/// CPython: def spawn_main(pipe_handle, parent_pid=None, tracker_fd=None)
pub fn spawn_main() !void {
    // Called when child process starts
    // Would read from pipe and execute target function
}

// ============================================================================
// Freeze Support
// ============================================================================

/// CPython: def freeze_support()
/// Required for Windows frozen executables
pub fn freeze_support() void {
    if (builtin.os.tag != .windows) {
        return;
    }

    // On Windows, check if we're a frozen executable being spawned
    // and handle accordingly
}

// ============================================================================
// Validation
// ============================================================================

/// CPython: def _check_not_importing_main()
pub fn check_not_importing_main() void {
    // In AOT compilation, this check is not needed
}

/// CPython: def import_main_path(main_path)
pub fn import_main_path(main_path: []const u8) void {
    _ = main_path;
    // No-op in AOT
}

// ============================================================================
// Old API Compatibility
// ============================================================================

/// CPython: old_main_modules (deprecated)
pub var old_main_modules: ?*anyopaque = null;

// ============================================================================
// Tests
// ============================================================================

test "get_executable" {
    const exe = get_executable();
    try std.testing.expect(exe.len > 0);
}

test "set_executable" {
    const original = get_executable();
    set_executable("/custom/path");
    try std.testing.expectEqualStrings("/custom/path", get_executable());
    set_executable(original);
}

test "freeze_support" {
    // Should be a no-op on non-Windows
    freeze_support();
}
