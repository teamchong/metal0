//! Windows Registry Access
//!
//! Platform-specific module - only available on Windows.
//! On non-Windows platforms, this module compiles but raises ModuleNotFoundError at runtime.
//!
//! CPython source: PC/_winreg.c
//! CPython equivalent: Modules/winreg (Windows-only C extension)

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

// Placeholder types for non-Windows builds
pub const HKEYType = if (is_windows) std.os.windows.HKEY else opaque {};

// Registry key constants (defined for all platforms to allow compilation)
pub const HKEY_CLASSES_ROOT: i32 = 0x80000000;
pub const HKEY_CURRENT_USER: i32 = 0x80000001;
pub const HKEY_LOCAL_MACHINE: i32 = 0x80000002;
pub const HKEY_USERS: i32 = 0x80000003;
pub const HKEY_PERFORMANCE_DATA: i32 = 0x80000004;
pub const HKEY_CURRENT_CONFIG: i32 = 0x80000005;
pub const HKEY_DYN_DATA: i32 = 0x80000006;

// Access rights
pub const KEY_QUERY_VALUE: i32 = 0x0001;
pub const KEY_SET_VALUE: i32 = 0x0002;
pub const KEY_CREATE_SUB_KEY: i32 = 0x0004;
pub const KEY_ENUMERATE_SUB_KEYS: i32 = 0x0008;
pub const KEY_NOTIFY: i32 = 0x0010;
pub const KEY_CREATE_LINK: i32 = 0x0020;
pub const KEY_WOW64_64KEY: i32 = 0x0100;
pub const KEY_WOW64_32KEY: i32 = 0x0200;
pub const KEY_READ: i32 = 0x20019;
pub const KEY_WRITE: i32 = 0x20006;
pub const KEY_EXECUTE: i32 = 0x20019;
pub const KEY_ALL_ACCESS: i32 = 0xF003F;

// Registry value types
pub const REG_NONE: i32 = 0;
pub const REG_SZ: i32 = 1;
pub const REG_EXPAND_SZ: i32 = 2;
pub const REG_BINARY: i32 = 3;
pub const REG_DWORD: i32 = 4;
pub const REG_DWORD_LITTLE_ENDIAN: i32 = 4;
pub const REG_DWORD_BIG_ENDIAN: i32 = 5;
pub const REG_LINK: i32 = 6;
pub const REG_MULTI_SZ: i32 = 7;
pub const REG_RESOURCE_LIST: i32 = 8;
pub const REG_FULL_RESOURCE_DESCRIPTOR: i32 = 9;
pub const REG_RESOURCE_REQUIREMENTS_LIST: i32 = 10;
pub const REG_QWORD: i32 = 11;
pub const REG_QWORD_LITTLE_ENDIAN: i32 = 11;

/// Open a registry key (stub - raises error on non-Windows)
pub fn openKey(allocator: std.mem.Allocator, key: i32, sub_key: []const u8, reserved: i32, access: i32) !HKEYType {
    _ = allocator;
    _ = key;
    _ = sub_key;
    _ = reserved;
    _ = access;
    try checkPlatform();
    @panic("winreg.OpenKey not implemented for Windows yet");
}

/// Close a registry key (stub)
pub fn closeKey(key: HKEYType) !void {
    _ = key;
    try checkPlatform();
}

/// Query registry value (stub)
pub fn queryValue(allocator: std.mem.Allocator, key: HKEYType, sub_key: []const u8) ![]const u8 {
    _ = allocator;
    _ = key;
    _ = sub_key;
    try checkPlatform();
    return error.PlatformNotSupported;
}

/// Set registry value (stub)
pub fn setValue(key: HKEYType, value_name: []const u8, reserved: i32, value_type: i32, data: []const u8) !void {
    _ = key;
    _ = value_name;
    _ = reserved;
    _ = value_type;
    _ = data;
    try checkPlatform();
}

/// Enumerate registry keys (stub)
pub fn enumKey(allocator: std.mem.Allocator, key: HKEYType, index: i32) ![]const u8 {
    _ = allocator;
    _ = key;
    _ = index;
    try checkPlatform();
    return error.PlatformNotSupported;
}

/// Enumerate registry values (stub)
pub fn enumValue(allocator: std.mem.Allocator, key: HKEYType, index: i32) !struct { name: []const u8, data: []const u8, value_type: i32 } {
    _ = allocator;
    _ = key;
    _ = index;
    try checkPlatform();
    return error.PlatformNotSupported;
}

test "winreg platform check" {
    if (builtin.os.tag == .windows) {
        // Should succeed on Windows
        try checkPlatform();
    } else {
        // Should fail on non-Windows
        try std.testing.expectError(error.PlatformNotSupported, checkPlatform());
    }
}
