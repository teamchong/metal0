//! Python 'winsound' module - Windows sound playing interface
//!
//! Provides access to the Windows sound-playing machinery.
//!
//! Mirrors: CPython Modules/winsound.c

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

pub const WinSoundError = error{
    UnsupportedPlatform,
    SoundNotFound,
    InvalidParameter,
    OperationFailed,
    OutOfMemory,
};

// ============================================================================
// Types
// ============================================================================

pub const DWORD = u32;
pub const UINT = u32;
pub const BOOL = i32;

// ============================================================================
// Constants - PlaySound flags
// ============================================================================

pub const SND_SYNC: DWORD = 0x0000;
pub const SND_ASYNC: DWORD = 0x0001;
pub const SND_NODEFAULT: DWORD = 0x0002;
pub const SND_MEMORY: DWORD = 0x0004;
pub const SND_LOOP: DWORD = 0x0008;
pub const SND_NOSTOP: DWORD = 0x0010;
pub const SND_NOWAIT: DWORD = 0x00002000;
pub const SND_ALIAS: DWORD = 0x00010000;
pub const SND_ALIAS_ID: DWORD = 0x00110000;
pub const SND_FILENAME: DWORD = 0x00020000;
pub const SND_RESOURCE: DWORD = 0x00040004;
pub const SND_PURGE: DWORD = 0x0040;
pub const SND_APPLICATION: DWORD = 0x0080;

// ============================================================================
// Constants - MessageBeep types
// ============================================================================

pub const MB_OK: UINT = 0x00000000;
pub const MB_ICONERROR: UINT = 0x00000010;
pub const MB_ICONQUESTION: UINT = 0x00000020;
pub const MB_ICONWARNING: UINT = 0x00000030;
pub const MB_ICONINFORMATION: UINT = 0x00000040;
pub const MB_ICONHAND: UINT = MB_ICONERROR;
pub const MB_ICONSTOP: UINT = MB_ICONERROR;
pub const MB_ICONEXCLAMATION: UINT = MB_ICONWARNING;
pub const MB_ICONASTERISK: UINT = MB_ICONINFORMATION;

// ============================================================================
// External Windows Functions
// ============================================================================

const winmm = if (is_windows) struct {
    extern "winmm" fn PlaySoundW(
        pszSound: ?[*:0]const u16,
        hmod: ?*anyopaque,
        fdwSound: DWORD,
    ) callconv(windows.WINAPI) BOOL;

    extern "winmm" fn waveOutGetNumDevs() callconv(windows.WINAPI) UINT;

    extern "kernel32" fn Beep(
        dwFreq: DWORD,
        dwDuration: DWORD,
    ) callconv(windows.WINAPI) BOOL;

    extern "user32" fn MessageBeep(
        uType: UINT,
    ) callconv(windows.WINAPI) BOOL;
} else undefined;

// ============================================================================
// Functions
// ============================================================================

/// Play a sound file or system sound
pub fn PlaySound(sound: ?[]const u8, flags: DWORD) WinSoundError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    var sound_ptr: ?[*:0]const u16 = null;
    var sound_buf: [260]u16 = undefined;

    if (sound) |s| {
        const len = std.unicode.utf8ToUtf16Le(&sound_buf, s) catch return error.InvalidParameter;
        sound_buf[len] = 0;
        sound_ptr = @ptrCast(&sound_buf);
    }

    if (winmm.PlaySoundW(sound_ptr, null, flags) == 0) {
        return error.OperationFailed;
    }
}

/// Stop playing any sound
pub fn StopSound() WinSoundError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    if (winmm.PlaySoundW(null, null, SND_PURGE) == 0) {
        return error.OperationFailed;
    }
}

/// Play a sound from memory buffer
pub fn PlaySoundFromMemory(data: []const u8, flags: DWORD) WinSoundError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    const mem_flags = flags | SND_MEMORY;
    if (winmm.PlaySoundW(@ptrCast(data.ptr), null, mem_flags) == 0) {
        return error.OperationFailed;
    }
}

/// Generate a simple beep
pub fn Beep(frequency: DWORD, duration: DWORD) WinSoundError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    // Frequency must be between 37 and 32767 Hz
    if (frequency < 37 or frequency > 32767) {
        return error.InvalidParameter;
    }

    if (winmm.Beep(frequency, duration) == 0) {
        return error.OperationFailed;
    }
}

/// Play a system message beep
pub fn MessageBeep(beep_type: UINT) WinSoundError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    if (winmm.MessageBeep(beep_type) == 0) {
        return error.OperationFailed;
    }
}

/// Get the number of wave output devices
pub fn waveOutGetNumDevs() UINT {
    if (!is_windows) return 0;
    return winmm.waveOutGetNumDevs();
}

// ============================================================================
// System Sound Names
// ============================================================================

pub const SystemSounds = struct {
    pub const Asterisk = "SystemAsterisk";
    pub const Default = "SystemDefault";
    pub const Exclamation = "SystemExclamation";
    pub const Exit = "SystemExit";
    pub const Hand = "SystemHand";
    pub const Question = "SystemQuestion";
    pub const Start = "SystemStart";
};

/// Play a system sound by name
pub fn playSystemSound(name: []const u8) WinSoundError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    return PlaySound(name, SND_ALIAS | SND_ASYNC);
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

test "PlaySound flag constants" {
    try std.testing.expect(SND_SYNC == 0);
    try std.testing.expect(SND_ASYNC == 1);
    try std.testing.expect(SND_FILENAME == 0x00020000);
}

test "MessageBeep type constants" {
    try std.testing.expect(MB_OK == 0);
    try std.testing.expect(MB_ICONERROR == 0x10);
    try std.testing.expect(MB_ICONHAND == MB_ICONERROR);
}

test "waveOutGetNumDevs on Windows" {
    if (is_windows) {
        // Should return number of wave devices (0 or more)
        const num_devs = waveOutGetNumDevs();
        _ = num_devs; // Just verify it doesn't crash
    }
}

test "SystemSounds constants" {
    try std.testing.expectEqualStrings("SystemAsterisk", SystemSounds.Asterisk);
    try std.testing.expectEqualStrings("SystemDefault", SystemSounds.Default);
}
