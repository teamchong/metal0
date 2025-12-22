/// Runtime slice operations for native codegen
/// Moves complex stepped slice logic from comptime (inline codegen) to runtime
/// This fixes compilation timeout caused by O(n^2) comptime expansion
const std = @import("std");

/// Error type for slice operations
pub const SliceError = error{
    ZeroStep,
    OutOfMemory,
};

/// Slice a string with step - handles negative indices, bounds, reverse iteration
/// Returns: owned []u8 slice (caller must free with allocator)
pub fn stringSliceWithStep(
    allocator: std.mem.Allocator,
    str: []const u8,
    start_opt: ?i64,
    end_opt: ?i64,
    step: i64,
) SliceError![]u8 {
    if (step == 0) return SliceError.ZeroStep;

    const len: i64 = @intCast(str.len);

    // Handle defaults based on step direction
    var start: i64 = start_opt orelse (if (step > 0) 0 else len - 1);
    var end: i64 = end_opt orelse (if (step > 0) len else -len - 1);

    // Handle negative indices
    if (start < 0) start = @max(0, len + start);
    if (end < 0) {
        const min_end: i64 = if (step < 0) -1 else 0;
        end = @max(min_end, len + end);
    }

    // Clamp to valid range
    start = @max(0, @min(start, len));
    if (step > 0) {
        end = @max(0, @min(end, len));
    } else {
        end = @max(-1, @min(end, len));
    }

    // Build result
    var result = std.ArrayListUnmanaged(u8){};

    if (step > 0) {
        const start_idx: usize = @intCast(start);
        const end_idx: usize = @intCast(end);
        const step_usize: usize = @intCast(step);
        var i: usize = start_idx;
        while (i < end_idx) : (i += step_usize) {
            result.append(allocator, str[i]) catch return SliceError.OutOfMemory;
        }
    } else {
        const step_neg: i64 = -step;
        var i: i64 = start;
        while (i > end) {
            const idx: usize = @intCast(i);
            result.append(allocator, str[idx]) catch return SliceError.OutOfMemory;
            i -= step_neg;
        }
    }

    return result.toOwnedSlice(allocator) catch SliceError.OutOfMemory;
}

/// Result wrapper for stepped slices - has .items field for iteration compatibility
pub fn SliceResult(comptime T: type) type {
    return struct {
        items: []T,

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            allocator.free(self.items);
        }
    };
}

/// Slice a typed array with step - for lists/arrays with known element type
/// Returns: SliceResult(T) with .items field for compatibility with codegen iteration
pub fn sliceWithStep(
    comptime T: type,
    allocator: std.mem.Allocator,
    items: []const T,
    start_opt: ?i64,
    end_opt: ?i64,
    step: i64,
) SliceError!SliceResult(T) {
    if (step == 0) return SliceError.ZeroStep;

    const len: i64 = @intCast(items.len);

    // Handle defaults based on step direction
    var start: i64 = start_opt orelse (if (step > 0) 0 else len - 1);
    var end: i64 = end_opt orelse (if (step > 0) len else -len - 1);

    // Handle negative indices
    if (start < 0) start = @max(0, len + start);
    if (end < 0) {
        const min_end: i64 = if (step < 0) -1 else 0;
        end = @max(min_end, len + end);
    }

    // Clamp to valid range
    start = @max(0, @min(start, len));
    if (step > 0) {
        end = @max(0, @min(end, len));
    } else {
        end = @max(-1, @min(end, len));
    }

    // Build result
    var result = std.ArrayListUnmanaged(T){};

    if (step > 0) {
        const start_idx: usize = @intCast(start);
        const end_idx: usize = @intCast(end);
        const step_usize: usize = @intCast(step);
        var i: usize = start_idx;
        while (i < end_idx) : (i += step_usize) {
            result.append(allocator, items[i]) catch return SliceError.OutOfMemory;
        }
    } else {
        const step_neg: i64 = -step;
        var i: i64 = start;
        while (i > end) {
            const idx: usize = @intCast(i);
            result.append(allocator, items[idx]) catch return SliceError.OutOfMemory;
            i -= step_neg;
        }
    }

    return SliceResult(T){ .items = result.toOwnedSlice(allocator) catch return SliceError.OutOfMemory };
}

/// Slice an ArrayListUnmanaged with step - accesses .items internally
/// Returns: SliceResult(T) for compatibility with codegen iteration
pub fn sliceArrayListWithStep(
    comptime T: type,
    allocator: std.mem.Allocator,
    list: std.ArrayListUnmanaged(T),
    start_opt: ?i64,
    end_opt: ?i64,
    step: i64,
) SliceError!SliceResult(T) {
    return sliceWithStep(T, allocator, list.items, start_opt, end_opt, step);
}

/// Generic slice for unknown types - uses runtime checks
/// This handles both fixed arrays and ArrayListUnmanaged
pub fn genericSliceWithStep(
    comptime T: type,
    allocator: std.mem.Allocator,
    container: anytype,
    start_opt: ?i64,
    end_opt: ?i64,
    step: i64,
) SliceError!SliceResult(T) {
    const Container = @TypeOf(container);
    const items: []const T = if (@hasField(Container, "items"))
        container.items
    else if (@typeInfo(Container) == .pointer)
        container
    else
        &container;

    return sliceWithStep(T, allocator, items, start_opt, end_opt, step);
}

test "stringSliceWithStep positive step" {
    const allocator = std.testing.allocator;
    const result = try stringSliceWithStep(allocator, "hello", 0, 5, 2);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hlo", result);
}

test "stringSliceWithStep negative step" {
    const allocator = std.testing.allocator;
    const result = try stringSliceWithStep(allocator, "hello", null, null, -1);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("olleh", result);
}

test "sliceWithStep positive step" {
    const allocator = std.testing.allocator;
    const arr = [_]i64{ 0, 1, 2, 3, 4 };
    const result = try sliceWithStep(i64, allocator, &arr, 0, 5, 2);
    defer allocator.free(result.items);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 0, 2, 4 }, result.items);
}

test "sliceWithStep negative step" {
    const allocator = std.testing.allocator;
    const arr = [_]i64{ 0, 1, 2, 3, 4 };
    const result = try sliceWithStep(i64, allocator, &arr, null, null, -1);
    defer allocator.free(result.items);
    try std.testing.expectEqualSlices(i64, &[_]i64{ 4, 3, 2, 1, 0 }, result.items);
}

test "sliceWithStep zero step error" {
    const allocator = std.testing.allocator;
    const arr = [_]i64{ 0, 1, 2 };
    const result = sliceWithStep(i64, allocator, &arr, 0, 3, 0);
    try std.testing.expectError(SliceError.ZeroStep, result);
}

/// Normalize a Python index to a valid usize for array access
/// Python semantics: negative index means from end, e.g., a[-1] is last element
/// If index is out of bounds, returns null (caller should handle IndexError)
pub fn normalizeIndex(index: i64, len: usize) ?usize {
    const len_i: i64 = @intCast(len);
    const actual_index: i64 = if (index < 0) len_i + index else index;
    if (actual_index < 0 or actual_index >= len_i) return null;
    return @intCast(actual_index);
}

/// Normalize index or panic with IndexError message
pub fn normalizeIndexOrError(index: i64, len: usize) usize {
    return normalizeIndex(index, len) orelse @panic("list index out of range");
}
