//! Version Range (VersionSet) implementation for PubGrub
//!
//! A Range is a set of versions represented as a union of non-overlapping intervals.
//! Each interval is either bounded or unbounded on either end.
//!
//! Examples:
//! - ">=1.0.0,<2.0.0" -> [1.0.0, 2.0.0)
//! - ">=1.0.0" -> [1.0.0, ∞)
//! - "!=1.5.0" -> (-∞, 1.5.0) ∪ (1.5.0, ∞)

const std = @import("std");
const Version = @import("version.zig").Version;

/// Bound type for interval endpoints
pub const Bound = union(enum) {
    /// Unbounded (infinity)
    unbounded: void,
    /// Inclusive bound [v
    included: Version,
    /// Exclusive bound (v
    excluded: Version,

    pub fn deinit(self: *Bound, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .unbounded => {},
            .included => |*v| v.deinit(allocator),
            .excluded => |*v| v.deinit(allocator),
        }
    }

    pub fn clone(self: Bound, allocator: std.mem.Allocator) !Bound {
        return switch (self) {
            .unbounded => .unbounded,
            .included => |v| .{ .included = try v.clone(allocator) },
            .excluded => |v| .{ .excluded = try v.clone(allocator) },
        };
    }

    /// Check if bound is unbounded
    pub fn isUnbounded(self: Bound) bool {
        return self == .unbounded;
    }

    /// Get the version if bounded
    pub fn version(self: Bound) ?Version {
        return switch (self) {
            .unbounded => null,
            .included => |v| v,
            .excluded => |v| v,
        };
    }

    /// Check if version satisfies this lower bound
    pub fn satisfiesLower(self: Bound, v: Version) bool {
        return switch (self) {
            .unbounded => true,
            .included => |bound| v.greaterThanOrEqual(bound),
            .excluded => |bound| v.greaterThan(bound),
        };
    }

    /// Check if version satisfies this upper bound
    pub fn satisfiesUpper(self: Bound, v: Version) bool {
        return switch (self) {
            .unbounded => true,
            .included => |bound| v.lessThanOrEqual(bound),
            .excluded => |bound| v.lessThan(bound),
        };
    }
};

/// An interval [lower, upper)
pub const Interval = struct {
    lower: Bound,
    upper: Bound,

    pub fn deinit(self: *Interval, allocator: std.mem.Allocator) void {
        self.lower.deinit(allocator);
        self.upper.deinit(allocator);
    }

    pub fn clone(self: Interval, allocator: std.mem.Allocator) !Interval {
        return .{
            .lower = try self.lower.clone(allocator),
            .upper = try self.upper.clone(allocator),
        };
    }

    /// Check if version is contained in this interval
    pub fn contains(self: Interval, v: Version) bool {
        return self.lower.satisfiesLower(v) and self.upper.satisfiesUpper(v);
    }

    /// Check if interval is empty
    pub fn isEmpty(self: Interval) bool {
        const lower_v = self.lower.version() orelse return false;
        const upper_v = self.upper.version() orelse return false;

        const cmp = lower_v.order(upper_v);
        if (cmp == .gt) return true;
        if (cmp == .eq) {
            // [v, v] is not empty, but (v, v], [v, v), (v, v) are
            const lower_incl = self.lower == .included;
            const upper_incl = self.upper == .included;
            return !(lower_incl and upper_incl);
        }
        return false;
    }

    /// Check if two intervals overlap
    pub fn overlaps(self: Interval, other: Interval) bool {
        // Check if self.lower < other.upper and other.lower < self.upper
        const self_lower_v = self.lower.version();
        const self_upper_v = self.upper.version();
        const other_lower_v = other.lower.version();
        const other_upper_v = other.upper.version();

        // If both have lower bounds, check other.upper > self.lower
        if (self_lower_v != null and other_upper_v != null) {
            const cmp = self_lower_v.?.order(other_upper_v.?);
            if (cmp == .gt) return false;
            if (cmp == .eq) {
                // Overlap only if both are inclusive
                if (!(self.lower == .included and other.upper == .included)) return false;
            }
        }

        // Check self.upper > other.lower
        if (other_lower_v != null and self_upper_v != null) {
            const cmp = other_lower_v.?.order(self_upper_v.?);
            if (cmp == .gt) return false;
            if (cmp == .eq) {
                if (!(other.lower == .included and self.upper == .included)) return false;
            }
        }

        return true;
    }

    /// Check if this interval is adjacent to another (can be merged)
    pub fn adjacent(self: Interval, other: Interval) bool {
        // self and other are adjacent if self.upper == other.lower and one is inclusive
        const self_upper_v = self.upper.version() orelse return false;
        const other_lower_v = other.lower.version() orelse return false;

        if (!self_upper_v.eql(other_lower_v)) return false;

        // They're adjacent if at least one endpoint includes the boundary
        return (self.upper == .included or other.lower == .included);
    }
};

/// A set of versions as a union of disjoint intervals
/// Invariant: intervals are sorted and non-overlapping
pub const Range = struct {
    intervals: std.ArrayList(Interval),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Range {
        return .{
            .intervals = std.ArrayList(Interval){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Range) void {
        for (self.intervals.items) |*interval| {
            interval.deinit(self.allocator);
        }
        self.intervals.deinit(self.allocator);
    }

    /// Create an empty range (no versions)
    pub fn empty(allocator: std.mem.Allocator) Range {
        return Range.init(allocator);
    }

    /// Create a full range (all versions)
    pub fn full(allocator: std.mem.Allocator) !Range {
        var range = Range.init(allocator);
        try range.intervals.append(allocator, .{
            .lower = .unbounded,
            .upper = .unbounded,
        });
        return range;
    }

    /// Create a singleton range containing exactly one version
    pub fn singleton(allocator: std.mem.Allocator, v: Version) !Range {
        var range = Range.init(allocator);
        const cloned = try v.clone(allocator);
        const cloned2 = try v.clone(allocator);
        try range.intervals.append(allocator, .{
            .lower = .{ .included = cloned },
            .upper = .{ .included = cloned2 },
        });
        return range;
    }

    /// Create range from specifier: >=v
    pub fn greaterThanOrEqual(allocator: std.mem.Allocator, v: Version) !Range {
        var range = Range.init(allocator);
        try range.intervals.append(allocator, .{
            .lower = .{ .included = try v.clone(allocator) },
            .upper = .unbounded,
        });
        return range;
    }

    /// Create range from specifier: >v
    pub fn greaterThan(allocator: std.mem.Allocator, v: Version) !Range {
        var range = Range.init(allocator);
        try range.intervals.append(allocator, .{
            .lower = .{ .excluded = try v.clone(allocator) },
            .upper = .unbounded,
        });
        return range;
    }

    /// Create range from specifier: <=v
    pub fn lessThanOrEqual(allocator: std.mem.Allocator, v: Version) !Range {
        var range = Range.init(allocator);
        try range.intervals.append(allocator, .{
            .lower = .unbounded,
            .upper = .{ .included = try v.clone(allocator) },
        });
        return range;
    }

    /// Create range from specifier: <v
    pub fn lessThan(allocator: std.mem.Allocator, v: Version) !Range {
        var range = Range.init(allocator);
        try range.intervals.append(allocator, .{
            .lower = .unbounded,
            .upper = .{ .excluded = try v.clone(allocator) },
        });
        return range;
    }

    /// Check if range contains a specific version
    pub fn contains(self: Range, v: Version) bool {
        for (self.intervals.items) |interval| {
            if (interval.contains(v)) return true;
        }
        return false;
    }

    /// Check if range is empty (no versions)
    pub fn isEmpty(self: Range) bool {
        return self.intervals.items.len == 0;
    }

    /// Check if two ranges are equal
    pub fn eql(self: Range, other: Range) bool {
        if (self.intervals.items.len != other.intervals.items.len) return false;
        for (self.intervals.items, other.intervals.items) |a, b| {
            // Compare bounds
            if (!boundsEqual(a.lower, b.lower)) return false;
            if (!boundsEqual(a.upper, b.upper)) return false;
        }
        return true;
    }

    /// Clone this range
    pub fn clone(self: Range) !Range {
        var result = Range.init(self.allocator);
        for (self.intervals.items) |interval| {
            try result.intervals.append(self.allocator, try interval.clone(self.allocator));
        }
        return result;
    }

    /// Compute the complement of this range
    pub fn complement(self: Range) !Range {
        var result = Range.init(self.allocator);

        if (self.isEmpty()) {
            // Complement of empty is full
            try result.intervals.append(self.allocator, .{
                .lower = .unbounded,
                .upper = .unbounded,
            });
            return result;
        }

        var prev_upper: Bound = .unbounded;

        for (self.intervals.items) |interval| {
            // Gap before this interval becomes an interval in complement
            const new_upper: Bound = switch (interval.lower) {
                .unbounded => continue, // No gap before unbounded lower
                .included => |v| .{ .excluded = try v.clone(self.allocator) },
                .excluded => |v| .{ .included = try v.clone(self.allocator) },
            };

            // Only add if there's actually a gap
            if (prev_upper != .unbounded or new_upper.version() != null) {
                const new_interval = Interval{
                    .lower = try prev_upper.clone(self.allocator),
                    .upper = new_upper,
                };
                if (!new_interval.isEmpty()) {
                    try result.intervals.append(self.allocator, new_interval);
                }
            }

            prev_upper = switch (interval.upper) {
                .unbounded => .unbounded,
                .included => |v| .{ .excluded = try v.clone(self.allocator) },
                .excluded => |v| .{ .included = try v.clone(self.allocator) },
            };
        }

        // Add final interval if last interval doesn't extend to infinity
        if (prev_upper != .unbounded) {
            try result.intervals.append(self.allocator, .{
                .lower = prev_upper,
                .upper = .unbounded,
            });
        }

        return result;
    }

    /// Compute the intersection of two ranges
    pub fn intersection(self: Range, other: Range) !Range {
        var result = Range.init(self.allocator);

        for (self.intervals.items) |a| {
            for (other.intervals.items) |b| {
                // Compute intersection of two intervals
                const new_lower = maxBound(a.lower, b.lower, true);
                const new_upper = minBound(a.upper, b.upper, false);

                const new_interval = Interval{
                    .lower = try new_lower.clone(self.allocator),
                    .upper = try new_upper.clone(self.allocator),
                };

                if (!new_interval.isEmpty()) {
                    try result.intervals.append(self.allocator, new_interval);
                } else {
                    // Clean up if empty
                    var mutable_interval = new_interval;
                    mutable_interval.deinit(self.allocator);
                }
            }
        }

        return result;
    }

    /// Compute the union of two ranges
    pub fn @"union"(self: Range, other: Range) !Range {
        // Union = complement(intersection(complement(self), complement(other)))
        var self_comp = try self.complement();
        defer self_comp.deinit();

        var other_comp = try other.complement();
        defer other_comp.deinit();

        var inter = try self_comp.intersection(other_comp);
        defer inter.deinit();

        return inter.complement();
    }

    /// Check if two ranges are disjoint (no overlap)
    pub fn isDisjoint(self: Range, other: Range) bool {
        for (self.intervals.items) |a| {
            for (other.intervals.items) |b| {
                if (a.overlaps(b)) return false;
            }
        }
        return true;
    }

    /// Check if self is a subset of other
    pub fn subsetOf(self: Range, other: Range) !bool {
        var inter = try self.intersection(other);
        defer inter.deinit();
        return self.eql(inter);
    }
};

fn boundsEqual(a: Bound, b: Bound) bool {
    return switch (a) {
        .unbounded => b == .unbounded,
        .included => |va| switch (b) {
            .included => |vb| va.eql(vb),
            else => false,
        },
        .excluded => |va| switch (b) {
            .excluded => |vb| va.eql(vb),
            else => false,
        },
    };
}

/// Get the maximum of two lower bounds
fn maxBound(a: Bound, b: Bound, is_lower: bool) Bound {
    _ = is_lower;
    return switch (a) {
        .unbounded => b,
        .included => |va| switch (b) {
            .unbounded => a,
            .included => |vb| if (va.greaterThanOrEqual(vb)) a else b,
            .excluded => |vb| {
                const cmp = va.order(vb);
                if (cmp == .gt) return a;
                if (cmp == .eq) return b; // excluded is more restrictive
                return b;
            },
        },
        .excluded => |va| switch (b) {
            .unbounded => a,
            .included => |vb| {
                const cmp = va.order(vb);
                if (cmp == .gt or cmp == .eq) return a;
                return b;
            },
            .excluded => |vb| if (va.greaterThanOrEqual(vb)) a else b,
        },
    };
}

/// Get the minimum of two upper bounds
fn minBound(a: Bound, b: Bound, is_upper: bool) Bound {
    _ = is_upper;
    return switch (a) {
        .unbounded => b,
        .included => |va| switch (b) {
            .unbounded => a,
            .included => |vb| if (va.lessThanOrEqual(vb)) a else b,
            .excluded => |vb| {
                const cmp = va.order(vb);
                if (cmp == .lt) return a;
                if (cmp == .eq) return b; // excluded is more restrictive
                return b;
            },
        },
        .excluded => |va| switch (b) {
            .unbounded => a,
            .included => |vb| {
                const cmp = va.order(vb);
                if (cmp == .lt or cmp == .eq) return a;
                return b;
            },
            .excluded => |vb| if (va.lessThanOrEqual(vb)) a else b,
        },
    };
}

test "range operations" {
    const allocator = std.testing.allocator;

    // Create some test versions
    var v1 = try Version.parse(allocator, "1.0.0");
    defer v1.deinit(allocator);

    var v2 = try Version.parse(allocator, "2.0.0");
    defer v2.deinit(allocator);

    // Test singleton
    var r1 = try Range.singleton(allocator, v1);
    defer r1.deinit();
    try std.testing.expect(r1.contains(v1));
    try std.testing.expect(!r1.contains(v2));

    // Test >=1.0.0
    var r2 = try Range.greaterThanOrEqual(allocator, v1);
    defer r2.deinit();
    try std.testing.expect(r2.contains(v1));
    try std.testing.expect(r2.contains(v2));

    // Test empty
    var empty_range = Range.empty(allocator);
    defer empty_range.deinit();
    try std.testing.expect(empty_range.isEmpty());
    try std.testing.expect(!empty_range.contains(v1));
}
