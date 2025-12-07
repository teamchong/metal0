//! Python 'msvcrt' module - Microsoft Visual C Runtime routines
//!
//! Useful routines from the MS VC runtime - console I/O, file locking,
//! and memory mapped files.
//!
//! Mirrors: CPython Modules/msvcrtmodule.c

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Platform Detection
// ============================================================================

pub const is_windows = builtin.os.tag == .windows;
const windows = if (is_windows) std.os.windows else undefined;

// ============================================================================
// Error Types
// ============================================================================

pub const MsvcrtError = error{
    UnsupportedPlatform,
    IoError,
    InvalidParameter,
    LockingFailed,
    OutOfMemory,
};

// ============================================================================
// Types
// ============================================================================

pub const DWORD = u32;
pub const HANDLE = if (is_windows) windows.HANDLE else *anyopaque;

// ============================================================================
// Constants - Locking
// ============================================================================

pub const LK_NBLCK: i32 = 1; // Non-blocking lock
pub const LK_LOCK: i32 = 2; // Blocking lock
pub const LK_NBRLCK: i32 = 3; // Non-blocking read lock
pub const LK_RLCK: i32 = 4; // Read lock
pub const LK_UNLCK: i32 = 0; // Unlock

// ============================================================================
// Constants - File Open Modes
// ============================================================================

pub const O_TEXT: i32 = 0x4000;
pub const O_BINARY: i32 = 0x8000;
pub const O_RAW: i32 = O_BINARY;
pub const O_WTEXT: i32 = 0x10000;
pub const O_U16TEXT: i32 = 0x20000;
pub const O_U8TEXT: i32 = 0x40000;

// ============================================================================
// External CRT Functions
// ============================================================================

const msvcrt = if (is_windows) struct {
    // Console functions
    extern "msvcrt" fn _getch() callconv(.C) c_int;
    extern "msvcrt" fn _getche() callconv(.C) c_int;
    extern "msvcrt" fn _getwch() callconv(.C) c_int;
    extern "msvcrt" fn _getwche() callconv(.C) c_int;
    extern "msvcrt" fn _putch(c: c_int) callconv(.C) c_int;
    extern "msvcrt" fn _putwch(c: c_int) callconv(.C) c_int;
    extern "msvcrt" fn _ungetch(c: c_int) callconv(.C) c_int;
    extern "msvcrt" fn _ungetwch(c: c_int) callconv(.C) c_int;
    extern "msvcrt" fn _kbhit() callconv(.C) c_int;

    // File locking
    extern "msvcrt" fn _locking(fd: c_int, mode: c_int, nbytes: c_long) callconv(.C) c_int;

    // File mode
    extern "msvcrt" fn _setmode(fd: c_int, mode: c_int) callconv(.C) c_int;

    // Handle/fd conversion
    extern "msvcrt" fn _open_osfhandle(osfhandle: isize, flags: c_int) callconv(.C) c_int;
    extern "msvcrt" fn _get_osfhandle(fd: c_int) callconv(.C) isize;

    // CRT heap info
    extern "msvcrt" fn _heapmin() callconv(.C) c_int;

    // Error handling
    extern "msvcrt" fn _set_error_mode(mode: c_int) callconv(.C) c_int;
} else undefined;

// ============================================================================
// Console I/O Functions
// ============================================================================

/// Read a keypress without echoing
pub fn getch() MsvcrtError!u8 {
    if (!is_windows) return error.UnsupportedPlatform;

    const ch = msvcrt._getch();
    if (ch < 0) return error.IoError;
    return @intCast(ch);
}

/// Read a keypress with echoing
pub fn getche() MsvcrtError!u8 {
    if (!is_windows) return error.UnsupportedPlatform;

    const ch = msvcrt._getche();
    if (ch < 0) return error.IoError;
    return @intCast(ch);
}

/// Read a wide character keypress without echoing
pub fn getwch() MsvcrtError!u16 {
    if (!is_windows) return error.UnsupportedPlatform;

    const ch = msvcrt._getwch();
    if (ch < 0) return error.IoError;
    return @intCast(ch);
}

/// Read a wide character keypress with echoing
pub fn getwche() MsvcrtError!u16 {
    if (!is_windows) return error.UnsupportedPlatform;

    const ch = msvcrt._getwche();
    if (ch < 0) return error.IoError;
    return @intCast(ch);
}

/// Write a character to console
pub fn putch(ch: u8) MsvcrtError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    if (msvcrt._putch(ch) < 0) {
        return error.IoError;
    }
}

/// Write a wide character to console
pub fn putwch(ch: u16) MsvcrtError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    if (msvcrt._putwch(ch) < 0) {
        return error.IoError;
    }
}

/// Push back a character to the console buffer
pub fn ungetch(ch: u8) MsvcrtError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    if (msvcrt._ungetch(ch) < 0) {
        return error.IoError;
    }
}

/// Push back a wide character to the console buffer
pub fn ungetwch(ch: u16) MsvcrtError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    if (msvcrt._ungetwch(ch) < 0) {
        return error.IoError;
    }
}

/// Check if a keypress is waiting
pub fn kbhit() bool {
    if (!is_windows) return false;
    return msvcrt._kbhit() != 0;
}

// ============================================================================
// File Locking Functions
// ============================================================================

/// Lock or unlock a portion of a file
pub fn locking(fd: i32, mode: i32, nbytes: i64) MsvcrtError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    if (msvcrt._locking(fd, mode, @intCast(nbytes)) != 0) {
        return error.LockingFailed;
    }
}

/// Lock a file (convenience wrapper)
pub fn lockFile(fd: i32, nbytes: i64, blocking: bool) MsvcrtError!void {
    const mode = if (blocking) LK_LOCK else LK_NBLCK;
    return locking(fd, mode, nbytes);
}

/// Unlock a file (convenience wrapper)
pub fn unlockFile(fd: i32, nbytes: i64) MsvcrtError!void {
    return locking(fd, LK_UNLCK, nbytes);
}

// ============================================================================
// File Mode Functions
// ============================================================================

/// Set file translation mode
pub fn setmode(fd: i32, mode: i32) MsvcrtError!i32 {
    if (!is_windows) return error.UnsupportedPlatform;

    const old_mode = msvcrt._setmode(fd, mode);
    if (old_mode == -1) {
        return error.InvalidParameter;
    }
    return old_mode;
}

/// Set file to text mode
pub fn setTextMode(fd: i32) MsvcrtError!i32 {
    return setmode(fd, O_TEXT);
}

/// Set file to binary mode
pub fn setBinaryMode(fd: i32) MsvcrtError!i32 {
    return setmode(fd, O_BINARY);
}

// ============================================================================
// Handle/FD Conversion Functions
// ============================================================================

/// Get OS file handle from C file descriptor
pub fn get_osfhandle(fd: i32) MsvcrtError!HANDLE {
    if (!is_windows) return error.UnsupportedPlatform;

    const handle = msvcrt._get_osfhandle(fd);
    if (handle == -1) {
        return error.InvalidParameter;
    }
    return @ptrFromInt(@as(usize, @intCast(handle)));
}

/// Create C file descriptor from OS file handle
pub fn open_osfhandle(handle: HANDLE, flags: i32) MsvcrtError!i32 {
    if (!is_windows) return error.UnsupportedPlatform;

    const fd = msvcrt._open_osfhandle(@intCast(@intFromPtr(handle)), flags);
    if (fd == -1) {
        return error.InvalidParameter;
    }
    return fd;
}

// ============================================================================
// Heap Functions
// ============================================================================

/// Minimize CRT heap
pub fn heapmin() MsvcrtError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    if (msvcrt._heapmin() != 0) {
        return error.OutOfMemory;
    }
}

// ============================================================================
// Error Mode
// ============================================================================

pub const REPORT_ERRMODE: i32 = 0;
pub const OUT_TO_DEFAULT: i32 = 0;
pub const OUT_TO_STDERR: i32 = 1;
pub const OUT_TO_MSGBOX: i32 = 2;

/// Set CRT error mode
pub fn set_error_mode(mode: i32) MsvcrtError!i32 {
    if (!is_windows) return error.UnsupportedPlatform;
    return msvcrt._set_error_mode(mode);
}

// ============================================================================
// CRT Version Info
// ============================================================================

pub const CRT_ASSEMBLY_VERSION = "14.0";

/// Get CRT version string
pub fn getCrtVersion() []const u8 {
    return CRT_ASSEMBLY_VERSION;
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

pub fn init() void {
    if (initialized) return;
    initialized = true;
}

pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "locking constants" {
    try std.testing.expectEqual(@as(i32, 0), LK_UNLCK);
    try std.testing.expectEqual(@as(i32, 1), LK_NBLCK);
    try std.testing.expectEqual(@as(i32, 2), LK_LOCK);
}

test "file mode constants" {
    try std.testing.expect(O_TEXT != O_BINARY);
    try std.testing.expectEqual(O_BINARY, O_RAW);
}

test "error mode constants" {
    try std.testing.expectEqual(@as(i32, 0), REPORT_ERRMODE);
    try std.testing.expectEqual(@as(i32, 1), OUT_TO_STDERR);
}

test "kbhit on Windows" {
    if (is_windows) {
        // Just verify it doesn't crash
        _ = kbhit();
    }
}

test "getCrtVersion" {
    const version = getCrtVersion();
    try std.testing.expect(version.len > 0);
}
