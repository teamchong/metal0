//! Python 'winreg' module - Windows Registry access
//!
//! Provides access to the Windows Registry, allowing reading, writing,
//! and querying registry keys and values.
//!
//! Mirrors: CPython Modules/winreg.c

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

pub const WinRegError = error{
    UnsupportedPlatform,
    AccessDenied,
    KeyNotFound,
    ValueNotFound,
    InvalidParameter,
    OperationFailed,
    OutOfMemory,
};

// ============================================================================
// Types
// ============================================================================

pub const HKEY = if (is_windows) windows.HKEY else *anyopaque;
pub const DWORD = u32;
pub const REGSAM = DWORD;

// ============================================================================
// Predefined Keys
// ============================================================================

pub const HKEY_CLASSES_ROOT: HKEY = if (is_windows) @ptrFromInt(0x80000000) else @ptrFromInt(0x80000000);
pub const HKEY_CURRENT_USER: HKEY = if (is_windows) @ptrFromInt(0x80000001) else @ptrFromInt(0x80000001);
pub const HKEY_LOCAL_MACHINE: HKEY = if (is_windows) @ptrFromInt(0x80000002) else @ptrFromInt(0x80000002);
pub const HKEY_USERS: HKEY = if (is_windows) @ptrFromInt(0x80000003) else @ptrFromInt(0x80000003);
pub const HKEY_PERFORMANCE_DATA: HKEY = if (is_windows) @ptrFromInt(0x80000004) else @ptrFromInt(0x80000004);
pub const HKEY_CURRENT_CONFIG: HKEY = if (is_windows) @ptrFromInt(0x80000005) else @ptrFromInt(0x80000005);
pub const HKEY_DYN_DATA: HKEY = if (is_windows) @ptrFromInt(0x80000006) else @ptrFromInt(0x80000006);

// ============================================================================
// Registry Value Types
// ============================================================================

pub const REG_NONE: DWORD = 0;
pub const REG_SZ: DWORD = 1;
pub const REG_EXPAND_SZ: DWORD = 2;
pub const REG_BINARY: DWORD = 3;
pub const REG_DWORD: DWORD = 4;
pub const REG_DWORD_LITTLE_ENDIAN: DWORD = 4;
pub const REG_DWORD_BIG_ENDIAN: DWORD = 5;
pub const REG_LINK: DWORD = 6;
pub const REG_MULTI_SZ: DWORD = 7;
pub const REG_RESOURCE_LIST: DWORD = 8;
pub const REG_FULL_RESOURCE_DESCRIPTOR: DWORD = 9;
pub const REG_RESOURCE_REQUIREMENTS_LIST: DWORD = 10;
pub const REG_QWORD: DWORD = 11;
pub const REG_QWORD_LITTLE_ENDIAN: DWORD = 11;

// ============================================================================
// Access Rights
// ============================================================================

pub const KEY_QUERY_VALUE: REGSAM = 0x0001;
pub const KEY_SET_VALUE: REGSAM = 0x0002;
pub const KEY_CREATE_SUB_KEY: REGSAM = 0x0004;
pub const KEY_ENUMERATE_SUB_KEYS: REGSAM = 0x0008;
pub const KEY_NOTIFY: REGSAM = 0x0010;
pub const KEY_CREATE_LINK: REGSAM = 0x0020;
pub const KEY_WOW64_64KEY: REGSAM = 0x0100;
pub const KEY_WOW64_32KEY: REGSAM = 0x0200;
pub const KEY_READ: REGSAM = 0x20019;
pub const KEY_WRITE: REGSAM = 0x20006;
pub const KEY_EXECUTE: REGSAM = KEY_READ;
pub const KEY_ALL_ACCESS: REGSAM = 0xF003F;

// ============================================================================
// Create Options
// ============================================================================

pub const REG_OPTION_RESERVED: DWORD = 0x00000000;
pub const REG_OPTION_NON_VOLATILE: DWORD = 0x00000000;
pub const REG_OPTION_VOLATILE: DWORD = 0x00000001;
pub const REG_OPTION_CREATE_LINK: DWORD = 0x00000002;
pub const REG_OPTION_BACKUP_RESTORE: DWORD = 0x00000004;
pub const REG_OPTION_OPEN_LINK: DWORD = 0x00000008;

// ============================================================================
// Disposition Values
// ============================================================================

pub const REG_CREATED_NEW_KEY: DWORD = 0x00000001;
pub const REG_OPENED_EXISTING_KEY: DWORD = 0x00000002;

// ============================================================================
// Error Codes
// ============================================================================

pub const ERROR_SUCCESS: DWORD = 0;
pub const ERROR_FILE_NOT_FOUND: DWORD = 2;
pub const ERROR_ACCESS_DENIED: DWORD = 5;
pub const ERROR_MORE_DATA: DWORD = 234;
pub const ERROR_NO_MORE_ITEMS: DWORD = 259;

// ============================================================================
// External Windows Functions
// ============================================================================

const advapi32 = if (is_windows) struct {
    extern "advapi32" fn RegOpenKeyExW(
        hKey: HKEY,
        lpSubKey: [*:0]const u16,
        ulOptions: DWORD,
        samDesired: REGSAM,
        phkResult: *HKEY,
    ) callconv(windows.WINAPI) windows.LSTATUS;

    extern "advapi32" fn RegCloseKey(hKey: HKEY) callconv(windows.WINAPI) windows.LSTATUS;

    extern "advapi32" fn RegQueryValueExW(
        hKey: HKEY,
        lpValueName: ?[*:0]const u16,
        lpReserved: ?*DWORD,
        lpType: ?*DWORD,
        lpData: ?[*]u8,
        lpcbData: ?*DWORD,
    ) callconv(windows.WINAPI) windows.LSTATUS;

    extern "advapi32" fn RegSetValueExW(
        hKey: HKEY,
        lpValueName: ?[*:0]const u16,
        Reserved: DWORD,
        dwType: DWORD,
        lpData: [*]const u8,
        cbData: DWORD,
    ) callconv(windows.WINAPI) windows.LSTATUS;

    extern "advapi32" fn RegCreateKeyExW(
        hKey: HKEY,
        lpSubKey: [*:0]const u16,
        Reserved: DWORD,
        lpClass: ?[*:0]u16,
        dwOptions: DWORD,
        samDesired: REGSAM,
        lpSecurityAttributes: ?*anyopaque,
        phkResult: *HKEY,
        lpdwDisposition: ?*DWORD,
    ) callconv(windows.WINAPI) windows.LSTATUS;

    extern "advapi32" fn RegDeleteKeyW(
        hKey: HKEY,
        lpSubKey: [*:0]const u16,
    ) callconv(windows.WINAPI) windows.LSTATUS;

    extern "advapi32" fn RegDeleteValueW(
        hKey: HKEY,
        lpValueName: ?[*:0]const u16,
    ) callconv(windows.WINAPI) windows.LSTATUS;

    extern "advapi32" fn RegEnumKeyExW(
        hKey: HKEY,
        dwIndex: DWORD,
        lpName: [*]u16,
        lpcchName: *DWORD,
        lpReserved: ?*DWORD,
        lpClass: ?[*]u16,
        lpcchClass: ?*DWORD,
        lpftLastWriteTime: ?*windows.FILETIME,
    ) callconv(windows.WINAPI) windows.LSTATUS;

    extern "advapi32" fn RegEnumValueW(
        hKey: HKEY,
        dwIndex: DWORD,
        lpValueName: [*]u16,
        lpcchValueName: *DWORD,
        lpReserved: ?*DWORD,
        lpType: ?*DWORD,
        lpData: ?[*]u8,
        lpcbData: ?*DWORD,
    ) callconv(windows.WINAPI) windows.LSTATUS;

    extern "advapi32" fn RegQueryInfoKeyW(
        hKey: HKEY,
        lpClass: ?[*]u16,
        lpcchClass: ?*DWORD,
        lpReserved: ?*DWORD,
        lpcSubKeys: ?*DWORD,
        lpcbMaxSubKeyLen: ?*DWORD,
        lpcbMaxClassLen: ?*DWORD,
        lpcValues: ?*DWORD,
        lpcbMaxValueNameLen: ?*DWORD,
        lpcbMaxValueLen: ?*DWORD,
        lpcbSecurityDescriptor: ?*DWORD,
        lpftLastWriteTime: ?*windows.FILETIME,
    ) callconv(windows.WINAPI) windows.LSTATUS;

    extern "advapi32" fn RegFlushKey(hKey: HKEY) callconv(windows.WINAPI) windows.LSTATUS;
} else undefined;

// ============================================================================
// Functions
// ============================================================================

/// Open a registry key
pub fn OpenKey(key: HKEY, sub_key: []const u8, access: REGSAM) WinRegError!HKEY {
    if (!is_windows) return error.UnsupportedPlatform;

    var sub_key_buf: [512]u16 = undefined;
    const len = std.unicode.utf8ToUtf16Le(&sub_key_buf, sub_key) catch return error.InvalidParameter;
    sub_key_buf[len] = 0;

    var result_key: HKEY = undefined;
    const status = advapi32.RegOpenKeyExW(key, @ptrCast(&sub_key_buf), 0, access, &result_key);

    if (status != ERROR_SUCCESS) {
        if (status == ERROR_FILE_NOT_FOUND) return error.KeyNotFound;
        if (status == ERROR_ACCESS_DENIED) return error.AccessDenied;
        return error.OperationFailed;
    }

    return result_key;
}

/// Open a registry key (alias)
pub fn OpenKeyEx(key: HKEY, sub_key: []const u8, reserved: DWORD, access: REGSAM) WinRegError!HKEY {
    _ = reserved;
    return OpenKey(key, sub_key, access);
}

/// Close a registry key
pub fn CloseKey(key: HKEY) WinRegError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    const status = advapi32.RegCloseKey(key);
    if (status != ERROR_SUCCESS) {
        return error.OperationFailed;
    }
}

/// Query a registry value
pub fn QueryValue(key: HKEY, value_name: ?[]const u8, allocator: std.mem.Allocator) WinRegError!struct { type: DWORD, data: []u8 } {
    if (!is_windows) return error.UnsupportedPlatform;

    var name_buf: [256]u16 = undefined;
    var name_ptr: ?[*:0]const u16 = null;

    if (value_name) |name| {
        const len = std.unicode.utf8ToUtf16Le(&name_buf, name) catch return error.InvalidParameter;
        name_buf[len] = 0;
        name_ptr = @ptrCast(&name_buf);
    }

    // First query to get size
    var data_size: DWORD = 0;
    var value_type: DWORD = 0;
    var status = advapi32.RegQueryValueExW(key, name_ptr, null, &value_type, null, &data_size);

    if (status == ERROR_FILE_NOT_FOUND) return error.ValueNotFound;
    if (status != ERROR_SUCCESS and status != ERROR_MORE_DATA) return error.OperationFailed;

    // Allocate and query data
    const data = allocator.alloc(u8, data_size) catch return error.OutOfMemory;
    errdefer allocator.free(data);

    status = advapi32.RegQueryValueExW(key, name_ptr, null, &value_type, data.ptr, &data_size);
    if (status != ERROR_SUCCESS) {
        allocator.free(data);
        return error.OperationFailed;
    }

    return .{ .type = value_type, .data = data };
}

/// Query a registry value (extended)
pub fn QueryValueEx(key: HKEY, value_name: ?[]const u8, allocator: std.mem.Allocator) WinRegError!struct { type: DWORD, data: []u8 } {
    return QueryValue(key, value_name, allocator);
}

/// Set a registry value
pub fn SetValue(key: HKEY, value_name: ?[]const u8, value_type: DWORD, data: []const u8) WinRegError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    var name_buf: [256]u16 = undefined;
    var name_ptr: ?[*:0]const u16 = null;

    if (value_name) |name| {
        const len = std.unicode.utf8ToUtf16Le(&name_buf, name) catch return error.InvalidParameter;
        name_buf[len] = 0;
        name_ptr = @ptrCast(&name_buf);
    }

    const status = advapi32.RegSetValueExW(key, name_ptr, 0, value_type, data.ptr, @intCast(data.len));
    if (status != ERROR_SUCCESS) {
        if (status == ERROR_ACCESS_DENIED) return error.AccessDenied;
        return error.OperationFailed;
    }
}

/// Set a registry value (extended)
pub fn SetValueEx(key: HKEY, value_name: ?[]const u8, reserved: DWORD, value_type: DWORD, data: []const u8) WinRegError!void {
    _ = reserved;
    return SetValue(key, value_name, value_type, data);
}

/// Create a registry key
pub fn CreateKey(key: HKEY, sub_key: []const u8) WinRegError!HKEY {
    if (!is_windows) return error.UnsupportedPlatform;

    var sub_key_buf: [512]u16 = undefined;
    const len = std.unicode.utf8ToUtf16Le(&sub_key_buf, sub_key) catch return error.InvalidParameter;
    sub_key_buf[len] = 0;

    var result_key: HKEY = undefined;
    const status = advapi32.RegCreateKeyExW(
        key,
        @ptrCast(&sub_key_buf),
        0,
        null,
        REG_OPTION_NON_VOLATILE,
        KEY_ALL_ACCESS,
        null,
        &result_key,
        null,
    );

    if (status != ERROR_SUCCESS) {
        if (status == ERROR_ACCESS_DENIED) return error.AccessDenied;
        return error.OperationFailed;
    }

    return result_key;
}

/// Create a registry key (extended)
pub fn CreateKeyEx(key: HKEY, sub_key: []const u8, reserved: DWORD, access: REGSAM) WinRegError!struct { key: HKEY, disposition: DWORD } {
    if (!is_windows) return error.UnsupportedPlatform;
    _ = reserved;

    var sub_key_buf: [512]u16 = undefined;
    const len = std.unicode.utf8ToUtf16Le(&sub_key_buf, sub_key) catch return error.InvalidParameter;
    sub_key_buf[len] = 0;

    var result_key: HKEY = undefined;
    var disposition: DWORD = 0;
    const status = advapi32.RegCreateKeyExW(
        key,
        @ptrCast(&sub_key_buf),
        0,
        null,
        REG_OPTION_NON_VOLATILE,
        access,
        null,
        &result_key,
        &disposition,
    );

    if (status != ERROR_SUCCESS) {
        if (status == ERROR_ACCESS_DENIED) return error.AccessDenied;
        return error.OperationFailed;
    }

    return .{ .key = result_key, .disposition = disposition };
}

/// Delete a registry key
pub fn DeleteKey(key: HKEY, sub_key: []const u8) WinRegError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    var sub_key_buf: [512]u16 = undefined;
    const len = std.unicode.utf8ToUtf16Le(&sub_key_buf, sub_key) catch return error.InvalidParameter;
    sub_key_buf[len] = 0;

    const status = advapi32.RegDeleteKeyW(key, @ptrCast(&sub_key_buf));
    if (status != ERROR_SUCCESS) {
        if (status == ERROR_FILE_NOT_FOUND) return error.KeyNotFound;
        if (status == ERROR_ACCESS_DENIED) return error.AccessDenied;
        return error.OperationFailed;
    }
}

/// Delete a registry value
pub fn DeleteValue(key: HKEY, value_name: ?[]const u8) WinRegError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    var name_buf: [256]u16 = undefined;
    var name_ptr: ?[*:0]const u16 = null;

    if (value_name) |name| {
        const len = std.unicode.utf8ToUtf16Le(&name_buf, name) catch return error.InvalidParameter;
        name_buf[len] = 0;
        name_ptr = @ptrCast(&name_buf);
    }

    const status = advapi32.RegDeleteValueW(key, name_ptr);
    if (status != ERROR_SUCCESS) {
        if (status == ERROR_FILE_NOT_FOUND) return error.ValueNotFound;
        if (status == ERROR_ACCESS_DENIED) return error.AccessDenied;
        return error.OperationFailed;
    }
}

/// Enumerate subkeys
pub fn EnumKey(key: HKEY, index: DWORD, allocator: std.mem.Allocator) WinRegError!?[]u8 {
    if (!is_windows) return error.UnsupportedPlatform;

    var name_buf: [256]u16 = undefined;
    var name_len: DWORD = 256;

    const status = advapi32.RegEnumKeyExW(key, index, &name_buf, &name_len, null, null, null, null);

    if (status == ERROR_NO_MORE_ITEMS) return null;
    if (status != ERROR_SUCCESS) return error.OperationFailed;

    // Convert UTF-16 to UTF-8
    const utf8_len = std.unicode.utf16LeToUtf8(&.{}, name_buf[0..name_len]) catch return error.OperationFailed;
    const result = allocator.alloc(u8, utf8_len) catch return error.OutOfMemory;
    _ = std.unicode.utf16LeToUtf8(result, name_buf[0..name_len]) catch {
        allocator.free(result);
        return error.OperationFailed;
    };

    return result;
}

/// Enumerate values
pub fn EnumValue(key: HKEY, index: DWORD, allocator: std.mem.Allocator) WinRegError!?struct { name: []u8, type: DWORD } {
    if (!is_windows) return error.UnsupportedPlatform;

    var name_buf: [256]u16 = undefined;
    var name_len: DWORD = 256;
    var value_type: DWORD = 0;

    const status = advapi32.RegEnumValueW(key, index, &name_buf, &name_len, null, &value_type, null, null);

    if (status == ERROR_NO_MORE_ITEMS) return null;
    if (status != ERROR_SUCCESS) return error.OperationFailed;

    // Convert UTF-16 to UTF-8
    const utf8_len = std.unicode.utf16LeToUtf8(&.{}, name_buf[0..name_len]) catch return error.OperationFailed;
    const result = allocator.alloc(u8, utf8_len) catch return error.OutOfMemory;
    _ = std.unicode.utf16LeToUtf8(result, name_buf[0..name_len]) catch {
        allocator.free(result);
        return error.OperationFailed;
    };

    return .{ .name = result, .type = value_type };
}

/// Query key info
pub fn QueryInfoKey(key: HKEY) WinRegError!struct {
    num_sub_keys: DWORD,
    max_sub_key_len: DWORD,
    num_values: DWORD,
    max_value_name_len: DWORD,
    max_value_len: DWORD,
} {
    if (!is_windows) return error.UnsupportedPlatform;

    var num_sub_keys: DWORD = 0;
    var max_sub_key_len: DWORD = 0;
    var num_values: DWORD = 0;
    var max_value_name_len: DWORD = 0;
    var max_value_len: DWORD = 0;

    const status = advapi32.RegQueryInfoKeyW(
        key,
        null,
        null,
        null,
        &num_sub_keys,
        &max_sub_key_len,
        null,
        &num_values,
        &max_value_name_len,
        &max_value_len,
        null,
        null,
    );

    if (status != ERROR_SUCCESS) return error.OperationFailed;

    return .{
        .num_sub_keys = num_sub_keys,
        .max_sub_key_len = max_sub_key_len,
        .num_values = num_values,
        .max_value_name_len = max_value_name_len,
        .max_value_len = max_value_len,
    };
}

/// Flush key to disk
pub fn FlushKey(key: HKEY) WinRegError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    const status = advapi32.RegFlushKey(key);
    if (status != ERROR_SUCCESS) {
        return error.OperationFailed;
    }
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Expand environment strings in a value
pub fn ExpandEnvironmentStrings(allocator: std.mem.Allocator, value: []const u8) WinRegError![]u8 {
    if (!is_windows) return error.UnsupportedPlatform;

    // Convert to UTF-16
    var value_buf: [4096]u16 = undefined;
    const len = std.unicode.utf8ToUtf16Le(&value_buf, value) catch return error.InvalidParameter;
    value_buf[len] = 0;

    // Expand
    var result_buf: [4096]u16 = undefined;
    const expanded_len = windows.kernel32.ExpandEnvironmentStringsW(@ptrCast(&value_buf), &result_buf, 4096);
    if (expanded_len == 0) return error.OperationFailed;

    // Convert back to UTF-8
    const utf8_len = std.unicode.utf16LeToUtf8(&.{}, result_buf[0 .. expanded_len - 1]) catch return error.OperationFailed;
    const result = allocator.alloc(u8, utf8_len) catch return error.OutOfMemory;
    _ = std.unicode.utf16LeToUtf8(result, result_buf[0 .. expanded_len - 1]) catch {
        allocator.free(result);
        return error.OperationFailed;
    };

    return result;
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

test "registry type constants" {
    try std.testing.expectEqual(@as(DWORD, 1), REG_SZ);
    try std.testing.expectEqual(@as(DWORD, 4), REG_DWORD);
    try std.testing.expectEqual(@as(DWORD, 11), REG_QWORD);
}

test "registry access constants" {
    try std.testing.expect(KEY_READ > 0);
    try std.testing.expect(KEY_WRITE > 0);
    try std.testing.expect(KEY_ALL_ACCESS > KEY_READ);
}

test "predefined keys" {
    try std.testing.expect(@intFromPtr(HKEY_LOCAL_MACHINE) == 0x80000002);
    try std.testing.expect(@intFromPtr(HKEY_CURRENT_USER) == 0x80000001);
}

test "OpenKey on Windows" {
    if (is_windows) {
        // Try to open a well-known key
        const key = OpenKey(HKEY_LOCAL_MACHINE, "SOFTWARE", KEY_READ) catch |err| {
            // Access might be denied, that's OK
            if (err == error.AccessDenied) return;
            return err;
        };
        defer CloseKey(key) catch {};
    }
}
