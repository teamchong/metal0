/// Python floor division (//) operations
const std = @import("std");
const PyValue = @import("../Objects/object.zig").PyValue;

/// Python floor division (//) for unknown types at runtime
/// Returns i64 for integer types, f64 for float types
/// Two-Flow: Handles PyValue for uncertain types
pub fn pyFloorDiv(_: std.mem.Allocator, a: anytype, b: anytype) i64 {
    const T = @TypeOf(a);
    const info = @typeInfo(T);

    // Two-Flow: Handle PyValue (uncertain type wrapper)
    if (T == PyValue) {
        const U = @TypeOf(b);
        if (U == PyValue) {
            const result = a.floordiv(b);
            return result.asInt();
        }
        // Mixed: PyValue // concrete type - extract and recurse
        return pyFloorDiv(undefined, a.asInt(), b);
    }

    // For integers, use @divFloor
    if (info == .int or info == .comptime_int) {
        return @divFloor(@as(i64, a), @as(i64, b));
    }

    // For floats, use @floor(a / b) and convert to i64
    if (info == .float or info == .comptime_float) {
        return @intFromFloat(@floor(@as(f64, a) / @as(f64, b)));
    }

    // Fallback for other types
    return @divFloor(@as(i64, a), @as(i64, b));
}
