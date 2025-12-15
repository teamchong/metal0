/// Equality operations for reducing monomorphization explosion
/// Uses PyValue as the universal comparison type - compiles ONCE per type, not per type-pair
const std = @import("std");
const PyValue = @import("../Objects/object.zig").PyValue;

/// Compare any two values via PyValue conversion
/// O(n) conversions + O(1) comparison instead of O(n²) inline comparisons
///
/// This is the key function for reducing assertion monomorphization:
/// - equalTuples(TypeA, TypeB) would create O(n²) instances for each type pair
/// - equalViaPyValue converts each type to PyValue (O(n)) then uses PyValue.eql (O(1))
pub fn equalViaPyValue(allocator: std.mem.Allocator, a: anytype, b: anytype) bool {
    const a_pv = PyValue.fromAlloc(allocator, a) catch return false;
    const b_pv = PyValue.fromAlloc(allocator, b) catch return false;
    return a_pv.eql(b_pv);
}

/// Fast path check - returns true if types support direct comparison without allocation
pub fn canCompareDirect(comptime T: type) bool {
    const info = @typeInfo(T);
    return info == .int or info == .comptime_int or
        info == .float or info == .comptime_float or
        info == .bool;
}

/// Compare two values with fast paths for primitives
/// Falls back to PyValue comparison for complex types
pub fn equalAny(allocator: std.mem.Allocator, a: anytype, b: anytype) bool {
    const A = @TypeOf(a);
    const B = @TypeOf(b);

    // Fast paths for same-type primitives (no allocation needed)
    if (A == B) {
        const info = @typeInfo(A);
        if (info == .int or info == .comptime_int) return a == b;
        if (info == .bool) return a == b;
        if (info == .float or info == .comptime_float) {
            // Handle NaN: in Python, NaN == NaN is False for IEEE, but same-object identity is True
            if (std.math.isNan(a) and std.math.isNan(b)) return true; // Same object identity
            return @abs(a - b) < 0.0001;
        }
        // Same-type slices - use mem.eql
        if (info == .pointer and info.pointer.size == .slice) {
            if (info.pointer.child == u8) {
                return std.mem.eql(u8, a, b);
            }
        }
    }

    // PyValue path for complex types (tuples, structs, unions, etc.)
    return equalViaPyValue(allocator, a, b);
}

test "equalViaPyValue - primitives" {
    const allocator = std.testing.allocator;

    // Integers
    try std.testing.expect(equalViaPyValue(allocator, @as(i64, 42), @as(i64, 42)));
    try std.testing.expect(!equalViaPyValue(allocator, @as(i64, 42), @as(i64, 43)));

    // Floats
    try std.testing.expect(equalViaPyValue(allocator, @as(f64, 3.14), @as(f64, 3.14)));

    // Booleans
    try std.testing.expect(equalViaPyValue(allocator, true, true));
    try std.testing.expect(!equalViaPyValue(allocator, true, false));
}

test "equalAny - fast paths" {
    const allocator = std.testing.allocator;

    // Same-type integers (fast path, no allocation)
    try std.testing.expect(equalAny(allocator, @as(i64, 42), @as(i64, 42)));

    // Same-type floats (fast path)
    try std.testing.expect(equalAny(allocator, @as(f64, 3.14), @as(f64, 3.14)));

    // Same-type booleans (fast path)
    try std.testing.expect(equalAny(allocator, true, true));

    // String slices (fast path)
    try std.testing.expect(equalAny(allocator, "hello", "hello"));
    try std.testing.expect(!equalAny(allocator, "hello", "world"));
}
