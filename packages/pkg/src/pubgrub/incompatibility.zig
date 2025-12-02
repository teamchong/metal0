//! Incompatibility - A set of terms that should never be satisfied together
//!
//! An incompatibility originates from package dependencies:
//! If A@1 depends on B>=2, we can never have both "A=1" and "not B>=2" satisfied.
//! This creates incompatibility {A=1, not B>=2}.
//!
//! Incompatibilities can also be derived during conflict resolution.

const std = @import("std");
const Term = @import("term.zig").Term;
const Range = @import("range.zig").Range;
const Version = @import("version.zig").Version;

/// Unique identifier for an incompatibility
pub const IncompId = u32;

/// Unique identifier for a package
pub const PackageId = u32;

/// The reason an incompatibility exists
pub const Kind = union(enum) {
    /// Initial incompatibility: we must pick the root package
    not_root: struct {
        package: PackageId,
        version: Version,
    },
    /// No versions exist in the given range
    no_versions: struct {
        package: PackageId,
        range: Range,
    },
    /// Dependency: package@versions depends on dep in dep_range
    from_dependency: struct {
        package: PackageId,
        versions: Range,
        dep: PackageId,
        dep_range: Range,
    },
    /// Derived from two other incompatibilities (conflict resolution)
    derived: struct {
        cause1: IncompId,
        cause2: IncompId,
    },
    /// Custom reason (e.g., package unavailable)
    custom: struct {
        package: PackageId,
        range: Range,
        reason: []const u8,
    },

    pub fn deinit(self: *Kind, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .not_root => |*nr| nr.version.deinit(allocator),
            .no_versions => |*nv| nv.range.deinit(),
            .from_dependency => |*fd| {
                fd.versions.deinit();
                fd.dep_range.deinit();
            },
            .derived => {},
            .custom => |*c| {
                c.range.deinit();
                allocator.free(c.reason);
            },
        }
    }
};

/// An incompatibility is a set of terms for different packages
/// that should never be satisfied all together.
pub const Incompatibility = struct {
    /// Map from package ID to term for that package
    /// Using a simple array for small maps (usually 1-2 packages)
    terms: std.ArrayList(PackageTerm),
    /// Why this incompatibility exists
    kind: Kind,
    allocator: std.mem.Allocator,

    pub const PackageTerm = struct {
        package: PackageId,
        term: Term,

        pub fn deinit(self: *PackageTerm) void {
            self.term.deinit();
        }
    };

    pub fn init(allocator: std.mem.Allocator, kind: Kind) Incompatibility {
        return .{
            .terms = std.ArrayList(PackageTerm){},
            .kind = kind,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Incompatibility) void {
        for (self.terms.items) |*pt| {
            pt.deinit();
        }
        self.terms.deinit(self.allocator);
        self.kind.deinit(self.allocator);
    }

    /// Add a term for a package to this incompatibility
    pub fn addTerm(self: *Incompatibility, package: PackageId, term: Term) !void {
        try self.terms.append(self.allocator, .{ .package = package, .term = term });
    }

    /// Get the term for a specific package
    pub fn get(self: Incompatibility, package: PackageId) ?*const Term {
        for (self.terms.items) |*pt| {
            if (pt.package == package) return &pt.term;
        }
        return null;
    }

    /// Create "not root" incompatibility to start resolution
    pub fn notRoot(allocator: std.mem.Allocator, root_package: PackageId, root_version: Version) !Incompatibility {
        var incompat = Incompatibility.init(allocator, .{
            .not_root = .{
                .package = root_package,
                .version = try root_version.clone(allocator),
            },
        });

        // Add negative term: not(root@version) means we MUST select root@version
        const singleton = try Range.singleton(allocator, root_version);
        try incompat.addTerm(root_package, .{
            .range = singleton,
            .positive = false, // Negative term
        });

        return incompat;
    }

    /// Create incompatibility from a dependency
    /// package@versions depends on dep@dep_range
    /// Incompatibility: {package in versions, dep NOT in dep_range}
    pub fn fromDependency(
        allocator: std.mem.Allocator,
        package: PackageId,
        versions: Range,
        dep: PackageId,
        dep_range: Range,
    ) !Incompatibility {
        var incompat = Incompatibility.init(allocator, .{
            .from_dependency = .{
                .package = package,
                .versions = try versions.clone(),
                .dep = dep,
                .dep_range = try dep_range.clone(),
            },
        });

        // Positive term for the dependent package
        try incompat.addTerm(package, .{
            .range = try versions.clone(),
            .positive = true,
        });

        // Negative term for the dependency (if dep_range is not empty)
        if (!dep_range.isEmpty()) {
            try incompat.addTerm(dep, .{
                .range = try dep_range.clone(),
                .positive = false,
            });
        }

        return incompat;
    }

    /// Create incompatibility for "no versions available"
    pub fn noVersions(allocator: std.mem.Allocator, package: PackageId, range: Range) !Incompatibility {
        var incompat = Incompatibility.init(allocator, .{
            .no_versions = .{
                .package = package,
                .range = try range.clone(),
            },
        });

        try incompat.addTerm(package, .{
            .range = try range.clone(),
            .positive = true,
        });

        return incompat;
    }

    /// Create a derived incompatibility from conflict resolution
    pub fn priorCause(
        allocator: std.mem.Allocator,
        incompat1: Incompatibility,
        incompat2: Incompatibility,
        cause1_id: IncompId,
        cause2_id: IncompId,
        unified_package: PackageId,
    ) !Incompatibility {
        var result = Incompatibility.init(allocator, .{
            .derived = .{
                .cause1 = cause1_id,
                .cause2 = cause2_id,
            },
        });

        // Get the terms from both incompatibilities, merging on unified_package
        var seen_packages = std.AutoHashMap(PackageId, void).init(allocator);
        defer seen_packages.deinit();

        // Get term for unified_package from both incompatibilities and union them
        const t1 = incompat1.get(unified_package);
        const t2 = incompat2.get(unified_package);

        if (t1 != null and t2 != null) {
            var unified_term = try t1.?.@"union"(t2.?.*);
            // Only add if not "any" (which would make incompatibility trivially satisfied)
            if (unified_term.positive or !unified_term.range.isEmpty()) {
                try result.addTerm(unified_package, unified_term);
            } else {
                unified_term.deinit();
            }
            try seen_packages.put(unified_package, {});
        }

        // Add all other terms from incompat1
        for (incompat1.terms.items) |pt| {
            if (pt.package == unified_package) continue;
            if (seen_packages.contains(pt.package)) continue;

            // If same package exists in incompat2, intersect the terms
            if (incompat2.get(pt.package)) |t2_term| {
                const intersected = try pt.term.intersection(t2_term.*);
                try result.addTerm(pt.package, intersected);
            } else {
                try result.addTerm(pt.package, try pt.term.clone());
            }
            try seen_packages.put(pt.package, {});
        }

        // Add remaining terms from incompat2
        for (incompat2.terms.items) |pt| {
            if (pt.package == unified_package) continue;
            if (seen_packages.contains(pt.package)) continue;
            try result.addTerm(pt.package, try pt.term.clone());
            try seen_packages.put(pt.package, {});
        }

        return result;
    }

    /// Check if this incompatibility is terminal (implies no solution)
    pub fn isTerminal(self: Incompatibility, root_package: PackageId, root_version: Version) bool {
        if (self.terms.items.len == 0) return true;
        if (self.terms.items.len > 1) return false;

        const pt = self.terms.items[0];
        return pt.package == root_package and pt.term.contains(root_version);
    }

    /// Relation of partial solution with this incompatibility
    pub const Relation = enum {
        /// All terms satisfied → conflict!
        satisfied,
        /// At least one term contradicted → incompatibility irrelevant
        contradicted,
        /// All but one satisfied, one inconclusive → almost satisfied
        almost_satisfied,
        /// More than one inconclusive
        inconclusive,
    };

    /// Determine relation of partial solution to this incompatibility
    /// `getTerm` returns the current term intersection for a package (null if unknown)
    pub fn relation(
        self: Incompatibility,
        comptime getTerm: fn (PackageId) ?*const Term,
    ) struct { rel: Relation, package: ?PackageId } {
        var num_inconclusive: u32 = 0;
        var inconclusive_package: ?PackageId = null;
        var contradicted_package: ?PackageId = null;

        for (self.terms.items) |pt| {
            const solution_term = getTerm(pt.package);
            if (solution_term == null) {
                // Unknown package is inconclusive
                num_inconclusive += 1;
                inconclusive_package = pt.package;
                if (num_inconclusive > 1) {
                    return .{ .rel = .inconclusive, .package = null };
                }
                continue;
            }

            const rel = pt.term.relationWith(solution_term.?.*) catch .inconclusive;
            switch (rel) {
                .satisfied => {}, // Continue checking
                .contradicted => {
                    contradicted_package = pt.package;
                    return .{ .rel = .contradicted, .package = contradicted_package };
                },
                .inconclusive => {
                    num_inconclusive += 1;
                    inconclusive_package = pt.package;
                    if (num_inconclusive > 1) {
                        return .{ .rel = .inconclusive, .package = null };
                    }
                },
            }
        }

        if (num_inconclusive == 0) {
            return .{ .rel = .satisfied, .package = null };
        } else {
            return .{ .rel = .almost_satisfied, .package = inconclusive_package };
        }
    }

    /// Iterator over package-term pairs
    pub fn iter(self: Incompatibility) []const PackageTerm {
        return self.terms.items;
    }
};
