//! multiprocessing.popen_spawn_win32 - Spawn-based process spawning (Windows)
//! Reference: cpython/Lib/multiprocessing/popen_spawn_win32.py
//!
//! CPython __all__: ['Popen']
//!
//! Implements process spawning on Windows using CreateProcess.

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Constants
// ============================================================================

/// CPython: TERMINATE = 0x10000
pub const TERMINATE: u32 = 0x10000;

/// CPython: WINEXE = sys.platform == 'win32' and getattr(sys, 'frozen', False)
pub const WINEXE: bool = builtin.os.tag == .windows;

/// CPython: WINSERVICE = sys.executable.lower().endswith("pythonservice.exe")
pub const WINSERVICE: bool = false;

// ============================================================================
// Popen - Spawn-based process spawner (Windows)
// ============================================================================

/// CPython: class Popen
/// Process spawner using CreateProcess on Windows
pub const Popen = struct {
    const Self = @This();

    pid: ?i32,
    returncode: ?i32,
    handle: ?std.os.windows.HANDLE,
    sentinel: ?std.os.windows.HANDLE,

    pub fn init() Self {
        return .{
            .pid = null,
            .returncode = null,
            .handle = null,
            .sentinel = null,
        };
    }

    pub fn deinit(self: *Self) void {
        if (builtin.os.tag == .windows) {
            if (self.handle) |h| {
                std.os.windows.CloseHandle(h);
            }
            if (self.sentinel) |s| {
                std.os.windows.CloseHandle(s);
            }
        }
    }

    /// CPython: def __call__(self, process_obj)
    pub fn call(self: *Self, argv: []const []const u8) !void {
        if (builtin.os.tag != .windows) {
            return error.WindowsOnly;
        }

        // Use ChildProcess for spawning on Windows
        var child = std.process.Child.init(argv, std.heap.page_allocator);
        try child.spawn();

        self.pid = @intCast(child.id);
        // On Windows, child.id is the process handle
    }

    /// CPython: def duplicate_for_child(self, handle)
    pub fn duplicate_for_child(_: *Self, handle: std.os.windows.HANDLE) !std.os.windows.HANDLE {
        if (builtin.os.tag != .windows) {
            return error.WindowsOnly;
        }
        // Duplicate handle for child process
        var new_handle: std.os.windows.HANDLE = undefined;
        const current_process = std.os.windows.kernel32.GetCurrentProcess();
        const result = std.os.windows.kernel32.DuplicateHandle(
            current_process,
            handle,
            current_process,
            &new_handle,
            0,
            1, // bInheritHandle = TRUE
            2, // DUPLICATE_SAME_ACCESS
        );
        if (result == 0) {
            return error.DuplicateHandleFailed;
        }
        return new_handle;
    }

    /// CPython: def poll(self, flag=os.WNOHANG)
    pub fn poll(self: *Self) ?i32 {
        if (self.returncode != null) {
            return self.returncode;
        }

        if (builtin.os.tag == .windows) {
            if (self.handle) |h| {
                var exit_code: u32 = undefined;
                if (std.os.windows.kernel32.GetExitCodeProcess(h, &exit_code) != 0) {
                    if (exit_code != 259) { // STILL_ACTIVE
                        self.returncode = @intCast(exit_code);
                        return self.returncode;
                    }
                }
            }
        }

        return null;
    }

    /// CPython: def wait(self, timeout=None)
    pub fn wait(self: *Self, timeout: ?f64) !i32 {
        if (self.returncode) |rc| {
            return rc;
        }

        if (builtin.os.tag == .windows) {
            if (self.handle) |h| {
                const timeout_ms: u32 = if (timeout) |t|
                    @intFromFloat(t * 1000)
                else
                    std.os.windows.INFINITE;

                _ = std.os.windows.kernel32.WaitForSingleObject(h, timeout_ms);

                var exit_code: u32 = undefined;
                if (std.os.windows.kernel32.GetExitCodeProcess(h, &exit_code) != 0) {
                    self.returncode = @intCast(exit_code);
                    return self.returncode.?;
                }
            }
        }

        return error.NoProcess;
    }

    /// CPython: def terminate(self)
    pub fn terminate(self: *Self) !void {
        if (builtin.os.tag == .windows) {
            if (self.handle) |h| {
                _ = std.os.windows.kernel32.TerminateProcess(h, 1);
            }
        }
    }

    /// CPython: def kill(self) - same as terminate on Windows
    pub fn kill(self: *Self) !void {
        try self.terminate();
    }
};

// ============================================================================
// Helper Functions
// ============================================================================

/// CPython: def get_command_line(**kwds)
pub fn get_command_line(prog: []const u8, args: []const []const u8) ![]const u8 {
    _ = prog;
    _ = args;
    // Build Windows command line string
    // This would involve proper quoting for Windows
    return "";
}

/// CPython: def get_preparation_data(name)
pub fn get_preparation_data(name: []const u8) []const u8 {
    return name;
}

// ============================================================================
// Tests
// ============================================================================

test "Popen init" {
    var p = Popen.init();
    defer p.deinit();

    try std.testing.expect(p.pid == null);
    try std.testing.expect(p.returncode == null);
}
