/// Tuple operations runtime helpers
/// Extracted from codegen to prevent comptime explosion from inline for over tuple fields
///
/// Problem: Each dynamic tuple index (t[i] where i is not constant) generated
/// `inline for (std.meta.fields(@TypeOf(__t)))` causing O(n²) monomorphization.
///
/// Solution: These helpers are compiled once per tuple type, called N times.
/// The inline for is still needed (Zig requires comptime field names), but it's
/// in a function that gets monomorphized once per tuple type, not once per access.
const std = @import("std");

/// Generic tuple operations that work with any tuple/struct type
/// Monomorphizes once per T type, not once per call site
///
/// Note: This assumes homogeneous tuples (all elements same type).
/// For heterogeneous tuples, the caller must ensure type compatibility.
pub fn TupleOps(comptime T: type) type {
    const fields = std.meta.fields(T);

    // Get the type of the first field (assumes homogeneous tuple)
    const ElementType = if (fields.len > 0) fields[0].type else void;

    return struct {
        pub const element_type = ElementType;
        pub const length = fields.len;

        /// Get element at runtime index
        /// The inline for is necessary because Zig requires comptime field names,
        /// but the function itself is compiled once per tuple type.
        pub fn get(tuple: T, index: usize) ElementType {
            inline for (fields, 0..) |f, fi| {
                if (fi == index) return @field(tuple, f.name);
            }
            // Index out of bounds
            unreachable;
        }

        /// Get element at runtime index with bounds checking
        pub fn getChecked(tuple: T, index: usize) ?ElementType {
            if (index >= fields.len) return null;
            inline for (fields, 0..) |f, fi| {
                if (fi == index) return @field(tuple, f.name);
            }
            unreachable;
        }

        /// Get element at negative index (Python semantics: -1 = last element)
        pub fn getWithNegative(tuple: T, index: i64) ElementType {
            const actual_index: usize = if (index < 0)
                @intCast(@as(i64, @intCast(fields.len)) + index)
            else
                @intCast(index);
            return get(tuple, actual_index);
        }

        /// Convert tuple to array (useful for slicing operations)
        /// This is done at comptime per tuple type, then the array can be used at runtime
        pub fn toArray(tuple: T) [fields.len]ElementType {
            var arr: [fields.len]ElementType = undefined;
            inline for (fields, 0..) |f, i| {
                arr[i] = @field(tuple, f.name);
            }
            return arr;
        }

        /// Get tuple length
        pub fn len() usize {
            return fields.len;
        }
    };
}

// Pre-instantiated for common tuple types to avoid repeated monomorphization
// These are rarely used directly - the generic version handles most cases

// Tests
test "TupleOps.get" {
    const tuple = .{ @as(i64, 10), @as(i64, 20), @as(i64, 30) };
    const Ops = TupleOps(@TypeOf(tuple));

    try std.testing.expectEqual(@as(i64, 10), Ops.get(tuple, 0));
    try std.testing.expectEqual(@as(i64, 20), Ops.get(tuple, 1));
    try std.testing.expectEqual(@as(i64, 30), Ops.get(tuple, 2));
}

test "TupleOps.getChecked" {
    const tuple = .{ @as(i64, 10), @as(i64, 20) };
    const Ops = TupleOps(@TypeOf(tuple));

    try std.testing.expectEqual(@as(?i64, 10), Ops.getChecked(tuple, 0));
    try std.testing.expectEqual(@as(?i64, 20), Ops.getChecked(tuple, 1));
    try std.testing.expectEqual(@as(?i64, null), Ops.getChecked(tuple, 2));
}

test "TupleOps.getWithNegative" {
    const tuple = .{ @as(i64, 10), @as(i64, 20), @as(i64, 30) };
    const Ops = TupleOps(@TypeOf(tuple));

    try std.testing.expectEqual(@as(i64, 30), Ops.getWithNegative(tuple, -1));
    try std.testing.expectEqual(@as(i64, 20), Ops.getWithNegative(tuple, -2));
    try std.testing.expectEqual(@as(i64, 10), Ops.getWithNegative(tuple, -3));
    try std.testing.expectEqual(@as(i64, 10), Ops.getWithNegative(tuple, 0));
}

test "TupleOps.toArray" {
    const tuple = .{ @as(i64, 10), @as(i64, 20), @as(i64, 30) };
    const Ops = TupleOps(@TypeOf(tuple));

    const arr = Ops.toArray(tuple);
    try std.testing.expectEqual(@as(i64, 10), arr[0]);
    try std.testing.expectEqual(@as(i64, 20), arr[1]);
    try std.testing.expectEqual(@as(i64, 30), arr[2]);
}

test "TupleOps.len" {
    const tuple = .{ @as(i64, 10), @as(i64, 20), @as(i64, 30) };
    const Ops = TupleOps(@TypeOf(tuple));

    try std.testing.expectEqual(@as(usize, 3), Ops.len());
}
