//! ctypes.wintypes - Windows data types
//! Reference: cpython/Lib/ctypes/wintypes.py
//!
//! Provides Windows-specific data types for ctypes FFI.
//! These types match the Windows SDK headers.

const std = @import("std");
const builtin = @import("builtin");
const ctypes = @import("../ctypes.zig");

// ============================================================================
// Basic Windows Types
// ============================================================================

/// 8-bit unsigned integer
pub const BYTE = u8;

/// 16-bit unsigned integer
pub const WORD = u16;

/// 32-bit unsigned integer (platform-dependent long)
pub const DWORD = ctypes.c_ulong;

/// 8-bit character
pub const CHAR = u8;

/// Wide character (UTF-16 on Windows)
pub const WCHAR = u16;

/// Unsigned integer
pub const UINT = u32;

/// Signed integer
pub const INT = i32;

/// Double precision float
pub const DOUBLE = f64;

/// Single precision float
pub const FLOAT = f32;

/// Boolean as byte
pub const BOOLEAN = BYTE;

/// Boolean as long
pub const BOOL = ctypes.c_long;

/// Unsigned long
pub const ULONG = ctypes.c_ulong;

/// Signed long
pub const LONG = ctypes.c_long;

/// Unsigned short
pub const USHORT = u16;

/// Signed short
pub const SHORT = i16;

// ============================================================================
// Large Integers
// ============================================================================

/// 64-bit signed integer
pub const LARGE_INTEGER = i64;
pub const _LARGE_INTEGER = LARGE_INTEGER;

/// 64-bit unsigned integer
pub const ULARGE_INTEGER = u64;
pub const _ULARGE_INTEGER = ULARGE_INTEGER;

// ============================================================================
// String Pointer Types
// ============================================================================

/// Pointer to OLE string (wide)
pub const LPCOLESTR = ?[*:0]const WCHAR;
pub const LPOLESTR = ?[*:0]WCHAR;
pub const OLESTR = ?[*:0]const WCHAR;

/// Pointer to wide string (const)
pub const LPCWSTR = ?[*:0]const WCHAR;
/// Pointer to wide string
pub const LPWSTR = ?[*:0]WCHAR;

/// Pointer to ANSI string (const)
pub const LPCSTR = ?[*:0]const CHAR;
/// Pointer to ANSI string
pub const LPSTR = ?[*:0]CHAR;

/// Pointer to void (const)
pub const LPCVOID = ?*const anyopaque;
/// Pointer to void
pub const LPVOID = ?*anyopaque;

// ============================================================================
// Window Message Parameters
// ============================================================================

/// WPARAM - unsigned pointer-sized integer
pub const WPARAM = usize;

/// LPARAM - signed pointer-sized integer
pub const LPARAM = isize;

// ============================================================================
// Identifier Types
// ============================================================================

/// Atom identifier
pub const ATOM = WORD;

/// Language identifier
pub const LANGID = WORD;

/// Color reference (RGB)
pub const COLORREF = DWORD;

/// Locale group identifier
pub const LGRPID = DWORD;

/// Locale type
pub const LCTYPE = DWORD;

/// Locale identifier
pub const LCID = DWORD;

// ============================================================================
// Handle Types
// ============================================================================

/// Generic handle type
pub const HANDLE = ?*anyopaque;

/// Accelerator table handle
pub const HACCEL = HANDLE;
/// Bitmap handle
pub const HBITMAP = HANDLE;
/// Brush handle
pub const HBRUSH = HANDLE;
/// Color space handle
pub const HCOLORSPACE = HANDLE;
/// Device context handle
pub const HDC = HANDLE;
/// Desktop handle
pub const HDESK = HANDLE;
/// Deferred window position handle
pub const HDWP = HANDLE;
/// Enhanced metafile handle
pub const HENHMETAFILE = HANDLE;
/// Font handle
pub const HFONT = HANDLE;
/// GDI object handle
pub const HGDIOBJ = HANDLE;
/// Global memory handle
pub const HGLOBAL = HANDLE;
/// Hook handle
pub const HHOOK = HANDLE;
/// Icon handle
pub const HICON = HANDLE;
/// Instance handle
pub const HINSTANCE = HANDLE;
/// Registry key handle
pub const HKEY = HANDLE;
/// Keyboard layout handle
pub const HKL = HANDLE;
/// Local memory handle
pub const HLOCAL = HANDLE;
/// Menu handle
pub const HMENU = HANDLE;
/// Metafile handle
pub const HMETAFILE = HANDLE;
/// Module handle
pub const HMODULE = HANDLE;
/// Monitor handle
pub const HMONITOR = HANDLE;
/// Palette handle
pub const HPALETTE = HANDLE;
/// Pen handle
pub const HPEN = HANDLE;
/// Region handle
pub const HRGN = HANDLE;
/// Resource handle
pub const HRSRC = HANDLE;
/// String handle
pub const HSTR = HANDLE;
/// Task handle
pub const HTASK = HANDLE;
/// Window station handle
pub const HWINSTA = HANDLE;
/// Window handle
pub const HWND = HANDLE;
/// Service control manager handle
pub const SC_HANDLE = HANDLE;
/// Service status handle
pub const SERVICE_STATUS_HANDLE = HANDLE;

// ============================================================================
// Structures
// ============================================================================

/// Rectangle structure
pub const RECT = extern struct {
    left: LONG = 0,
    top: LONG = 0,
    right: LONG = 0,
    bottom: LONG = 0,
};
pub const tagRECT = RECT;
pub const _RECTL = RECT;
pub const RECTL = RECT;

/// Small rectangle (SHORT coordinates)
pub const SMALL_RECT = extern struct {
    Left: SHORT = 0,
    Top: SHORT = 0,
    Right: SHORT = 0,
    Bottom: SHORT = 0,
};
pub const _SMALL_RECT = SMALL_RECT;

/// Coordinate structure
pub const COORD = extern struct {
    X: SHORT = 0,
    Y: SHORT = 0,
};
pub const _COORD = COORD;

/// Point structure
pub const POINT = extern struct {
    x: LONG = 0,
    y: LONG = 0,
};
pub const tagPOINT = POINT;
pub const _POINTL = POINT;
pub const POINTL = POINT;

/// Size structure
pub const SIZE = extern struct {
    cx: LONG = 0,
    cy: LONG = 0,
};
pub const tagSIZE = SIZE;
pub const SIZEL = SIZE;

/// FILETIME structure
pub const FILETIME = extern struct {
    dwLowDateTime: DWORD = 0,
    dwHighDateTime: DWORD = 0,
};
pub const _FILETIME = FILETIME;

/// Window message structure
pub const MSG = extern struct {
    hWnd: HWND = null,
    message: UINT = 0,
    wParam: WPARAM = 0,
    lParam: LPARAM = 0,
    time: DWORD = 0,
    pt: POINT = .{},
};
pub const tagMSG = MSG;

/// Maximum path length
pub const MAX_PATH: usize = 260;

/// WIN32_FIND_DATAA structure (ANSI)
pub const WIN32_FIND_DATAA = extern struct {
    dwFileAttributes: DWORD = 0,
    ftCreationTime: FILETIME = .{},
    ftLastAccessTime: FILETIME = .{},
    ftLastWriteTime: FILETIME = .{},
    nFileSizeHigh: DWORD = 0,
    nFileSizeLow: DWORD = 0,
    dwReserved0: DWORD = 0,
    dwReserved1: DWORD = 0,
    cFileName: [MAX_PATH]CHAR = [_]CHAR{0} ** MAX_PATH,
    cAlternateFileName: [14]CHAR = [_]CHAR{0} ** 14,
};

/// WIN32_FIND_DATAW structure (Unicode)
pub const WIN32_FIND_DATAW = extern struct {
    dwFileAttributes: DWORD = 0,
    ftCreationTime: FILETIME = .{},
    ftLastAccessTime: FILETIME = .{},
    ftLastWriteTime: FILETIME = .{},
    nFileSizeHigh: DWORD = 0,
    nFileSizeLow: DWORD = 0,
    dwReserved0: DWORD = 0,
    dwReserved1: DWORD = 0,
    cFileName: [MAX_PATH]WCHAR = [_]WCHAR{0} ** MAX_PATH,
    cAlternateFileName: [14]WCHAR = [_]WCHAR{0} ** 14,
};

// ============================================================================
// Helper Functions
// ============================================================================

/// Create RGB color value
pub fn RGB(red: u8, green: u8, blue: u8) COLORREF {
    return @as(COLORREF, red) + (@as(COLORREF, green) << 8) + (@as(COLORREF, blue) << 16);
}

// ============================================================================
// Pointer Types
// ============================================================================

pub const LPBOOL = *BOOL;
pub const PBOOL = *BOOL;
pub const PBOOLEAN = *BOOLEAN;
pub const LPBYTE = *BYTE;
pub const PBYTE = *BYTE;
pub const PCHAR = *CHAR;
pub const LPCOLORREF = *COLORREF;
pub const LPDWORD = *DWORD;
pub const PDWORD = *DWORD;
pub const LPFILETIME = *FILETIME;
pub const PFILETIME = *FILETIME;
pub const PFLOAT = *FLOAT;
pub const LPHANDLE = *HANDLE;
pub const PHANDLE = *HANDLE;
pub const PHKEY = *HKEY;
pub const LPHKL = *HKL;
pub const LPINT = *INT;
pub const PINT = *INT;
pub const PLARGE_INTEGER = *LARGE_INTEGER;
pub const PLCID = *LCID;
pub const LPLONG = *LONG;
pub const PLONG = *LONG;
pub const LPMSG = *MSG;
pub const PMSG = *MSG;
pub const LPPOINT = *POINT;
pub const PPOINT = *POINT;
pub const PPOINTL = *POINTL;
pub const LPRECT = *RECT;
pub const PRECT = *RECT;
pub const LPRECTL = *RECTL;
pub const PRECTL = *RECTL;
pub const LPSC_HANDLE = *SC_HANDLE;
pub const PSHORT = *SHORT;
pub const LPSIZE = *SIZE;
pub const PSIZE = *SIZE;
pub const LPSIZEL = *SIZEL;
pub const PSIZEL = *SIZEL;
pub const PSMALL_RECT = *SMALL_RECT;
pub const LPUINT = *UINT;
pub const PUINT = *UINT;
pub const PULARGE_INTEGER = *ULARGE_INTEGER;
pub const PULONG = *ULONG;
pub const PUSHORT = *USHORT;
pub const PWCHAR = *WCHAR;
pub const LPWIN32_FIND_DATAA = *WIN32_FIND_DATAA;
pub const PWIN32_FIND_DATAA = *WIN32_FIND_DATAA;
pub const LPWIN32_FIND_DATAW = *WIN32_FIND_DATAW;
pub const PWIN32_FIND_DATAW = *WIN32_FIND_DATAW;
pub const LPWORD = *WORD;
pub const PWORD = *WORD;

// ============================================================================
// Tests
// ============================================================================

test "basic type sizes" {
    try std.testing.expectEqual(@as(usize, 1), @sizeOf(BYTE));
    try std.testing.expectEqual(@as(usize, 2), @sizeOf(WORD));
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(LARGE_INTEGER));
}

test "RECT structure" {
    var rect = RECT{ .left = 10, .top = 20, .right = 100, .bottom = 200 };
    try std.testing.expectEqual(@as(LONG, 10), rect.left);
    try std.testing.expectEqual(@as(LONG, 20), rect.top);
    rect.right = 150;
    try std.testing.expectEqual(@as(LONG, 150), rect.right);
}

test "RGB function" {
    const color = RGB(255, 128, 64);
    try std.testing.expectEqual(@as(COLORREF, 0x4080FF), color);
}

test "POINT structure" {
    const pt = POINT{ .x = 100, .y = 200 };
    try std.testing.expectEqual(@as(LONG, 100), pt.x);
    try std.testing.expectEqual(@as(LONG, 200), pt.y);
}
