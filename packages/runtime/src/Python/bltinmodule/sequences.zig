/// sequences - Sequence Built-in Functions
/// len(), all(), any(), sorted() implementations.

const std = @import("std");
const errors = @import("../errors.zig");
const conversions = @import("conversions.zig");
const pyobject_utils = @import("../../runtime/pyobject_utils.zig");
const cpython = @import("../../cpython.zig");
const PyValue = @import("../../Objects/object.zig").PyValue;

// ============================================================================
// Sequence Functions
// ============================================================================

/// Get length of sequence
/// Mirrors: builtin len()
/// Returns usize directly (not error union) for codegen compatibility
pub fn len_builtin(value: anytype) usize {
    const T = @TypeOf(value);

    // Handle PyValue (Two-Flow type system)
    if (T == PyValue) {
        return switch (value) {
            .list => |list| list.items.len,
            .tuple => |tuple| tuple.len,
            .string => |s| s.len,
            .bytes => |b| b.data.len,
            else => 0,
        };
    }

    return switch (@typeInfo(T)) {
        .pointer => |ptr_info| {
            if (ptr_info.size == .slice) {
                return value.len;
            }
            if (ptr_info.child == u8) {
                // C-string
                return std.mem.len(value);
            }
            // Check if this is a *PyObject (from runtime.eval)
            if (ptr_info.child == cpython.PyObject) {
                return pyobject_utils.pyLen(value);
            }
            return 0; // Fallback for non-len types
        },
        .array => |arr_info| arr_info.len,
        .@"struct" => |struct_info| {
            // Handle structs with .items field (ArrayList-like)
            if (@hasField(T, "items")) {
                return value.items.len;
            }
            // Handle structs with .len field
            if (@hasField(T, "len")) {
                return value.len;
            }
            return struct_info.fields.len; // Tuple-like struct
        },
        .@"union" => |union_info| {
            // Handle tagged unions (like PyValue) at comptime
            _ = union_info;
            if (T == PyValue) {
                return switch (value) {
                    .list => |list| list.items.len,
                    .tuple => |tuple| tuple.len,
                    .string => |s| s.len,
                    .bytes => |b| b.data.len,
                    else => 0,
                };
            }
            return 0;
        },
        else => 0, // Fallback
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
