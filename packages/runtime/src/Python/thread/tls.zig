/// tls - Thread Local Storage
/// Platform-specific TLS key management.

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Thread Local Storage Key
// ============================================================================

/// Thread-local storage key
pub const TLSKey = struct {
    key: if (builtin.os.tag == .windows)
        std.os.windows.DWORD
    else
        std.c.pthread_key_t,

    const Self = @This();

    pub fn create() !Self {
        if (builtin.os.tag == .windows) {
            const key = std.os.windows.kernel32.TlsAlloc();
            if (key == std.os.windows.TLS_OUT_OF_INDEXES) {
                return error.OutOfMemory;
            }
            return .{ .key = key };
        } else {
            var key: std.c.pthread_key_t = undefined;
            if (std.c.pthread_key_create(&key, null) != 0) {
                return error.OutOfMemory;
            }
            return .{ .key = key };
        }
    }

    pub fn delete(self: Self) void {
        if (builtin.os.tag == .windows) {
            _ = std.os.windows.kernel32.TlsFree(self.key);
        } else {
            _ = std.c.pthread_key_delete(self.key);
        }
    }

    pub fn get(self: Self) ?*anyopaque {
        if (builtin.os.tag == .windows) {
            const value = std.os.windows.kernel32.TlsGetValue(self.key);
            if (value == null and std.os.windows.kernel32.GetLastError() != .SUCCESS) {
                return null;
            }
            return value;
        } else {
            return std.c.pthread_getspecific(self.key);
        }
    }

    pub fn set(self: Self, value: ?*anyopaque) !void {
        if (builtin.os.tag == .windows) {
            if (std.os.windows.kernel32.TlsSetValue(self.key, value) == 0) {
                return error.Failed;
            }
        } else {
            if (std.c.pthread_setspecific(self.key, value) != 0) {
                return error.Failed;
            }
        }
    }
};
