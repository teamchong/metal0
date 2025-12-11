/// Miscellaneous utility functions
const std = @import("std");

// Import exceptions
const exceptions = @import("exceptions.zig");
const PythonError = exceptions.PythonError;

/// Bounds-checked array list access for exception handling
/// Returns element at index or IndexError if out of bounds
pub fn arrayListGet(comptime T: type, list: std.ArrayList(T), index: i64) PythonError!T {
    const len: i64 = @intCast(list.items.len);

    // Handle negative indices (Python-style)
    const actual_index = if (index < 0) len + index else index;

    // Bounds check
    if (actual_index < 0 or actual_index >= len) {
        return PythonError.IndexError;
    }

    return list.items[@intCast(actual_index)];
}

/// Concatenate two arrays/slices - returns a new array with elements from both
/// This is Python list concatenation: [1,2] + [3,4] = [1,2,3,4]
pub inline fn concat(a: anytype, b: anytype) @TypeOf(a ++ b) {
    return a ++ b;
}
