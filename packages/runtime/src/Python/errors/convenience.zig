/// convenience - Convenience Error Functions
/// Mirrors cpython/Python/errors.c convenience functions
///
/// This module provides high-level convenience functions for common error types.

const std = @import("std");
const core_api = @import("core_api.zig");
const formatting = @import("formatting.zig");

const setString = core_api.setString;
const setNone = core_api.setNone;
const format = formatting.format;

/// Set TypeError for bad argument
/// Mirrors: PyErr_BadArgument
pub fn badArgument() void {
    setString("TypeError", "bad argument type for built-in operation");
}

/// Set MemoryError
/// Mirrors: PyErr_NoMemory
pub fn noMemory() void {
    setNone("MemoryError");
}

/// Set error from errno
/// Mirrors: PyErr_SetFromErrno
pub fn setFromErrno(exception_type: []const u8) void {
    const errno_val = std.c.getErrno();
    const message = std.c.strerror(errno_val);
    const msg_slice: []const u8 = std.mem.sliceTo(message, 0);
    format(exception_type, "[Errno {d}] {s}", .{ @intFromEnum(errno_val), msg_slice });
}

/// Set error from errno with filename
/// Mirrors: PyErr_SetFromErrnoWithFilename
pub fn setFromErrnoWithFilename(exception_type: []const u8, filename: []const u8) void {
    const errno_val = std.c.getErrno();
    const message = std.c.strerror(errno_val);
    const msg_slice: []const u8 = std.mem.sliceTo(message, 0);
    format(exception_type, "[Errno {d}] {s}: '{s}'", .{ @intFromEnum(errno_val), msg_slice, filename });
}

/// Set ModuleNotFoundError
/// Mirrors: _PyErr_SetModuleNotFoundError
pub fn setModuleNotFoundError(module_name: []const u8) void {
    format("ModuleNotFoundError", "No module named '{s}'", .{module_name});
}

/// Set ImportError with details
/// Mirrors: PyErr_SetImportError
pub fn setImportError(msg: []const u8, name: ?[]const u8, path: ?[]const u8) void {
    _ = path;
    if (name) |n| {
        format("ImportError", "{s} (name={s})", .{ msg, n });
    } else {
        setString("ImportError", msg);
    }
}

/// Bad internal call error
/// Mirrors: _PyErr_BadInternalCall
pub fn badInternalCall(filename: []const u8, lineno: i32) void {
    format("SystemError", "{s}:{d}: bad argument to internal function", .{ filename, lineno });
}
