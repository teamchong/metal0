//! Microsoft Visual C Runtime Library Access
//!
//! Platform-specific module - only available on Windows.
//! On non-Windows platforms, this module compiles but raises ModuleNotFoundError at runtime.
//!
//! CPython source: PC/msvcrtmodule.c
//! CPython equivalent: msvcrt (Windows-only C extension)

const std = @import("std");
const builtin = @import("builtin");

// Compile-time platform check
const is_windows = builtin.os.tag == .windows;

/// Module initialization error
pub const ModuleError = error{
    PlatformNotSupported,
};

/// Check if this module is available on current platform
pub fn checkPlatform() ModuleError!void {
    if (!is_windows) {
        return error.PlatformNotSupported;
    }
}

// Lock mode constants (defined for all platforms to allow compilation)
pub const LK_UNLCK: i32 = 0; // Unlock
pub const LK_LOCK: i32 = 1; // Lock (blocking)
pub const LK_NBLCK: i32 = 2; // Lock (non-blocking)
pub const LK_RLCK: i32 = 3; // Lock for reading (blocking)
pub const LK_NBRLCK: i32 = 4; // Lock for reading (non-blocking)

// File I/O mode constants
pub const O_BINARY: i32 = 0x8000;
pub const O_TEXT: i32 = 0x4000;
pub const O_NOINHERIT: i32 = 0x0080;

// Console constants
pub const SEM_FAILCRITICALERRORS: i32 = 0x0001;
pub const SEM_NOALIGNMENTFAULTEXCEPT: i32 = 0x0004;
pub const SEM_NOGPFAULTERRORBOX: i32 = 0x0002;
pub const SEM_NOOPENFILEERRORBOX: i32 = 0x8000;

/// File locking (stub)
pub fn locking(fd: i32, mode: i32, nbytes: i64) !void {
    _ = fd;
    _ = mode;
    _ = nbytes;
    try checkPlatform();
    @panic("msvcrt.locking not implemented for Windows yet");
}

/// Set binary mode (stub)
pub fn setmode(fd: i32, mode: i32) !i32 {
    _ = fd;
    _ = mode;
    try checkPlatform();
    return error.PlatformNotSupported;
}

/// Open OS file handle from C file descriptor (stub)
pub fn open_osfhandle(handle: i64, flags: i32) !i32 {
    _ = handle;
    _ = flags;
    try checkPlatform();
    return error.PlatformNotSupported;
}

/// Get OS file handle from C file descriptor (stub)
pub fn get_osfhandle(fd: i32) !i64 {
    _ = fd;
    try checkPlatform();
    return error.PlatformNotSupported;
}

/// Check if key pressed (stub)
pub fn kbhit() !bool {
    try checkPlatform();
    return false;
}

/// Get character from console without echo (stub)
pub fn getch() !u8 {
    try checkPlatform();
    return error.PlatformNotSupported;
}

/// Get wide character from console without echo (stub)
pub fn getwch() !u16 {
    try checkPlatform();
    return error.PlatformNotSupported;
}

/// Get character from console with echo (stub)
pub fn getche() !u8 {
    try checkPlatform();
    return error.PlatformNotSupported;
}

/// Get wide character from console with echo (stub)
pub fn getwche() !u16 {
    try checkPlatform();
    return error.PlatformNotSupported;
}

/// Put character to console (stub)
pub fn putch(c: u8) !void {
    _ = c;
    try checkPlatform();
}

/// Put wide character to console (stub)
pub fn putwch(c: u16) !void {
    _ = c;
    try checkPlatform();
}

/// Unget character (push back) (stub)
pub fn ungetch(c: u8) !void {
    _ = c;
    try checkPlatform();
}

/// Unget wide character (push back) (stub)
pub fn ungetwch(c: u16) !void {
    _ = c;
    try checkPlatform();
}

/// Set error mode (stub)
pub fn SetErrorMode(mode: i32) !i32 {
    _ = mode;
    try checkPlatform();
    return 0;
}

/// Heap allocation functions (stubs)
pub fn heapmin() !void {
    try checkPlatform();
}

test "msvcrt platform check" {
    if (builtin.os.tag == .windows) {
        // Should succeed on Windows
        try checkPlatform();
    } else {
        // Should fail on non-Windows
        try std.testing.expectError(error.PlatformNotSupported, checkPlatform());
    }
}
