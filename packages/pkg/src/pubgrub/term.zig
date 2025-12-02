//! Term - A positive or negative expression regarding a set of versions
//!
//! A term is the fundamental unit of operation of the PubGrub algorithm.
//!
//! - Positive(r): satisfied if the package is selected AND version is in r
//! - Negative(r): satisfied if the package is NOT selected OR version is in r.complement()
//!
//! The distinction matters for conflict analysis:
//! - Positive(empty): conflict - we need a version but can't pick any
//! - Negative(full): fine - we don't need to select this package

const std = @import("std");
const Range = @import("range.zig").Range;
const Version = @import("version.zig").Version;

pub const Term = struct {
    range: Range,
    positive: bool,

    pub fn init(range: Range, positive: bool) Term {
        return .{ .range = range, .positive = positive };
    }

    pub fn deinit(self: *Term) void {
        self.range.deinit();
    }

    pub fn clone(self: Term) !Term {
        return .{
            .range = try self.range.clone(),
            .positive = self.positive,
        };
    }

    /// Create a term that is always true (matches any version, including none)
    pub fn any(allocator: std.mem.Allocator) Term {
        return .{
            .range = Range.empty(allocator),
            .positive = false,
        };
    }

    /// Create a term that is never true
    pub fn none(allocator: std.mem.Allocator) Term {
        return .{
            .range = Range.empty(allocator),
            .positive = true,
        };
    }

    /// Create a positive term containing exactly one version
    pub fn exact(allocator: std.mem.Allocator, v: Version) !Term {
        return .{
            .range = try Range.singleton(allocator, v),
            .positive = true,
        };
    }

    /// Negate a term
    pub fn negate(self: Term) !Term {
        return .{
            .range = try self.range.clone(),
            .positive = !self.positive,
        };
    }

    /// Check if a version satisfies this term
    pub fn contains(self: Term, v: Version) bool {
        if (self.positive) {
            return self.range.contains(v);
        } else {
            return !self.range.contains(v);
        }
    }

    /// Compute the intersection of two terms
    /// The intersection is positive if any term is positive
    pub fn intersection(self: Term, other: Term) !Term {
        if (self.positive and other.positive) {
            // Both positive: intersection of ranges
            return .{
                .range = try self.range.intersection(other.range),
                .positive = true,
            };
        } else if (self.positive and !other.positive) {
            // self positive, other negative: self \ other.range
            var other_comp = try other.range.complement();
            defer other_comp.deinit();
            return .{
                .range = try self.range.intersection(other_comp),
                .positive = true,
            };
        } else if (!self.positive and other.positive) {
            // self negative, other positive: other \ self.range
            var self_comp = try self.range.complement();
            defer self_comp.deinit();
            return .{
                .range = try other.range.intersection(self_comp),
                .positive = true,
            };
        } else {
            // Both negative: union of ranges (stays negative)
            return .{
                .range = try self.range.@"union"(other.range),
                .positive = false,
            };
        }
    }

    /// Compute the union of two terms
    /// The union is positive only if both terms are positive
    pub fn @"union"(self: Term, other: Term) !Term {
        if (self.positive and other.positive) {
            // Both positive: union of ranges
            return .{
                .range = try self.range.@"union"(other.range),
                .positive = true,
            };
        } else if (self.positive and !other.positive) {
            // self positive, other negative
            var self_comp = try self.range.complement();
            defer self_comp.deinit();
            return .{
                .range = try self_comp.intersection(other.range),
                .positive = false,
            };
        } else if (!self.positive and other.positive) {
            // self negative, other positive
            var other_comp = try other.range.complement();
            defer other_comp.deinit();
            return .{
                .range = try other_comp.intersection(self.range),
                .positive = false,
            };
        } else {
            // Both negative: intersection of ranges (stays negative)
            return .{
                .range = try self.range.intersection(other.range),
                .positive = false,
            };
        }
    }

    /// Check if self is a subset of other
    pub fn subsetOf(self: Term, other: Term) !bool {
        var inter = try self.intersection(other);
        defer inter.deinit();
        return self.eql(inter);
    }

    /// Check if two terms are disjoint
    pub fn isDisjoint(self: Term, other: Term) !bool {
        var inter = try self.intersection(other);
        defer inter.deinit();
        return inter.positive and inter.range.isEmpty();
    }

    /// Check equality of terms
    pub fn eql(self: Term, other: Term) bool {
        return self.positive == other.positive and self.range.eql(other.range);
    }

    /// Relation of a term with respect to a set of terms (represented as their intersection)
    pub const Relation = enum {
        /// The set satisfies this term (term must be true when set is true)
        satisfied,
        /// The set contradicts this term (term must be false when set is true)
        contradicted,
        /// Neither - the set doesn't determine the term
        inconclusive,
    };

    /// Determine the relation of this term with another (the intersection of assignments)
    pub fn relationWith(self: Term, other: Term) !Relation {
        // other ⊆ self → satisfied
        if (try other.subsetOf(self)) return .satisfied;
        // other ∩ self = ∅ → contradicted
        if (try self.isDisjoint(other)) return .contradicted;
        return .inconclusive;
    }
};

test "term operations" {
    const allocator = std.testing.allocator;

    var v1 = try Version.parse(allocator, "1.0.0");
    defer v1.deinit(allocator);

    // Test exact term
    var t1 = try Term.exact(allocator, v1);
    defer t1.deinit();
    try std.testing.expect(t1.contains(v1));
    try std.testing.expect(t1.positive);
}
