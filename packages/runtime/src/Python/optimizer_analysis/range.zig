/// range - Range Analysis
/// Tracks integer value ranges for overflow detection and optimization

const std = @import("std");

// ============================================================================
// Range Analysis
// ============================================================================

/// Integer range
pub const IntRange = struct {
    min: i64,
    max: i64,
    is_constant: bool = false,

    /// Create unknown range
    pub fn unknown() IntRange {
        return .{ .min = std.math.minInt(i64), .max = std.math.maxInt(i64) };
    }

    /// Create constant range
    pub fn constant(value: i64) IntRange {
        return .{ .min = value, .max = value, .is_constant = true };
    }

    /// Create bounded range
    pub fn bounded(min: i64, max: i64) IntRange {
        return .{ .min = min, .max = max, .is_constant = min == max };
    }

    /// Join two ranges
    pub fn join(self: IntRange, other: IntRange) IntRange {
        return .{
            .min = @min(self.min, other.min),
            .max = @max(self.max, other.max),
            .is_constant = false,
        };
    }

    /// Intersect two ranges
    pub fn intersect(self: IntRange, other: IntRange) ?IntRange {
        const new_min = @max(self.min, other.min);
        const new_max = @min(self.max, other.max);
        if (new_min > new_max) return null;
        return .{
            .min = new_min,
            .max = new_max,
            .is_constant = new_min == new_max,
        };
    }

    /// Check if can overflow on addition
    pub fn canOverflowAdd(self: IntRange, other: IntRange) bool {
        // Check for positive overflow
        if (self.max > 0 and other.max > std.math.maxInt(i64) - self.max) return true;
        // Check for negative overflow
        if (self.min < 0 and other.min < std.math.minInt(i64) - self.min) return true;
        return false;
    }

    /// Add two ranges
    pub fn add(self: IntRange, other: IntRange) IntRange {
        return .{
            .min = self.min +| other.min,
            .max = self.max +| other.max,
            .is_constant = self.is_constant and other.is_constant,
        };
    }

    /// Multiply two ranges
    pub fn mul(self: IntRange, other: IntRange) IntRange {
        const products = [_]i64{
            self.min *| other.min,
            self.min *| other.max,
            self.max *| other.min,
            self.max *| other.max,
        };
        var min = products[0];
        var max = products[0];
        for (products[1..]) |p| {
            min = @min(min, p);
            max = @max(max, p);
        }
        return .{
            .min = min,
            .max = max,
            .is_constant = self.is_constant and other.is_constant,
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "int range arithmetic" {
    const r1 = IntRange.bounded(0, 10);
    const r2 = IntRange.bounded(5, 15);

    const joined = r1.join(r2);
    try std.testing.expectEqual(@as(i64, 0), joined.min);
    try std.testing.expectEqual(@as(i64, 15), joined.max);

    const intersected = r1.intersect(r2);
    try std.testing.expect(intersected != null);
    try std.testing.expectEqual(@as(i64, 5), intersected.?.min);
    try std.testing.expectEqual(@as(i64, 10), intersected.?.max);
}
