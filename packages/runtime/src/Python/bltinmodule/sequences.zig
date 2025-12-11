/// sequences - Sequence Built-in Functions
/// len(), all(), any(), sorted() implementations.

const std = @import("std");
const errors = @import("../errors.zig");
const conversions = @import("conversions.zig");

// ============================================================================
// Sequence Functions
// ============================================================================

/// Get length of sequence
/// Mirrors: builtin len()
pub fn len_builtin(value: anytype) !usize {
    const T = @TypeOf(value);
    return switch (@typeInfo(T)) {
        .pointer => |ptr_info| {
            if (ptr_info.size == .Slice) {
                return value.len;
            }
            if (ptr_info.child == u8) {
                // C-string
                return std.mem.len(value);
            }
            errors.setString("TypeError", "object has no len()");
            return error.TypeError;
        },
        .array => |arr_info| arr_info.len,
        else => {
            errors.setString("TypeError", "object has no len()");
            return error.TypeError;
        },
    };
}

/// Check if all elements are true
/// Mirrors: builtin all()
pub fn all_builtin(values: anytype) bool {
    for (values) |v| {
        if (!conversions.bool_builtin(v)) return false;
    }
    return true;
}

/// Check if any element is true
/// Mirrors: builtin any()
pub fn any_builtin(values: anytype) bool {
    for (values) |v| {
        if (conversions.bool_builtin(v)) return true;
    }
    return false;
}

/// Sort a slice in-place
/// Mirrors: builtin sorted() - but mutates
pub fn sorted_builtin(comptime T: type, items: []T, reverse: bool) void {
    if (reverse) {
        std.mem.sort(T, items, {}, std.sort.desc(T));
    } else {
        std.mem.sort(T, items, {}, std.sort.asc(T));
    }
}

// ============================================================================
// Tests
// ============================================================================

test "len function" {
    const arr = [_]i32{ 1, 2, 3, 4, 5 };
    try std.testing.expectEqual(@as(usize, 5), try len_builtin(&arr));
    try std.testing.expectEqual(@as(usize, 5), try len_builtin("hello"));
}

test "all and any" {
    const all_true = [_]bool{ true, true, true };
    const some_false = [_]bool{ true, false, true };

    try std.testing.expect(all_builtin(&all_true));
    try std.testing.expect(!all_builtin(&some_false));
    try std.testing.expect(any_builtin(&some_false));
}
