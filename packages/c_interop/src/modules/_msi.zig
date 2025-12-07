//! Python '_msi' module - Windows Installer (MSI) database access
//!
//! Read and write data in Windows Installer (.msi) database files.
//!
//! Mirrors: CPython Modules/_msi.c

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

pub const MsiError = error{
    UnsupportedPlatform,
    DatabaseOpenFailed,
    ViewCreationFailed,
    ExecutionFailed,
    FetchFailed,
    RecordNotFound,
    InvalidParameter,
    OutOfMemory,
};

// ============================================================================
// Types
// ============================================================================

pub const MSIHANDLE = u32;
pub const UINT = u32;

// ============================================================================
// Constants - Open Database Modes
// ============================================================================

pub const MSIDBOPEN_READONLY: i32 = 0;
pub const MSIDBOPEN_TRANSACT: i32 = 1;
pub const MSIDBOPEN_DIRECT: i32 = 2;
pub const MSIDBOPEN_CREATE: i32 = 3;
pub const MSIDBOPEN_CREATEDIRECT: i32 = 4;

// ============================================================================
// Constants - Modify Modes
// ============================================================================

pub const MSIMODIFY_SEEK: i32 = -1;
pub const MSIMODIFY_REFRESH: i32 = 0;
pub const MSIMODIFY_INSERT: i32 = 1;
pub const MSIMODIFY_UPDATE: i32 = 2;
pub const MSIMODIFY_ASSIGN: i32 = 3;
pub const MSIMODIFY_REPLACE: i32 = 4;
pub const MSIMODIFY_MERGE: i32 = 5;
pub const MSIMODIFY_DELETE: i32 = 6;
pub const MSIMODIFY_INSERT_TEMPORARY: i32 = 7;
pub const MSIMODIFY_VALIDATE: i32 = 8;
pub const MSIMODIFY_VALIDATE_NEW: i32 = 9;
pub const MSIMODIFY_VALIDATE_FIELD: i32 = 10;
pub const MSIMODIFY_VALIDATE_DELETE: i32 = 11;

// ============================================================================
// Constants - Error Codes
// ============================================================================

pub const ERROR_SUCCESS: UINT = 0;
pub const ERROR_INVALID_HANDLE: UINT = 6;
pub const ERROR_INVALID_PARAMETER: UINT = 87;
pub const ERROR_FUNCTION_FAILED: UINT = 1627;
pub const ERROR_NO_MORE_ITEMS: UINT = 259;
pub const ERROR_CREATE_FAILED: UINT = 1631;
pub const ERROR_OPEN_FAILED: UINT = 110;

// ============================================================================
// Constants - Column Types
// ============================================================================

pub const MSICOLINFO_NAMES: UINT = 0;
pub const MSICOLINFO_TYPES: UINT = 1;

// ============================================================================
// External MSI Functions
// ============================================================================

const msi = if (is_windows) struct {
    extern "msi" fn MsiOpenDatabaseW(
        szDatabasePath: [*:0]const u16,
        szPersist: ?*const anyopaque,
        phDatabase: *MSIHANDLE,
    ) callconv(windows.WINAPI) UINT;

    extern "msi" fn MsiCloseHandle(
        hAny: MSIHANDLE,
    ) callconv(windows.WINAPI) UINT;

    extern "msi" fn MsiDatabaseOpenViewW(
        hDatabase: MSIHANDLE,
        szQuery: [*:0]const u16,
        phView: *MSIHANDLE,
    ) callconv(windows.WINAPI) UINT;

    extern "msi" fn MsiViewExecute(
        hView: MSIHANDLE,
        hRecord: MSIHANDLE,
    ) callconv(windows.WINAPI) UINT;

    extern "msi" fn MsiViewFetch(
        hView: MSIHANDLE,
        phRecord: *MSIHANDLE,
    ) callconv(windows.WINAPI) UINT;

    extern "msi" fn MsiViewClose(
        hView: MSIHANDLE,
    ) callconv(windows.WINAPI) UINT;

    extern "msi" fn MsiViewModify(
        hView: MSIHANDLE,
        eModifyMode: i32,
        hRecord: MSIHANDLE,
    ) callconv(windows.WINAPI) UINT;

    extern "msi" fn MsiRecordGetFieldCount(
        hRecord: MSIHANDLE,
    ) callconv(windows.WINAPI) UINT;

    extern "msi" fn MsiRecordGetInteger(
        hRecord: MSIHANDLE,
        iField: UINT,
    ) callconv(windows.WINAPI) c_int;

    extern "msi" fn MsiRecordGetStringW(
        hRecord: MSIHANDLE,
        iField: UINT,
        szValueBuf: ?[*]u16,
        pcchValueBuf: *UINT,
    ) callconv(windows.WINAPI) UINT;

    extern "msi" fn MsiRecordSetInteger(
        hRecord: MSIHANDLE,
        iField: UINT,
        iValue: c_int,
    ) callconv(windows.WINAPI) UINT;

    extern "msi" fn MsiRecordSetStringW(
        hRecord: MSIHANDLE,
        iField: UINT,
        szValue: [*:0]const u16,
    ) callconv(windows.WINAPI) UINT;

    extern "msi" fn MsiCreateRecord(
        cParams: UINT,
    ) callconv(windows.WINAPI) MSIHANDLE;

    extern "msi" fn MsiDatabaseCommit(
        hDatabase: MSIHANDLE,
    ) callconv(windows.WINAPI) UINT;

    extern "msi" fn MsiGetSummaryInformationW(
        hDatabase: MSIHANDLE,
        szDatabasePath: ?[*:0]const u16,
        uiUpdateCount: UINT,
        phSummaryInfo: *MSIHANDLE,
    ) callconv(windows.WINAPI) UINT;

    extern "msi" fn MsiSummaryInfoGetPropertyW(
        hSummaryInfo: MSIHANDLE,
        uiProperty: UINT,
        puiDataType: *UINT,
        piValue: *c_int,
        pftValue: ?*windows.FILETIME,
        szValueBuf: ?[*]u16,
        pcchValueBuf: *UINT,
    ) callconv(windows.WINAPI) UINT;

    extern "msi" fn MsiSummaryInfoSetPropertyW(
        hSummaryInfo: MSIHANDLE,
        uiProperty: UINT,
        uiDataType: UINT,
        iValue: c_int,
        pftValue: ?*const windows.FILETIME,
        szValue: ?[*:0]const u16,
    ) callconv(windows.WINAPI) UINT;

    extern "msi" fn MsiSummaryInfoPersist(
        hSummaryInfo: MSIHANDLE,
    ) callconv(windows.WINAPI) UINT;
} else undefined;

// ============================================================================
// Database Functions
// ============================================================================

/// Open an MSI database
pub fn openDatabase(path: []const u8, mode: i32) MsiError!MSIHANDLE {
    if (!is_windows) return error.UnsupportedPlatform;

    var path_buf: [260]u16 = undefined;
    const len = std.unicode.utf8ToUtf16Le(&path_buf, path) catch return error.InvalidParameter;
    path_buf[len] = 0;

    var handle: MSIHANDLE = 0;
    const mode_ptr: ?*const anyopaque = @ptrFromInt(@as(usize, @intCast(mode)));
    const result = msi.MsiOpenDatabaseW(@ptrCast(&path_buf), mode_ptr, &handle);

    if (result != ERROR_SUCCESS) {
        return error.DatabaseOpenFailed;
    }

    return handle;
}

/// Close an MSI handle
pub fn closeHandle(handle: MSIHANDLE) MsiError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    const result = msi.MsiCloseHandle(handle);
    if (result != ERROR_SUCCESS) {
        // Ignore close errors
    }
}

/// Commit changes to database
pub fn commitDatabase(handle: MSIHANDLE) MsiError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    const result = msi.MsiDatabaseCommit(handle);
    if (result != ERROR_SUCCESS) {
        return error.ExecutionFailed;
    }
}

// ============================================================================
// View Functions
// ============================================================================

/// Open a database view with SQL query
pub fn openView(database: MSIHANDLE, query: []const u8) MsiError!MSIHANDLE {
    if (!is_windows) return error.UnsupportedPlatform;

    var query_buf: [4096]u16 = undefined;
    const len = std.unicode.utf8ToUtf16Le(&query_buf, query) catch return error.InvalidParameter;
    query_buf[len] = 0;

    var view: MSIHANDLE = 0;
    const result = msi.MsiDatabaseOpenViewW(database, @ptrCast(&query_buf), &view);

    if (result != ERROR_SUCCESS) {
        return error.ViewCreationFailed;
    }

    return view;
}

/// Execute a view
pub fn executeView(view: MSIHANDLE, record: MSIHANDLE) MsiError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    const result = msi.MsiViewExecute(view, record);
    if (result != ERROR_SUCCESS) {
        return error.ExecutionFailed;
    }
}

/// Fetch next record from view
pub fn fetchView(view: MSIHANDLE) MsiError!?MSIHANDLE {
    if (!is_windows) return error.UnsupportedPlatform;

    var record: MSIHANDLE = 0;
    const result = msi.MsiViewFetch(view, &record);

    if (result == ERROR_NO_MORE_ITEMS) {
        return null;
    }
    if (result != ERROR_SUCCESS) {
        return error.FetchFailed;
    }

    return record;
}

/// Close a view
pub fn closeView(view: MSIHANDLE) MsiError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    const result = msi.MsiViewClose(view);
    if (result != ERROR_SUCCESS) {
        // Ignore close errors
    }
}

/// Modify a record in a view
pub fn modifyView(view: MSIHANDLE, mode: i32, record: MSIHANDLE) MsiError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    const result = msi.MsiViewModify(view, mode, record);
    if (result != ERROR_SUCCESS) {
        return error.ExecutionFailed;
    }
}

// ============================================================================
// Record Functions
// ============================================================================

/// Create a new record
pub fn createRecord(field_count: UINT) MsiError!MSIHANDLE {
    if (!is_windows) return error.UnsupportedPlatform;

    const handle = msi.MsiCreateRecord(field_count);
    if (handle == 0) {
        return error.OutOfMemory;
    }
    return handle;
}

/// Get field count in a record
pub fn getFieldCount(record: MSIHANDLE) UINT {
    if (!is_windows) return 0;
    return msi.MsiRecordGetFieldCount(record);
}

/// Get integer value from a record field
pub fn getIntegerField(record: MSIHANDLE, field: UINT) MsiError!i32 {
    if (!is_windows) return error.UnsupportedPlatform;
    return msi.MsiRecordGetInteger(record, field);
}

/// Get string value from a record field
pub fn getStringField(record: MSIHANDLE, field: UINT, allocator: std.mem.Allocator) MsiError![]u8 {
    if (!is_windows) return error.UnsupportedPlatform;

    // First get size
    var size: UINT = 0;
    var result = msi.MsiRecordGetStringW(record, field, null, &size);
    if (result != ERROR_SUCCESS and result != 234) { // ERROR_MORE_DATA
        return error.FetchFailed;
    }

    // Allocate and get string
    var buf = allocator.alloc(u16, size + 1) catch return error.OutOfMemory;
    defer allocator.free(buf);

    size += 1;
    result = msi.MsiRecordGetStringW(record, field, buf.ptr, &size);
    if (result != ERROR_SUCCESS) {
        return error.FetchFailed;
    }

    // Convert to UTF-8
    const utf8_len = std.unicode.utf16LeToUtf8(&.{}, buf[0..size]) catch return error.FetchFailed;
    const utf8 = allocator.alloc(u8, utf8_len) catch return error.OutOfMemory;
    _ = std.unicode.utf16LeToUtf8(utf8, buf[0..size]) catch {
        allocator.free(utf8);
        return error.FetchFailed;
    };

    return utf8;
}

/// Set integer value in a record field
pub fn setIntegerField(record: MSIHANDLE, field: UINT, value: i32) MsiError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    const result = msi.MsiRecordSetInteger(record, field, value);
    if (result != ERROR_SUCCESS) {
        return error.ExecutionFailed;
    }
}

/// Set string value in a record field
pub fn setStringField(record: MSIHANDLE, field: UINT, value: []const u8) MsiError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    var buf: [4096]u16 = undefined;
    const len = std.unicode.utf8ToUtf16Le(&buf, value) catch return error.InvalidParameter;
    buf[len] = 0;

    const result = msi.MsiRecordSetStringW(record, field, @ptrCast(&buf));
    if (result != ERROR_SUCCESS) {
        return error.ExecutionFailed;
    }
}

// ============================================================================
// Summary Information Functions
// ============================================================================

/// Summary information property IDs
pub const PID_CODEPAGE: UINT = 1;
pub const PID_TITLE: UINT = 2;
pub const PID_SUBJECT: UINT = 3;
pub const PID_AUTHOR: UINT = 4;
pub const PID_KEYWORDS: UINT = 5;
pub const PID_COMMENTS: UINT = 6;
pub const PID_TEMPLATE: UINT = 7;
pub const PID_LASTAUTHOR: UINT = 8;
pub const PID_REVNUMBER: UINT = 9;
pub const PID_LASTPRINTED: UINT = 11;
pub const PID_CREATE_DTM: UINT = 12;
pub const PID_LASTSAVE_DTM: UINT = 13;
pub const PID_PAGECOUNT: UINT = 14;
pub const PID_WORDCOUNT: UINT = 15;
pub const PID_CHARCOUNT: UINT = 16;
pub const PID_APPNAME: UINT = 18;
pub const PID_SECURITY: UINT = 19;

/// Get summary information handle
pub fn getSummaryInformation(database: MSIHANDLE, update_count: UINT) MsiError!MSIHANDLE {
    if (!is_windows) return error.UnsupportedPlatform;

    var handle: MSIHANDLE = 0;
    const result = msi.MsiGetSummaryInformationW(database, null, update_count, &handle);

    if (result != ERROR_SUCCESS) {
        return error.ExecutionFailed;
    }

    return handle;
}

/// Persist summary information
pub fn persistSummaryInformation(summary: MSIHANDLE) MsiError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    const result = msi.MsiSummaryInfoPersist(summary);
    if (result != ERROR_SUCCESS) {
        return error.ExecutionFailed;
    }
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

test "open mode constants" {
    try std.testing.expectEqual(@as(i32, 0), MSIDBOPEN_READONLY);
    try std.testing.expectEqual(@as(i32, 1), MSIDBOPEN_TRANSACT);
    try std.testing.expectEqual(@as(i32, 3), MSIDBOPEN_CREATE);
}

test "modify mode constants" {
    try std.testing.expectEqual(@as(i32, 1), MSIMODIFY_INSERT);
    try std.testing.expectEqual(@as(i32, 2), MSIMODIFY_UPDATE);
    try std.testing.expectEqual(@as(i32, 6), MSIMODIFY_DELETE);
}

test "property IDs" {
    try std.testing.expectEqual(@as(UINT, 2), PID_TITLE);
    try std.testing.expectEqual(@as(UINT, 4), PID_AUTHOR);
    try std.testing.expectEqual(@as(UINT, 19), PID_SECURITY);
}

test "error codes" {
    try std.testing.expectEqual(@as(UINT, 0), ERROR_SUCCESS);
    try std.testing.expectEqual(@as(UINT, 259), ERROR_NO_MORE_ITEMS);
}
