/// traceback/repeat - Repeated Line Handling
/// Mirrors cpython/Python/traceback.c
///
/// This module provides:
/// - Track repeated traceback entries
/// - Collapse duplicate consecutive entries
/// - Get/reset repeat count

const std = @import("std");

/// State for tracking repeated lines
const RepeatState = struct {
    last_filename: []const u8 = "",
    last_lineno: i32 = 0,
    last_name: []const u8 = "",
    repeat_count: usize = 0,
};

/// Thread-local repeat state
threadlocal var repeat_state: RepeatState = .{};

/// Check if current entry is same as last
pub fn checkRepeat(filename: []const u8, lineno: i32, name: []const u8) bool {
    if (std.mem.eql(u8, filename, repeat_state.last_filename) and
        lineno == repeat_state.last_lineno and
        std.mem.eql(u8, name, repeat_state.last_name))
    {
        repeat_state.repeat_count += 1;
        return true;
    }

    repeat_state.last_filename = filename;
    repeat_state.last_lineno = lineno;
    repeat_state.last_name = name;
    repeat_state.repeat_count = 0;
    return false;
}

/// Get repeat count and reset
pub fn getAndResetRepeatCount() usize {
    const count = repeat_state.repeat_count;
    repeat_state.repeat_count = 0;
    return count;
}

/// Reset repeat state
pub fn reset() void {
    repeat_state = .{};
}
