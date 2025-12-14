//! Cross-platform process utilities
//!
//! Handles differences between Windows and POSIX process management:
//! - Windows: std.process.Child.Id is HANDLE (*anyopaque)
//! - POSIX: std.process.Child.Id is integer (i32/pid_t)
//!
//! CPython solves this by storing BOTH the HANDLE and numeric PID on Windows.
//! Windows CreateProcess returns: (hProcess: HANDLE, dwProcessId: DWORD)
//! We follow the same pattern: use getNumericPid() to get a serializable integer.
//!
//! Usage:
//!   const process = @import("utils/process_fmt.zig");
//!
//!   // Get numeric PID (works on all platforms, serializable)
//!   const pid = process.getNumericPid(child.id);
//!   std.debug.print("pid: {d}\n", .{pid});
//!
//!   // Killing processes by ID (cross-platform)
//!   process.killById(child_id);
//!
//!   // Killing with signal (POSIX) or terminate (Windows)
//!   process.killByIdWithSignal(child_id, 15); // SIGTERM on POSIX

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Windows API declarations (not in Zig stdlib)
// ============================================================================

/// Windows kernel32 functions not exposed in std.os.windows.kernel32
/// Declared here for cross-platform compatibility
const windows_ext = if (builtin.os.tag == .windows) struct {
    /// GetProcessId - retrieves the process identifier of the specified process
    /// https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getprocessid
    pub extern "kernel32" fn GetProcessId(Process: std.os.windows.HANDLE) callconv(.winapi) std.os.windows.DWORD;
} else struct {};

// ============================================================================
// Numeric PID extraction (CPython-style)
// ============================================================================

/// Get numeric process ID from Child.Id (cross-platform)
/// On Windows: calls GetProcessId(handle) to get DWORD
/// On POSIX: returns the pid_t directly (already an integer)
///
/// This follows CPython's approach where subprocess.Popen stores both
/// self._handle (HANDLE) and self.pid (integer) separately.
pub fn getNumericPid(child_id: std.process.Child.Id) u32 {
    if (comptime builtin.os.tag == .windows) {
        // Windows: Child.Id is HANDLE, call GetProcessId to get numeric PID
        const handle: std.os.windows.HANDLE = @ptrCast(child_id);
        return windows_ext.GetProcessId(handle);
    } else {
        // POSIX: Child.Id is already pid_t (i32), cast to u32 for consistency
        return @intCast(child_id);
    }
}

// ============================================================================
// Format specifiers for printing process IDs (legacy)
// ============================================================================

/// Format specifier for process IDs (raw Child.Id)
/// Prefer getNumericPid() + "{d}" for new code
pub const PID_FMT = if (builtin.os.tag == .windows) "{any}" else "{d}";

/// Format specifier for optional process IDs (raw Child.Id)
/// Prefer getNumericPid() + "{d}" for new code
pub const PID_FMT_OPT = if (builtin.os.tag == .windows) "{?any}" else "{?d}";

// ============================================================================
// Cross-platform process killing
// ============================================================================

/// Kill a process by its ID (cross-platform)
/// On Windows: uses TerminateProcess
/// On POSIX: uses kill with SIGKILL (9)
pub fn killById(pid: std.process.Child.Id) void {
    killByIdWithSignal(pid, 9); // SIGKILL
}

/// Kill a process by its ID with a specific signal
/// On Windows: signal is ignored, always uses TerminateProcess
/// On POSIX: uses kill with the specified signal (e.g., 15 for SIGTERM, 9 for SIGKILL)
pub fn killByIdWithSignal(pid: std.process.Child.Id, signal: u8) void {
    if (comptime builtin.os.tag == .windows) {
        // Windows: use TerminateProcess
        // pid is a HANDLE (*anyopaque) on Windows
        const handle: std.os.windows.HANDLE = @ptrCast(pid);
        _ = std.os.windows.kernel32.TerminateProcess(handle, 1);
    } else {
        // POSIX: use kill syscall
        _ = std.posix.kill(pid, signal) catch {};
    }
}

/// Terminate a process gracefully (SIGTERM on POSIX, TerminateProcess on Windows)
pub fn terminateById(pid: std.process.Child.Id) void {
    killByIdWithSignal(pid, 15); // SIGTERM
}

// ============================================================================
// Platform detection helpers
// ============================================================================

/// Returns true if running on Windows
pub const is_windows = builtin.os.tag == .windows;

/// Returns true if running on a POSIX system (Linux, macOS, BSD, etc.)
pub const is_posix = builtin.os.tag != .windows;

// ============================================================================
// Daemon/background process utilities
// ============================================================================

/// Check if daemon features are supported on this platform
/// Daemon features require ability to:
/// - Store PID in a file (not possible with Windows HANDLEs)
/// - Send signals to processes (POSIX only)
pub const daemon_supported = is_posix;

/// Get the current process ID as a string-serializable integer
/// On Windows: returns 0 (daemon not supported)
/// On POSIX: returns the actual PID
pub fn getCurrentPid() i32 {
    if (comptime builtin.os.tag == .windows) {
        return 0; // Daemon not supported on Windows
    } else if (comptime builtin.os.tag == .linux) {
        return std.os.linux.getpid();
    } else {
        // macOS, FreeBSD, etc.
        return std.c.getpid();
    }
}
