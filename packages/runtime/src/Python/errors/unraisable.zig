/// unraisable - Unraisable Exception Handling
/// Mirrors cpython/Python/errors.c unraisable exception functions
///
/// This module handles exceptions that cannot be propagated normally,
/// such as those occurring in __del__ methods or finalizers.

const std = @import("std");
const thread_state_mod = @import("thread_state.zig");
const core_api = @import("core_api.zig");
const formatting = @import("formatting.zig");

const getThreadState = thread_state_mod.getThreadState;
const clear = core_api.clear;

/// Buffer for formatted unraisable messages (shared with formatting)
extern threadlocal var format_buffer: [4096]u8;

/// Write unraisable exception info (for exceptions in __del__, etc.)
/// Mirrors: PyErr_WriteUnraisable
pub fn writeUnraisable(obj_repr: ?[]const u8) void {
    const tstate = getThreadState();
    if (tstate.current_exception) |exc| {
        const stderr = std.io.getStdErr().writer();
        if (obj_repr) |obj| {
            stderr.print("Exception ignored in: {s}\n", .{obj}) catch {};
        }
        if (exc.traceback) |tb| {
            stderr.print("{s}", .{tb}) catch {};
        }
        stderr.print("{s}: {s}\n", .{ exc.type_name, exc.message }) catch {};
    }
    clear();
}

/// Format unraisable exception
/// Mirrors: PyErr_FormatUnraisable
pub fn formatUnraisable(comptime fmt: []const u8, args: anytype) void {
    const obj_repr = std.fmt.bufPrint(&format_buffer, fmt, args) catch &format_buffer;
    writeUnraisable(obj_repr);
}
