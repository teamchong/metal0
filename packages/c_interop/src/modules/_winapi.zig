//! CPython source: Modules/_winapi.c
//!
//! Provides low-level access to Windows API functions for process creation,
//! pipe handling, and other OS-level operations.
//!
//! Mirrors: CPython Modules/_winapi.c

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

pub const WinApiError = error{
    UnsupportedPlatform,
    InvalidHandle,
    AccessDenied,
    InvalidParameter,
    OperationFailed,
    BrokenPipe,
    PipeBusy,
    FileNotFound,
    OutOfMemory,
};

// ============================================================================
// Types
// ============================================================================

pub const HANDLE = if (is_windows) windows.HANDLE else *anyopaque;
pub const BOOL = if (is_windows) windows.BOOL else c_int;
pub const DWORD = u32;
pub const LPVOID = *anyopaque;

pub const INVALID_HANDLE_VALUE: HANDLE = if (is_windows)
    windows.INVALID_HANDLE_VALUE
else
    @ptrFromInt(~@as(usize, 0));

// ============================================================================
// Constants - Process Creation
// ============================================================================

pub const CREATE_NEW_CONSOLE: DWORD = 0x00000010;
pub const CREATE_NEW_PROCESS_GROUP: DWORD = 0x00000200;
pub const CREATE_NO_WINDOW: DWORD = 0x08000000;
pub const CREATE_UNICODE_ENVIRONMENT: DWORD = 0x00000400;
pub const DETACHED_PROCESS: DWORD = 0x00000008;
pub const CREATE_DEFAULT_ERROR_MODE: DWORD = 0x04000000;
pub const CREATE_BREAKAWAY_FROM_JOB: DWORD = 0x01000000;

// Priority class
pub const ABOVE_NORMAL_PRIORITY_CLASS: DWORD = 0x00008000;
pub const BELOW_NORMAL_PRIORITY_CLASS: DWORD = 0x00004000;
pub const HIGH_PRIORITY_CLASS: DWORD = 0x00000080;
pub const IDLE_PRIORITY_CLASS: DWORD = 0x00000040;
pub const NORMAL_PRIORITY_CLASS: DWORD = 0x00000020;
pub const REALTIME_PRIORITY_CLASS: DWORD = 0x00000100;

// ============================================================================
// Constants - Standard Handles
// ============================================================================

pub const STD_INPUT_HANDLE: DWORD = @bitCast(@as(i32, -10));
pub const STD_OUTPUT_HANDLE: DWORD = @bitCast(@as(i32, -11));
pub const STD_ERROR_HANDLE: DWORD = @bitCast(@as(i32, -12));

// ============================================================================
// Constants - Wait
// ============================================================================

pub const INFINITE: DWORD = 0xFFFFFFFF;
pub const WAIT_OBJECT_0: DWORD = 0x00000000;
pub const WAIT_ABANDONED: DWORD = 0x00000080;
pub const WAIT_ABANDONED_0: DWORD = 0x00000080;
pub const WAIT_TIMEOUT: DWORD = 0x00000102;
pub const WAIT_FAILED: DWORD = 0xFFFFFFFF;

// ============================================================================
// Constants - Pipes
// ============================================================================

pub const PIPE_ACCESS_DUPLEX: DWORD = 0x00000003;
pub const PIPE_ACCESS_INBOUND: DWORD = 0x00000001;
pub const PIPE_ACCESS_OUTBOUND: DWORD = 0x00000002;
pub const PIPE_TYPE_BYTE: DWORD = 0x00000000;
pub const PIPE_TYPE_MESSAGE: DWORD = 0x00000004;
pub const PIPE_READMODE_BYTE: DWORD = 0x00000000;
pub const PIPE_READMODE_MESSAGE: DWORD = 0x00000002;
pub const PIPE_WAIT: DWORD = 0x00000000;
pub const PIPE_NOWAIT: DWORD = 0x00000001;
pub const PIPE_UNLIMITED_INSTANCES: DWORD = 255;
pub const NMPWAIT_WAIT_FOREVER: DWORD = 0xFFFFFFFF;
pub const NMPWAIT_NOWAIT: DWORD = 0x00000001;
pub const NMPWAIT_USE_DEFAULT_WAIT: DWORD = 0x00000000;

// ============================================================================
// Constants - File
// ============================================================================

pub const GENERIC_READ: DWORD = 0x80000000;
pub const GENERIC_WRITE: DWORD = 0x40000000;
pub const GENERIC_EXECUTE: DWORD = 0x20000000;
pub const GENERIC_ALL: DWORD = 0x10000000;

pub const FILE_SHARE_READ: DWORD = 0x00000001;
pub const FILE_SHARE_WRITE: DWORD = 0x00000002;
pub const FILE_SHARE_DELETE: DWORD = 0x00000004;

pub const CREATE_NEW: DWORD = 1;
pub const CREATE_ALWAYS: DWORD = 2;
pub const OPEN_EXISTING: DWORD = 3;
pub const OPEN_ALWAYS: DWORD = 4;
pub const TRUNCATE_EXISTING: DWORD = 5;

pub const FILE_ATTRIBUTE_NORMAL: DWORD = 0x00000080;
pub const FILE_FLAG_OVERLAPPED: DWORD = 0x40000000;
pub const FILE_FLAG_NO_BUFFERING: DWORD = 0x20000000;

// ============================================================================
// Constants - Process Access
// ============================================================================

pub const PROCESS_ALL_ACCESS: DWORD = 0x001FFFFF;
pub const PROCESS_CREATE_PROCESS: DWORD = 0x0080;
pub const PROCESS_CREATE_THREAD: DWORD = 0x0002;
pub const PROCESS_DUP_HANDLE: DWORD = 0x0040;
pub const PROCESS_QUERY_INFORMATION: DWORD = 0x0400;
pub const PROCESS_QUERY_LIMITED_INFORMATION: DWORD = 0x1000;
pub const PROCESS_SET_INFORMATION: DWORD = 0x0200;
pub const PROCESS_SET_QUOTA: DWORD = 0x0100;
pub const PROCESS_SUSPEND_RESUME: DWORD = 0x0800;
pub const PROCESS_TERMINATE: DWORD = 0x0001;
pub const PROCESS_VM_OPERATION: DWORD = 0x0008;
pub const PROCESS_VM_READ: DWORD = 0x0010;
pub const PROCESS_VM_WRITE: DWORD = 0x0020;
pub const SYNCHRONIZE: DWORD = 0x00100000;

// ============================================================================
// Constants - Duplication
// ============================================================================

pub const DUPLICATE_CLOSE_SOURCE: DWORD = 0x00000001;
pub const DUPLICATE_SAME_ACCESS: DWORD = 0x00000002;

// ============================================================================
// Constants - Memory
// ============================================================================

pub const MEM_COMMIT: DWORD = 0x00001000;
pub const MEM_RESERVE: DWORD = 0x00002000;
pub const MEM_RELEASE: DWORD = 0x00008000;
pub const PAGE_READWRITE: DWORD = 0x04;

// ============================================================================
// Constants - Error Codes
// ============================================================================

pub const ERROR_SUCCESS: DWORD = 0;
pub const ERROR_FILE_NOT_FOUND: DWORD = 2;
pub const ERROR_PATH_NOT_FOUND: DWORD = 3;
pub const ERROR_ACCESS_DENIED: DWORD = 5;
pub const ERROR_INVALID_HANDLE: DWORD = 6;
pub const ERROR_INVALID_PARAMETER: DWORD = 87;
pub const ERROR_BROKEN_PIPE: DWORD = 109;
pub const ERROR_PIPE_BUSY: DWORD = 231;
pub const ERROR_NO_DATA: DWORD = 232;
pub const ERROR_PIPE_NOT_CONNECTED: DWORD = 233;
pub const ERROR_MORE_DATA: DWORD = 234;
pub const ERROR_OPERATION_ABORTED: DWORD = 995;
pub const ERROR_IO_INCOMPLETE: DWORD = 996;
pub const ERROR_IO_PENDING: DWORD = 997;

// ============================================================================
// Structures
// ============================================================================

pub const OVERLAPPED = extern struct {
    Internal: usize = 0,
    InternalHigh: usize = 0,
    Offset: DWORD = 0,
    OffsetHigh: DWORD = 0,
    hEvent: ?HANDLE = null,
};

pub const SECURITY_ATTRIBUTES = extern struct {
    nLength: DWORD = @sizeOf(SECURITY_ATTRIBUTES),
    lpSecurityDescriptor: ?LPVOID = null,
    bInheritHandle: BOOL = 0,
};

pub const STARTUPINFOW = extern struct {
    cb: DWORD = @sizeOf(STARTUPINFOW),
    lpReserved: ?[*:0]u16 = null,
    lpDesktop: ?[*:0]u16 = null,
    lpTitle: ?[*:0]u16 = null,
    dwX: DWORD = 0,
    dwY: DWORD = 0,
    dwXSize: DWORD = 0,
    dwYSize: DWORD = 0,
    dwXCountChars: DWORD = 0,
    dwYCountChars: DWORD = 0,
    dwFillAttribute: DWORD = 0,
    dwFlags: DWORD = 0,
    wShowWindow: u16 = 0,
    cbReserved2: u16 = 0,
    lpReserved2: ?*u8 = null,
    hStdInput: ?HANDLE = null,
    hStdOutput: ?HANDLE = null,
    hStdError: ?HANDLE = null,
};

pub const PROCESS_INFORMATION = extern struct {
    hProcess: HANDLE,
    hThread: HANDLE,
    dwProcessId: DWORD,
    dwThreadId: DWORD,
};

// Startup info flags
pub const STARTF_USESHOWWINDOW: DWORD = 0x00000001;
pub const STARTF_USESIZE: DWORD = 0x00000002;
pub const STARTF_USEPOSITION: DWORD = 0x00000004;
pub const STARTF_USECOUNTCHARS: DWORD = 0x00000008;
pub const STARTF_USEFILLATTRIBUTE: DWORD = 0x00000010;
pub const STARTF_USESTDHANDLES: DWORD = 0x00000100;

// ============================================================================
// Functions - Windows Implementation
// ============================================================================

/// Close a handle
pub fn CloseHandle(handle: HANDLE) WinApiError!void {
    if (!is_windows) return error.UnsupportedPlatform;
    if (windows.kernel32.CloseHandle(handle) == 0) {
        return error.InvalidHandle;
    }
}

/// Create an anonymous pipe
pub fn CreatePipe(inherit_read: bool, inherit_write: bool) WinApiError!struct { read: HANDLE, write: HANDLE } {
    if (!is_windows) return error.UnsupportedPlatform;

    var read_handle: HANDLE = undefined;
    var write_handle: HANDLE = undefined;

    var sa_read = SECURITY_ATTRIBUTES{
        .bInheritHandle = if (inherit_read) 1 else 0,
    };
    var sa_write = SECURITY_ATTRIBUTES{
        .bInheritHandle = if (inherit_write) 1 else 0,
    };

    // Use same security attributes for both if they match
    const sa_ptr = if (inherit_read == inherit_write) &sa_read else &sa_read;
    _ = sa_write;

    if (windows.kernel32.CreatePipe(&read_handle, &write_handle, sa_ptr, 0) == 0) {
        return error.OperationFailed;
    }

    return .{ .read = read_handle, .write = write_handle };
}

/// Create a named pipe
pub fn CreateNamedPipe(
    name: []const u8,
    open_mode: DWORD,
    pipe_mode: DWORD,
    max_instances: DWORD,
    out_buffer_size: DWORD,
    in_buffer_size: DWORD,
    default_timeout: DWORD,
) WinApiError!HANDLE {
    if (!is_windows) return error.UnsupportedPlatform;

    var name_buf: [256]u16 = undefined;
    const name_len = std.unicode.utf8ToUtf16Le(&name_buf, name) catch return error.InvalidParameter;
    name_buf[name_len] = 0;

    const handle = windows.kernel32.CreateNamedPipeW(
        @ptrCast(&name_buf),
        open_mode,
        pipe_mode,
        max_instances,
        out_buffer_size,
        in_buffer_size,
        default_timeout,
        null,
    );

    if (handle == INVALID_HANDLE_VALUE) {
        return error.OperationFailed;
    }

    return handle;
}

/// Connect a named pipe
pub fn ConnectNamedPipe(handle: HANDLE, overlapped: ?*OVERLAPPED) WinApiError!bool {
    if (!is_windows) return error.UnsupportedPlatform;

    const result = windows.kernel32.ConnectNamedPipe(handle, overlapped);
    if (result == 0) {
        const err = GetLastError();
        if (err == ERROR_IO_PENDING) return false;
        if (err == ERROR_PIPE_CONNECTED) return true;
        return error.OperationFailed;
    }
    return true;
}

/// Duplicate a handle
pub fn DuplicateHandle(
    source_process: HANDLE,
    source_handle: HANDLE,
    target_process: HANDLE,
    desired_access: DWORD,
    inherit_handle: bool,
    options: DWORD,
) WinApiError!HANDLE {
    if (!is_windows) return error.UnsupportedPlatform;

    var target_handle: HANDLE = undefined;
    if (windows.kernel32.DuplicateHandle(
        source_process,
        source_handle,
        target_process,
        &target_handle,
        desired_access,
        if (inherit_handle) 1 else 0,
        options,
    ) == 0) {
        return error.OperationFailed;
    }
    return target_handle;
}

/// Get the current process handle
pub fn GetCurrentProcess() HANDLE {
    if (!is_windows) return INVALID_HANDLE_VALUE;
    return windows.kernel32.GetCurrentProcess();
}

/// Get the current process ID
pub fn GetCurrentProcessId() DWORD {
    if (!is_windows) return 0;
    return windows.kernel32.GetCurrentProcessId();
}

/// Get exit code of a process
pub fn GetExitCodeProcess(handle: HANDLE) WinApiError!DWORD {
    if (!is_windows) return error.UnsupportedPlatform;

    var exit_code: DWORD = undefined;
    if (windows.kernel32.GetExitCodeProcess(handle, &exit_code) == 0) {
        return error.InvalidHandle;
    }
    return exit_code;
}

/// Get last Windows error code
pub fn GetLastError() DWORD {
    if (!is_windows) return 0;
    return windows.kernel32.GetLastError();
}

/// Set last Windows error code
pub fn SetLastError(error_code: DWORD) void {
    if (!is_windows) return;
    windows.kernel32.SetLastError(error_code);
}

/// Get a standard handle
pub fn GetStdHandle(std_handle: DWORD) WinApiError!HANDLE {
    if (!is_windows) return error.UnsupportedPlatform;

    const handle = windows.kernel32.GetStdHandle(std_handle);
    if (handle == INVALID_HANDLE_VALUE) {
        return error.InvalidHandle;
    }
    return handle;
}

/// Open an existing process
pub fn OpenProcess(access: DWORD, inherit: bool, pid: DWORD) WinApiError!HANDLE {
    if (!is_windows) return error.UnsupportedPlatform;

    const handle = windows.kernel32.OpenProcess(access, if (inherit) 1 else 0, pid);
    if (handle == null) {
        const err = GetLastError();
        if (err == ERROR_ACCESS_DENIED) return error.AccessDenied;
        return error.OperationFailed;
    }
    return handle.?;
}

/// Peek at a named pipe
pub fn PeekNamedPipe(handle: HANDLE) WinApiError!struct { available: DWORD, message_left: DWORD } {
    if (!is_windows) return error.UnsupportedPlatform;

    var available: DWORD = 0;
    var message_left: DWORD = 0;

    if (windows.kernel32.PeekNamedPipe(handle, null, 0, null, &available, &message_left) == 0) {
        const err = GetLastError();
        if (err == ERROR_BROKEN_PIPE) return error.BrokenPipe;
        return error.OperationFailed;
    }

    return .{ .available = available, .message_left = message_left };
}

/// Read from a file/pipe
pub fn ReadFile(handle: HANDLE, buffer: []u8, overlapped: ?*OVERLAPPED) WinApiError!DWORD {
    if (!is_windows) return error.UnsupportedPlatform;

    var bytes_read: DWORD = 0;
    if (windows.kernel32.ReadFile(
        handle,
        buffer.ptr,
        @intCast(buffer.len),
        &bytes_read,
        overlapped,
    ) == 0) {
        const err = GetLastError();
        if (err == ERROR_BROKEN_PIPE) return error.BrokenPipe;
        if (err == ERROR_IO_PENDING) return 0;
        return error.OperationFailed;
    }
    return bytes_read;
}

/// Terminate a process
pub fn TerminateProcess(handle: HANDLE, exit_code: DWORD) WinApiError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    if (windows.kernel32.TerminateProcess(handle, exit_code) == 0) {
        const err = GetLastError();
        if (err == ERROR_ACCESS_DENIED) return error.AccessDenied;
        return error.OperationFailed;
    }
}

/// Wait for a single object
pub fn WaitForSingleObject(handle: HANDLE, timeout: DWORD) WinApiError!DWORD {
    if (!is_windows) return error.UnsupportedPlatform;

    const result = windows.kernel32.WaitForSingleObject(handle, timeout);
    if (result == WAIT_FAILED) {
        return error.OperationFailed;
    }
    return result;
}

/// Wait for multiple objects
pub fn WaitForMultipleObjects(handles: []const HANDLE, wait_all: bool, timeout: DWORD) WinApiError!DWORD {
    if (!is_windows) return error.UnsupportedPlatform;

    const result = windows.kernel32.WaitForMultipleObjects(
        @intCast(handles.len),
        handles.ptr,
        if (wait_all) 1 else 0,
        timeout,
    );
    if (result == WAIT_FAILED) {
        return error.OperationFailed;
    }
    return result;
}

/// Write to a file/pipe
pub fn WriteFile(handle: HANDLE, buffer: []const u8, overlapped: ?*OVERLAPPED) WinApiError!DWORD {
    if (!is_windows) return error.UnsupportedPlatform;

    var bytes_written: DWORD = 0;
    if (windows.kernel32.WriteFile(
        handle,
        buffer.ptr,
        @intCast(buffer.len),
        &bytes_written,
        overlapped,
    ) == 0) {
        const err = GetLastError();
        if (err == ERROR_BROKEN_PIPE) return error.BrokenPipe;
        if (err == ERROR_IO_PENDING) return 0;
        return error.OperationFailed;
    }
    return bytes_written;
}

/// Get overlapped result
pub fn GetOverlappedResult(handle: HANDLE, overlapped: *OVERLAPPED, wait: bool) WinApiError!DWORD {
    if (!is_windows) return error.UnsupportedPlatform;

    var bytes_transferred: DWORD = 0;
    if (windows.kernel32.GetOverlappedResult(handle, overlapped, &bytes_transferred, if (wait) 1 else 0) == 0) {
        return error.OperationFailed;
    }
    return bytes_transferred;
}

/// Cancel IO operations
pub fn CancelIoEx(handle: HANDLE, overlapped: ?*OVERLAPPED) WinApiError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    if (windows.kernel32.CancelIoEx(handle, overlapped) == 0) {
        const err = GetLastError();
        if (err != ERROR_NOT_FOUND) {
            return error.OperationFailed;
        }
    }
}

const ERROR_NOT_FOUND: DWORD = 1168;

/// Create an event
pub fn CreateEvent(manual_reset: bool, initial_state: bool, name: ?[]const u8) WinApiError!HANDLE {
    if (!is_windows) return error.UnsupportedPlatform;

    var name_ptr: ?[*:0]const u16 = null;
    var name_buf: [256]u16 = undefined;

    if (name) |n| {
        const len = std.unicode.utf8ToUtf16Le(&name_buf, n) catch return error.InvalidParameter;
        name_buf[len] = 0;
        name_ptr = @ptrCast(&name_buf);
    }

    const handle = windows.kernel32.CreateEventW(
        null,
        if (manual_reset) 1 else 0,
        if (initial_state) 1 else 0,
        name_ptr,
    );

    if (handle == null) {
        return error.OperationFailed;
    }
    return handle.?;
}

/// Set an event
pub fn SetEvent(handle: HANDLE) WinApiError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    if (windows.kernel32.SetEvent(handle) == 0) {
        return error.OperationFailed;
    }
}

/// Reset an event
pub fn ResetEvent(handle: HANDLE) WinApiError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    if (windows.kernel32.ResetEvent(handle) == 0) {
        return error.OperationFailed;
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

test "constants defined" {
    try std.testing.expect(CREATE_NEW_CONSOLE > 0);
    try std.testing.expect(INFINITE == 0xFFFFFFFF);
    try std.testing.expect(WAIT_OBJECT_0 == 0);
    try std.testing.expect(STD_INPUT_HANDLE != 0);
}

test "process access constants" {
    try std.testing.expect(PROCESS_ALL_ACCESS > 0);
    try std.testing.expect(PROCESS_TERMINATE == 0x0001);
    try std.testing.expect(SYNCHRONIZE == 0x00100000);
}

test "pipe constants" {
    try std.testing.expect(PIPE_ACCESS_DUPLEX == 0x00000003);
    try std.testing.expect(PIPE_UNLIMITED_INSTANCES == 255);
}

test "error codes" {
    try std.testing.expect(ERROR_SUCCESS == 0);
    try std.testing.expect(ERROR_FILE_NOT_FOUND == 2);
    try std.testing.expect(ERROR_ACCESS_DENIED == 5);
}

test "GetCurrentProcess on Windows" {
    if (is_windows) {
        const handle = GetCurrentProcess();
        try std.testing.expect(handle != INVALID_HANDLE_VALUE);
    }
}

test "GetCurrentProcessId on Windows" {
    if (is_windows) {
        const pid = GetCurrentProcessId();
        try std.testing.expect(pid > 0);
    }
}
