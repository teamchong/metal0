/// Python floor division (//) operations
const std = @import("std");
const PyValue = @import("../Objects/object.zig").PyValue;

/// Python floor division (//) for unknown types at runtime
/// Returns i64 for integer types, f64 for float types
/// Two-Flow: Handles PyValue for uncertain types
pub fn pyFloorDiv(allocator: std.mem.Allocator, a: anytype, b: anytype) i64 {
    _ = allocator; // Note: allocator is kept for API compatibility
    return dispatchFloorDiv(a, b);
}

/// Internal dispatch for floor division - handles return type polymorphism
fn dispatchFloorDiv(a: anytype, b: anytype) i64 {
    const T = @TypeOf(a);
    const U = @TypeOf(b);
    const info_a = @typeInfo(T);
    const info_b = @typeInfo(U);

    // Two-Flow: Handle PyValue (uncertain type wrapper)
    if (T == PyValue) {
        if (U == PyValue) {
            const result = a.floordiv(b);
            return result.asInt();
        }
        // Mixed: PyValue // concrete type - extract and recurse
        return dispatchFloorDiv(a.asInt(), b);
    }

    // Handle Fraction and other types with floordiv method
    if (info_a == .@"struct") {
        if (@hasDecl(T, "floordiv")) {
            // Type has floordiv method - call it
            const result = a.floordiv(b);
            // Return as i64 (Fraction.floordiv returns Fraction, convert to int)
            if (@TypeOf(result) == i64) return result;
            if (@hasDecl(@TypeOf(result), "toInt")) return result.toInt();
            // Fallback - treat result as having numerator/denominator
            if (@hasField(@TypeOf(result), "numerator") and @hasField(@TypeOf(result), "denominator")) {
                return @divTrunc(result.numerator, result.denominator);
            }
            @compileError("floordiv result type not supported");
        }
    }
    if (info_b == .@"struct") {
        if (@hasDecl(U, "__rfloordiv__")) {
            const result = b.__rfloordiv__(a);
            if (@TypeOf(result) == i64) return result;
            if (@hasDecl(@TypeOf(result), "toInt")) return result.toInt();
            @compileError("__rfloordiv__ result type not supported");
        }
    }

    // For integers, use @divFloor
    if (info_a == .int or info_a == .comptime_int) {
        return @divFloor(@as(i64, a), @as(i64, b));
    }

    // For floats, use @floor(a / b) and convert to i64
    if (info_a == .float or info_a == .comptime_float) {
        return @intFromFloat(@floor(@as(f64, a) / @as(f64, b)));
    }

    // Fallback for other types
    return @divFloor(@as(i64, a), @as(i64, b));
}
