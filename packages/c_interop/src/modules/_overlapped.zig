//! Python '_overlapped' module - Windows Overlapped I/O support
//!
//! Low-level support for overlapped I/O operations on Windows.
//! Used by asyncio for Windows-specific asynchronous I/O.
//!
//! Mirrors: CPython Modules/overlapped.c

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

pub const OverlappedError = error{
    UnsupportedPlatform,
    InvalidHandle,
    OperationFailed,
    OperationPending,
    OperationCanceled,
    OutOfMemory,
};

// ============================================================================
// Types
// ============================================================================

pub const HANDLE = if (is_windows) windows.HANDLE else *anyopaque;
pub const DWORD = u32;
pub const ULONG_PTR = usize;
pub const BOOL = i32;

pub const INVALID_HANDLE_VALUE: HANDLE = if (is_windows)
    windows.INVALID_HANDLE_VALUE
else
    @ptrFromInt(~@as(usize, 0));

// ============================================================================
// Constants
// ============================================================================

pub const INFINITE: DWORD = 0xFFFFFFFF;
pub const ERROR_SUCCESS: DWORD = 0;
pub const ERROR_IO_PENDING: DWORD = 997;
pub const ERROR_IO_INCOMPLETE: DWORD = 996;
pub const ERROR_OPERATION_ABORTED: DWORD = 995;
pub const ERROR_HANDLE_EOF: DWORD = 38;

// IOCP constants
pub const INVALID_SOCKET: usize = ~@as(usize, 0);

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

pub const OVERLAPPED_ENTRY = extern struct {
    lpCompletionKey: ULONG_PTR,
    lpOverlapped: *OVERLAPPED,
    Internal: usize,
    dwNumberOfBytesTransferred: DWORD,
};

pub const WSABUF = extern struct {
    len: u32,
    buf: [*]u8,
};

// ============================================================================
// Overlapped Object
// ============================================================================

/// Overlapped I/O operation wrapper
pub const Overlapped = struct {
    const Self = @This();

    overlapped: OVERLAPPED = .{},
    handle: ?HANDLE = null,
    buffer: ?[]u8 = null,
    pending: bool = false,
    error_code: DWORD = 0,
    bytes_transferred: DWORD = 0,

    pub fn init() Self {
        return Self{};
    }

    /// Get the result of an overlapped operation
    pub fn getResult(self: *Self, wait: bool) OverlappedError!DWORD {
        if (!is_windows) return error.UnsupportedPlatform;

        if (self.handle == null) return error.InvalidHandle;

        var bytes_transferred: DWORD = 0;
        if (windows.kernel32.GetOverlappedResult(
            self.handle.?,
            &self.overlapped,
            &bytes_transferred,
            if (wait) 1 else 0,
        ) == 0) {
            const err = windows.kernel32.GetLastError();
            if (err == ERROR_IO_INCOMPLETE or err == ERROR_IO_PENDING) {
                return error.OperationPending;
            }
            if (err == ERROR_OPERATION_ABORTED) {
                return error.OperationCanceled;
            }
            return error.OperationFailed;
        }

        self.bytes_transferred = bytes_transferred;
        self.pending = false;
        return bytes_transferred;
    }

    /// Cancel the overlapped operation
    pub fn cancel(self: *Self) OverlappedError!void {
        if (!is_windows) return error.UnsupportedPlatform;

        if (self.handle == null) return error.InvalidHandle;

        if (windows.kernel32.CancelIoEx(self.handle.?, &self.overlapped) == 0) {
            const err = windows.kernel32.GetLastError();
            if (err != 1168) { // ERROR_NOT_FOUND
                return error.OperationFailed;
            }
        }
        self.pending = false;
    }
};

// ============================================================================
// I/O Completion Port Functions
// ============================================================================

/// Create an I/O completion port
pub fn CreateIoCompletionPort(
    file_handle: ?HANDLE,
    existing_port: ?HANDLE,
    completion_key: ULONG_PTR,
    num_threads: DWORD,
) OverlappedError!HANDLE {
    if (!is_windows) return error.UnsupportedPlatform;

    const handle = windows.kernel32.CreateIoCompletionPort(
        file_handle orelse INVALID_HANDLE_VALUE,
        existing_port,
        completion_key,
        num_threads,
    );

    if (handle == null) {
        return error.OperationFailed;
    }

    return handle.?;
}

/// Post a completion status to an I/O completion port
pub fn PostQueuedCompletionStatus(
    port: HANDLE,
    bytes_transferred: DWORD,
    completion_key: ULONG_PTR,
    overlapped: ?*OVERLAPPED,
) OverlappedError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    if (windows.kernel32.PostQueuedCompletionStatus(
        port,
        bytes_transferred,
        completion_key,
        overlapped,
    ) == 0) {
        return error.OperationFailed;
    }
}

/// Get a completion status from an I/O completion port
pub fn GetQueuedCompletionStatus(
    port: HANDLE,
    timeout: DWORD,
) OverlappedError!struct {
    bytes_transferred: DWORD,
    completion_key: ULONG_PTR,
    overlapped: ?*OVERLAPPED,
} {
    if (!is_windows) return error.UnsupportedPlatform;

    var bytes_transferred: DWORD = 0;
    var completion_key: ULONG_PTR = 0;
    var overlapped: ?*OVERLAPPED = null;

    if (windows.kernel32.GetQueuedCompletionStatus(
        port,
        &bytes_transferred,
        &completion_key,
        &overlapped,
        timeout,
    ) == 0) {
        const err = windows.kernel32.GetLastError();
        if (err == windows.WAIT_TIMEOUT) {
            return .{ .bytes_transferred = 0, .completion_key = 0, .overlapped = null };
        }
        return error.OperationFailed;
    }

    return .{
        .bytes_transferred = bytes_transferred,
        .completion_key = completion_key,
        .overlapped = overlapped,
    };
}

/// Get multiple completion statuses
pub fn GetQueuedCompletionStatusEx(
    port: HANDLE,
    entries: []OVERLAPPED_ENTRY,
    timeout: DWORD,
    alertable: bool,
) OverlappedError!u32 {
    if (!is_windows) return error.UnsupportedPlatform;

    var num_entries: u32 = 0;

    if (windows.kernel32.GetQueuedCompletionStatusEx(
        port,
        entries.ptr,
        @intCast(entries.len),
        &num_entries,
        timeout,
        if (alertable) 1 else 0,
    ) == 0) {
        const err = windows.kernel32.GetLastError();
        if (err == windows.WAIT_TIMEOUT) {
            return 0;
        }
        return error.OperationFailed;
    }

    return num_entries;
}

// ============================================================================
// File I/O Functions
// ============================================================================

/// Read from a file handle asynchronously
pub fn ReadFile(
    handle: HANDLE,
    buffer: []u8,
    overlapped: *OVERLAPPED,
) OverlappedError!DWORD {
    if (!is_windows) return error.UnsupportedPlatform;

    var bytes_read: DWORD = 0;

    if (windows.kernel32.ReadFile(
        handle,
        buffer.ptr,
        @intCast(buffer.len),
        &bytes_read,
        overlapped,
    ) == 0) {
        const err = windows.kernel32.GetLastError();
        if (err == ERROR_IO_PENDING) {
            return error.OperationPending;
        }
        if (err == ERROR_HANDLE_EOF) {
            return 0;
        }
        return error.OperationFailed;
    }

    return bytes_read;
}

/// Write to a file handle asynchronously
pub fn WriteFile(
    handle: HANDLE,
    buffer: []const u8,
    overlapped: *OVERLAPPED,
) OverlappedError!DWORD {
    if (!is_windows) return error.UnsupportedPlatform;

    var bytes_written: DWORD = 0;

    if (windows.kernel32.WriteFile(
        handle,
        buffer.ptr,
        @intCast(buffer.len),
        &bytes_written,
        overlapped,
    ) == 0) {
        const err = windows.kernel32.GetLastError();
        if (err == ERROR_IO_PENDING) {
            return error.OperationPending;
        }
        return error.OperationFailed;
    }

    return bytes_written;
}

// ============================================================================
// Named Pipe Functions
// ============================================================================

/// Connect to a named pipe asynchronously
pub fn ConnectNamedPipe(handle: HANDLE, overlapped: *OVERLAPPED) OverlappedError!bool {
    if (!is_windows) return error.UnsupportedPlatform;

    if (windows.kernel32.ConnectNamedPipe(handle, overlapped) == 0) {
        const err = windows.kernel32.GetLastError();
        if (err == ERROR_IO_PENDING) {
            return false;
        }
        if (err == 535) { // ERROR_PIPE_CONNECTED
            return true;
        }
        return error.OperationFailed;
    }

    return true;
}

// ============================================================================
// Event Functions
// ============================================================================

/// Create an event for overlapped I/O
pub fn CreateEvent(manual_reset: bool, initial_state: bool) OverlappedError!HANDLE {
    if (!is_windows) return error.UnsupportedPlatform;

    const handle = windows.kernel32.CreateEventW(
        null,
        if (manual_reset) 1 else 0,
        if (initial_state) 1 else 0,
        null,
    );

    if (handle == null) {
        return error.OperationFailed;
    }

    return handle.?;
}

/// Reset an event
pub fn ResetEvent(handle: HANDLE) OverlappedError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    if (windows.kernel32.ResetEvent(handle) == 0) {
        return error.OperationFailed;
    }
}

/// Set an event
pub fn SetEvent(handle: HANDLE) OverlappedError!void {
    if (!is_windows) return error.UnsupportedPlatform;

    if (windows.kernel32.SetEvent(handle) == 0) {
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

test "error constants" {
    try std.testing.expectEqual(@as(DWORD, 0), ERROR_SUCCESS);
    try std.testing.expectEqual(@as(DWORD, 997), ERROR_IO_PENDING);
    try std.testing.expectEqual(@as(DWORD, 995), ERROR_OPERATION_ABORTED);
}

test "OVERLAPPED struct size" {
    // OVERLAPPED should be properly sized
    try std.testing.expect(@sizeOf(OVERLAPPED) >= 20);
}

test "Overlapped object init" {
    var ol = Overlapped.init();
    try std.testing.expect(!ol.pending);
    try std.testing.expectEqual(@as(DWORD, 0), ol.error_code);
}

test "CreateIoCompletionPort on Windows" {
    if (is_windows) {
        // Create a standalone IOCP
        const port = CreateIoCompletionPort(null, null, 0, 0) catch |err| {
            // May fail in restricted environments
            if (err == error.OperationFailed) return;
            return err;
        };
        defer windows.kernel32.CloseHandle(port);
    }
}
