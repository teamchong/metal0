//! CPython source: PC/_testconsole.c
//!
//! Internal test module for testing Windows console I/O functionality.
//! Used by CPython's test suite to verify console behavior.
//!
//! Mirrors: CPython Modules/_testconsole.c

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

pub const TestConsoleError = error{
    UnsupportedPlatform,
    NotAConsole,
    InvalidParameter,
    ReadFailed,
    WriteFailed,
};

// ============================================================================
// Types
// ============================================================================

pub const HANDLE = if (is_windows) windows.HANDLE else *anyopaque;
pub const DWORD = u32;
pub const BOOL = i32;

pub const INVALID_HANDLE_VALUE: HANDLE = if (is_windows)
    windows.INVALID_HANDLE_VALUE
else
    @ptrFromInt(~@as(usize, 0));

// ============================================================================
// Constants
// ============================================================================

pub const STD_INPUT_HANDLE: DWORD = @bitCast(@as(i32, -10));
pub const STD_OUTPUT_HANDLE: DWORD = @bitCast(@as(i32, -11));
pub const STD_ERROR_HANDLE: DWORD = @bitCast(@as(i32, -12));

// Console modes
pub const ENABLE_ECHO_INPUT: DWORD = 0x0004;
pub const ENABLE_LINE_INPUT: DWORD = 0x0002;
pub const ENABLE_PROCESSED_INPUT: DWORD = 0x0001;
pub const ENABLE_WINDOW_INPUT: DWORD = 0x0008;
pub const ENABLE_MOUSE_INPUT: DWORD = 0x0010;
pub const ENABLE_INSERT_MODE: DWORD = 0x0020;
pub const ENABLE_QUICK_EDIT_MODE: DWORD = 0x0040;
pub const ENABLE_VIRTUAL_TERMINAL_INPUT: DWORD = 0x0200;

pub const ENABLE_PROCESSED_OUTPUT: DWORD = 0x0001;
pub const ENABLE_WRAP_AT_EOL_OUTPUT: DWORD = 0x0002;
pub const ENABLE_VIRTUAL_TERMINAL_PROCESSING: DWORD = 0x0004;
pub const DISABLE_NEWLINE_AUTO_RETURN: DWORD = 0x0008;
pub const ENABLE_LVB_GRID_WORLDWIDE: DWORD = 0x0010;

// ============================================================================
// Console Buffer Info
// ============================================================================

pub const COORD = extern struct {
    X: i16,
    Y: i16,
};

pub const SMALL_RECT = extern struct {
    Left: i16,
    Top: i16,
    Right: i16,
    Bottom: i16,
};

pub const CONSOLE_SCREEN_BUFFER_INFO = extern struct {
    dwSize: COORD,
    dwCursorPosition: COORD,
    wAttributes: u16,
    srWindow: SMALL_RECT,
    dwMaximumWindowSize: COORD,
};

// ============================================================================
// External Windows Functions
// ============================================================================

const kernel32 = if (is_windows) struct {
    extern "kernel32" fn GetStdHandle(nStdHandle: DWORD) callconv(windows.WINAPI) ?HANDLE;
    extern "kernel32" fn GetConsoleMode(hConsoleHandle: HANDLE, lpMode: *DWORD) callconv(windows.WINAPI) BOOL;
    extern "kernel32" fn SetConsoleMode(hConsoleHandle: HANDLE, dwMode: DWORD) callconv(windows.WINAPI) BOOL;
    extern "kernel32" fn GetConsoleScreenBufferInfo(hConsoleOutput: HANDLE, lpConsoleScreenBufferInfo: *CONSOLE_SCREEN_BUFFER_INFO) callconv(windows.WINAPI) BOOL;
    extern "kernel32" fn WriteConsoleW(hConsoleOutput: HANDLE, lpBuffer: [*]const u16, nNumberOfCharsToWrite: DWORD, lpNumberOfCharsWritten: ?*DWORD, lpReserved: ?*anyopaque) callconv(windows.WINAPI) BOOL;
    extern "kernel32" fn ReadConsoleW(hConsoleInput: HANDLE, lpBuffer: [*]u16, nNumberOfCharsToRead: DWORD, lpNumberOfCharsRead: *DWORD, pInputControl: ?*anyopaque) callconv(windows.WINAPI) BOOL;
    extern "kernel32" fn GetConsoleCP() callconv(windows.WINAPI) UINT;
    extern "kernel32" fn GetConsoleOutputCP() callconv(windows.WINAPI) UINT;
    extern "kernel32" fn SetConsoleCP(wCodePageID: UINT) callconv(windows.WINAPI) BOOL;
    extern "kernel32" fn SetConsoleOutputCP(wCodePageID: UINT) callconv(windows.WINAPI) BOOL;
} else undefined;

pub const UINT = u32;

// ============================================================================
// Console Functions
// ============================================================================

/// Get a standard console handle
pub fn getStdHandle(handle_type: DWORD) TestConsoleError!HANDLE {
    if (!is_windows) return error.UnsupportedPlatform;

    const handle = kernel32.GetStdHandle(handle_type);
    if (handle == null or handle == INVALID_HANDLE_VALUE) {
        return error.NotAConsole;
    }
    return handle.?;
}

/// Check if handle is a console
pub fn isConsole(handle: HANDLE) bool {
    if (!is_windows) return false;

    var mode: DWORD = 0;
    return kernel32.GetConsoleMode(handle, &mode) != 0;
}

/// Get console mode
pub fn getConsoleMode(handle: HANDLE) TestConsoleError!DWORD {
    if (!is_windows) return error.UnsupportedPlatform;

    var mode: DWORD = 0;
    if (kernel32.GetConsoleMode(handle, &mode) == 0) {
        return error.NotAConsole;
    }
    return mode;
}

/// Set console mode
pub fn setConsoleMode(handle: HANDLE, mode: DWORD) TestConsoleError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    if (kernel32.SetConsoleMode(handle, mode) == 0) {
        return error.NotAConsole;
    }
}

/// Get console screen buffer info
pub fn getConsoleScreenBufferInfo(handle: HANDLE) TestConsoleError!CONSOLE_SCREEN_BUFFER_INFO {
    if (!is_windows) return error.UnsupportedPlatform;

    var info: CONSOLE_SCREEN_BUFFER_INFO = undefined;
    if (kernel32.GetConsoleScreenBufferInfo(handle, &info) == 0) {
        return error.NotAConsole;
    }
    return info;
}

/// Write to console (wide characters)
pub fn writeConsole(handle: HANDLE, text: []const u16) TestConsoleError!DWORD {
    if (!is_windows) return error.UnsupportedPlatform;

    var written: DWORD = 0;
    if (kernel32.WriteConsoleW(handle, text.ptr, @intCast(text.len), &written, null) == 0) {
        return error.WriteFailed;
    }
    return written;
}

/// Write UTF-8 text to console
pub fn writeConsoleUtf8(handle: HANDLE, text: []const u8) TestConsoleError!DWORD {
    if (!is_windows) return error.UnsupportedPlatform;

    var buf: [4096]u16 = undefined;
    const len = std.unicode.utf8ToUtf16Le(&buf, text) catch return error.InvalidParameter;
    return writeConsole(handle, buf[0..len]);
}

/// Read from console (wide characters)
pub fn readConsole(handle: HANDLE, buffer: []u16) TestConsoleError!DWORD {
    if (!is_windows) return error.UnsupportedPlatform;

    var read: DWORD = 0;
    if (kernel32.ReadConsoleW(handle, buffer.ptr, @intCast(buffer.len), &read, null) == 0) {
        return error.ReadFailed;
    }
    return read;
}

/// Get input code page
pub fn getConsoleCP() UINT {
    if (!is_windows) return 0;
    return kernel32.GetConsoleCP();
}

/// Get output code page
pub fn getConsoleOutputCP() UINT {
    if (!is_windows) return 0;
    return kernel32.GetConsoleOutputCP();
}

/// Set input code page
pub fn setConsoleCP(code_page: UINT) TestConsoleError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    if (kernel32.SetConsoleCP(code_page) == 0) {
        return error.InvalidParameter;
    }
}

/// Set output code page
pub fn setConsoleOutputCP(code_page: UINT) TestConsoleError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    if (kernel32.SetConsoleOutputCP(code_page) == 0) {
        return error.InvalidParameter;
    }
}

// ============================================================================
// Code Page Constants
// ============================================================================

pub const CP_ACP: UINT = 0;
pub const CP_OEMCP: UINT = 1;
pub const CP_UTF7: UINT = 65000;
pub const CP_UTF8: UINT = 65001;

// ============================================================================
// Test Helpers
// ============================================================================

/// Test if stdout is a console
pub fn stdoutIsConsole() bool {
    if (!is_windows) return false;
    const handle = getStdHandle(STD_OUTPUT_HANDLE) catch return false;
    return isConsole(handle);
}

/// Test if stdin is a console
pub fn stdinIsConsole() bool {
    if (!is_windows) return false;
    const handle = getStdHandle(STD_INPUT_HANDLE) catch return false;
    return isConsole(handle);
}

/// Get console window size
pub fn getConsoleSize() TestConsoleError!struct { width: u16, height: u16 } {
    if (!is_windows) return error.UnsupportedPlatform;

    const handle = try getStdHandle(STD_OUTPUT_HANDLE);
    const info = try getConsoleScreenBufferInfo(handle);

    return .{
        .width = @intCast(info.srWindow.Right - info.srWindow.Left + 1),
        .height = @intCast(info.srWindow.Bottom - info.srWindow.Top + 1),
    };
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

test "console mode constants" {
    try std.testing.expect(ENABLE_ECHO_INPUT > 0);
    try std.testing.expect(ENABLE_LINE_INPUT > 0);
    try std.testing.expect(ENABLE_PROCESSED_OUTPUT > 0);
}

test "standard handle constants" {
    try std.testing.expect(STD_INPUT_HANDLE != 0);
    try std.testing.expect(STD_OUTPUT_HANDLE != 0);
    try std.testing.expect(STD_ERROR_HANDLE != 0);
}

test "code page constants" {
    try std.testing.expectEqual(@as(UINT, 0), CP_ACP);
    try std.testing.expectEqual(@as(UINT, 65001), CP_UTF8);
}

test "COORD struct" {
    const coord = COORD{ .X = 10, .Y = 20 };
    try std.testing.expectEqual(@as(i16, 10), coord.X);
    try std.testing.expectEqual(@as(i16, 20), coord.Y);
}

test "isConsole returns false on non-Windows" {
    if (!is_windows) {
        try std.testing.expect(!stdoutIsConsole());
        try std.testing.expect(!stdinIsConsole());
    }
}
