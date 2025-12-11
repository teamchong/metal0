/// Generic Hashing
/// Type-generic hash function
///
/// Provides a generic hashAny() function that dispatches to appropriate
/// hash functions based on Zig type information.

const std = @import("std");
const constants = @import("constants.zig");
const numeric = @import("numeric.zig");
const string = @import("string.zig");
const pointer = @import("pointer.zig");

const HashT = constants.HashT;

// ============================================================================
// Generic Object Hashing
// ============================================================================

/// Hash any Zig value (generic helper)
pub fn hashAny(value: anytype) HashT {
    const T = @TypeOf(value);

    return switch (@typeInfo(T)) {
        .int, .comptime_int => numeric.hashLong(@intCast(value)),
        .float, .comptime_float => numeric.hashDouble(@floatCast(value)),
        .bool => if (value) @as(HashT, 1) else @as(HashT, 0),
        .pointer => |ptr_info| {
            if (ptr_info.size == .Slice and ptr_info.child == u8) {
                return string.hashString(value);
            }
            return pointer.hashPointer(value);
        },
        .optional => if (value) |v| hashAny(v) else 0,
        else => 0, // Unhashable
    };
}
