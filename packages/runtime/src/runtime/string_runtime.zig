/// String runtime operations for Python semantics
const std = @import("std");

/// Split string on whitespace (Python str.split() with no args)
/// Returns ArrayList of string slices, removes empty strings
pub fn stringSplitWhitespace(text: []const u8, allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    var result = std.ArrayList([]const u8){};

    // Split on any whitespace, skip empty parts (like Python's split())
    var iter = std.mem.tokenizeAny(u8, text, " \t\n\r\x0c\x0b");
    while (iter.next()) |part| {
        try result.append(allocator, part);
    }

    return result;
}

/// Repeat string n times (Python str * n or bytes * n)
/// Accepts both []const u8 and PyBytes for bytes literal support
pub fn strRepeat(allocator: std.mem.Allocator, s: anytype, n: usize) []const u8 {
    // Extract the actual slice from either []const u8, PyBytes, or string literal pointer at comptime type check
    const T = @TypeOf(s);
    const actual_slice: []const u8 = if (T == []const u8)
        s
    else if (@typeInfo(T) == .@"struct" and @hasField(T, "data"))
        // PyBytes has a .data field
        s.data
    else if (@typeInfo(T) == .pointer and @typeInfo(T).pointer.size == .one) blk: {
        // Pointer to array (string literal like *const [N:0]u8) - coerce to slice
        const child_info = @typeInfo(@typeInfo(T).pointer.child);
        if (child_info == .array and child_info.array.child == u8) {
            break :blk s;
        } else {
            @compileError("strRepeat expects []const u8, PyBytes, or string literal, got " ++ @typeName(T));
        }
    } else @compileError("strRepeat expects []const u8, PyBytes, or string literal, got " ++ @typeName(T));

    if (n == 0) return "";
    if (n == 1) return actual_slice;

    const result = allocator.alloc(u8, actual_slice.len * n) catch return "";
    for (0..n) |i| {
        @memcpy(result[i * actual_slice.len ..][0..actual_slice.len], actual_slice);
    }
    return result;
}
