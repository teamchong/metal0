/// CPython OS Interface
///
/// Implements OS-level utilities for CPython compatibility.

const std = @import("std");
const cpython = @import("cpython_object.zig");

// External dependencies
extern fn Py_INCREF(*cpython.PyObject) callconv(.c) void;
extern fn Py_DECREF(*cpython.PyObject) callconv(.c) void;

/// Safe snprintf implementation
/// Returns number of characters written (excluding null terminator)
export fn PyOS_snprintf(str: [*]u8, size: usize, format: [*:0]const u8, ...) callconv(.c) c_int {
    var va = @cVaStart();
    defer @cVaEnd(&va);

    return std.c.vsnprintf(str, size, format, va);
}

/// Safe vsnprintf with va_list
/// Returns number of characters written (excluding null terminator)
export fn PyOS_vsnprintf(str: [*]u8, size: usize, format: [*:0]const u8, va: *std.builtin.VaList) callconv(.c) c_int {
    return std.c.vsnprintf(str, size, format, va.*);
}

/// Case-insensitive string comparison
/// Returns 0 if equal, <0 if s1 < s2, >0 if s1 > s2
export fn PyOS_stricmp(s1: [*:0]const u8, s2: [*:0]const u8) callconv(.c) c_int {
    var i: usize = 0;
    while (true) : (i += 1) {
        const c1 = std.ascii.toLower(s1[i]);
        const c2 = std.ascii.toLower(s2[i]);

        if (c1 != c2) return @as(c_int, @intCast(c1)) - @as(c_int, @intCast(c2));
        if (c1 == 0) return 0; // Both strings ended
    }
}

/// Case-insensitive string comparison (first n characters)
/// Returns 0 if equal, <0 if s1 < s2, >0 if s1 > s2
export fn PyOS_strnicmp(s1: [*:0]const u8, s2: [*:0]const u8, n: usize) callconv(.c) c_int {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const c1 = std.ascii.toLower(s1[i]);
        const c2 = std.ascii.toLower(s2[i]);

        if (c1 != c2) return @as(c_int, @intCast(c1)) - @as(c_int, @intCast(c2));
        if (c1 == 0) return 0; // Both strings ended
    }
    return 0; // First n characters are equal
}

/// Convert path-like object to filesystem path string
/// Returns new reference to path string or null on error
export fn PyOS_FSPath(path: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(path);

    // Check if object has __fspath__ method
    // For now, just assume strings are valid paths
    Py_INCREF(path);
    return path;
}

/// Callback to execute before fork()
/// Used to prepare for process forking
export fn PyOS_BeforeFork() callconv(.c) void {
    // TODO: Acquire all locks, prepare runtime state
    // This is called before fork() to ensure clean state
}

/// Callback to execute after fork() in parent process
/// Used to restore parent state after fork
export fn PyOS_AfterFork_Parent() callconv(.c) void {
    // TODO: Release locks in parent process
    // This is called in parent after fork()
}

/// Callback to execute after fork() in child process
/// Used to reinitialize child state after fork
export fn PyOS_AfterFork_Child() callconv(.c) void {
    // TODO: Reinitialize locks, thread state in child
    // This is called in child after fork()
}

/// Compatibility wrapper for AfterFork
/// Calls AfterFork_Parent() (legacy behavior)
export fn PyOS_AfterFork() callconv(.c) void {
    PyOS_AfterFork_Parent();
}

/// Initialize random number generator
/// Returns 0 on success, -1 on error
export fn _PyOS_URandom(buffer: [*]u8, size: isize) callconv(.c) c_int {
    _ = buffer;
    _ = size;
    // TODO: Fill buffer with cryptographically secure random bytes
    // Use /dev/urandom on Unix, CryptGenRandom on Windows
    return 0;
}

/// Get interrupt status
/// Returns 1 if interrupt occurred (Ctrl+C), 0 otherwise
export fn PyOS_InterruptOccurred() callconv(.c) c_int {
    // TODO: Check if SIGINT was received
    return 0; // No interrupt
}

/// Initialize signal handling
/// Sets up handlers for SIGINT, SIGTERM, etc.
export fn PyOS_InitInterrupts() callconv(.c) void {
    // TODO: Set up signal handlers
    // Register handler for SIGINT to set interrupt flag
}

/// Finalize signal handling
/// Restores original signal handlers
export fn PyOS_FiniInterrupts() callconv(.c) void {
    // TODO: Restore original signal handlers
}

/// Read line from stdin with optional prompt
/// Returns allocated string or null on EOF/error
export fn PyOS_Readline(stdin_: *std.c.FILE, stdout_: *std.c.FILE, prompt: [*:0]const u8) callconv(.c) [*:0]u8 {
    _ = stdin_;

    // Print prompt to stdout
    _ = std.c.fprintf(stdout_, "%s", prompt);
    _ = std.c.fflush(stdout_);

    // TODO: Read line from stdin
    // For now, return empty string
    const empty = std.c.malloc(1) orelse return @ptrFromInt(0);
    const str: [*]u8 = @ptrCast(empty);
    str[0] = 0;
    return @ptrCast(str);
}
