//! PubGrub Solver - The main dependency resolution algorithm
//!
//! PubGrub uses conflict-driven clause learning (CDCL) to efficiently
//! resolve package dependencies. The algorithm:
//!
//! 1. Unit Propagation: Apply known constraints
//! 2. Decision: Pick a package and version to try
//! 3. Conflict Resolution: If conflict, learn new constraint and backtrack
//!
//! This is the "best" dependency resolver, used by Dart's pub, uv, and others.

const std = @import("std");
const Term = @import("term.zig").Term;
const Range = @import("range.zig").Range;
const Version = @import("version.zig").Version;
const Incompatibility = @import("incompatibility.zig").Incompatibility;
const IncompId = @import("incompatibility.zig").IncompId;
const PackageId = @import("incompatibility.zig").PackageId;
const PartialSolution = @import("partial_solution.zig").PartialSolution;

/// Dependencies for a package version
pub const Dependencies = union(enum) {
    /// Dependencies are available
    available: []const Dependency,
    /// Dependencies unavailable (e.g., package yanked)
    unavailable: []const u8,
};

/// A single dependency
pub const Dependency = struct {
    package: []const u8,
    range: Range,
};

/// Dependency provider interface
/// Implement this to provide package metadata to the solver
pub const DependencyProvider = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Get all available versions for a package (newest first)
        getVersions: *const fn (ptr: *anyopaque, package: []const u8) anyerror![]Version,
        /// Get dependencies for a specific package version
        getDependencies: *const fn (ptr: *anyopaque, package: []const u8, version: Version) anyerror!Dependencies,
        /// Priority for package selection (higher = earlier)
        prioritize: *const fn (ptr: *anyopaque, package: []const u8, range: Range) i64,
    };

    pub fn getVersions(self: DependencyProvider, package: []const u8) ![]Version {
        return self.vtable.getVersions(self.ptr, package);
    }

    pub fn getDependencies(self: DependencyProvider, package: []const u8, version: Version) !Dependencies {
        return self.vtable.getDependencies(self.ptr, package, version);
    }

    pub fn prioritize(self: DependencyProvider, package: []const u8, range: Range) i64 {
        return self.vtable.prioritize(self.ptr, package, range);
    }
};

/// Resolution result
pub const Resolution = struct {
    /// Selected packages and versions
    packages: std.StringHashMap(Version),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Resolution {
        return .{
            .packages = std.StringHashMap(Version).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Resolution) void {
        var iter = self.packages.valueIterator();
        while (iter.next()) |v| {
            var version = v;
            version.deinit(self.allocator);
        }
        self.packages.deinit();
    }
};

/// Error with human-readable explanation
pub const ResolveError = struct {
    message: []const u8,
    derivation: ?DerivationTree,

    pub const DerivationTree = struct {
        description: []const u8,
        causes: ?struct {
            cause1: *DerivationTree,
            cause2: *DerivationTree,
        },
    };
};

/// The PubGrub solver state
pub const Solver = struct {
    allocator: std.mem.Allocator,
    provider: DependencyProvider,

    /// Package name -> ID mapping
    package_ids: std.StringHashMap(PackageId),
    /// ID -> Package name mapping
    package_names: std.ArrayList([]const u8),
    /// Next package ID
    next_package_id: PackageId,

    /// All incompatibilities
    incompatibilities: std.ArrayList(Incompatibility),
    /// Incompatibilities indexed by package
    incompat_by_package: std.AutoHashMap(PackageId, std.ArrayList(IncompId)),

    /// Partial solution
    partial_solution: PartialSolution,

    /// Root package
    root_package: PackageId,
    root_version: Version,

    pub fn init(allocator: std.mem.Allocator, provider: DependencyProvider) Solver {
        return .{
            .allocator = allocator,
            .provider = provider,
            .package_ids = std.StringHashMap(PackageId).init(allocator),
            .package_names = std.ArrayList([]const u8){},
            .next_package_id = 0,
            .incompatibilities = std.ArrayList(Incompatibility){},
            .incompat_by_package = std.AutoHashMap(PackageId, std.ArrayList(IncompId)).init(allocator),
            .partial_solution = PartialSolution.init(allocator),
            .root_package = 0,
            .root_version = undefined,
        };
    }

    pub fn deinit(self: *Solver) void {
        self.package_ids.deinit();
        self.package_names.deinit(self.allocator);

        for (self.incompatibilities.items) |*incompat| {
            incompat.deinit();
        }
        self.incompatibilities.deinit(self.allocator);

        var iter = self.incompat_by_package.valueIterator();
        while (iter.next()) |list| {
            var mut_list = list;
            mut_list.deinit(self.allocator);
        }
        self.incompat_by_package.deinit();

        self.partial_solution.deinit();
    }

    /// Get or create a package ID
    fn getPackageId(self: *Solver, name: []const u8) !PackageId {
        if (self.package_ids.get(name)) |id| {
            return id;
        }

        const id = self.next_package_id;
        self.next_package_id += 1;

        const name_copy = try self.allocator.dupe(u8, name);
        try self.package_ids.put(name_copy, id);
        try self.package_names.append(self.allocator, name_copy);

        return id;
    }

    /// Add an incompatibility
    fn addIncompatibility(self: *Solver, incompat: Incompatibility) !IncompId {
        const id: IncompId = @intCast(self.incompatibilities.items.len);
        try self.incompatibilities.append(self.allocator, incompat);

        // Index by package
        for (incompat.iter()) |pt| {
            const result = try self.incompat_by_package.getOrPut(pt.package);
            if (!result.found_existing) {
                result.value_ptr.* = std.ArrayList(IncompId){};
            }
            try result.value_ptr.append(self.allocator, id);
        }

        return id;
    }

    /// Resolve dependencies starting from a root package
    pub fn resolve(self: *Solver, root_name: []const u8, root_version_str: []const u8) !Resolution {
        // Setup root package
        self.root_package = try self.getPackageId(root_name);
        self.root_version = try Version.parse(self.allocator, root_version_str);

        // Add "not root" incompatibility to force root selection
        const not_root = try Incompatibility.notRoot(self.allocator, self.root_package, self.root_version);
        _ = try self.addIncompatibility(not_root);

        // Main resolution loop
        var next_package = self.root_package;

        while (true) {
            // Unit propagation
            const propagation_result = try self.unitPropagation(next_package);
            switch (propagation_result) {
                .conflict => |terminal_incompat| {
                    // No solution - build error message
                    _ = terminal_incompat;
                    return error.NoSolution;
                },
                .ok => {},
            }

            // Pick next package to decide
            const maybe_next = self.pickHighestPriorityPackage();
            if (maybe_next == null) {
                // All packages decided - we have a solution!
                break;
            }
            next_package = maybe_next.?;

            // Choose a version for this package
            const package_name = self.package_names.items[next_package];
            const term = self.partial_solution.getTermForPackage(next_package) orelse {
                return error.NoTermForPackage;
            };

            const version = try self.chooseVersion(package_name, term.range);
            if (version == null) {
                // No version satisfies constraints
                const no_versions = try Incompatibility.noVersions(
                    self.allocator,
                    next_package,
                    try term.range.clone(),
                );
                _ = try self.addIncompatibility(no_versions);
                continue;
            }

            // Get dependencies and add as incompatibilities
            const deps = try self.provider.getDependencies(package_name, version.?);
            switch (deps) {
                .unavailable => |reason| {
                    // Add custom incompatibility
                    _ = reason;
                    continue;
                },
                .available => |dep_list| {
                    for (dep_list) |dep| {
                        const dep_id = try self.getPackageId(dep.package);
                        const incompat = try Incompatibility.fromDependency(
                            self.allocator,
                            next_package,
                            try Range.singleton(self.allocator, version.?),
                            dep_id,
                            try dep.range.clone(),
                        );
                        _ = try self.addIncompatibility(incompat);
                    }
                },
            }

            // Add decision
            try self.partial_solution.addDecision(next_package, version.?);
        }

        // Extract solution
        var resolution = Resolution.init(self.allocator);
        var sol = self.partial_solution.extractSolution();
        defer sol.deinit();

        var sol_iter = sol.iterator();
        while (sol_iter.next()) |entry| {
            const pkg_id = entry.key_ptr.*;
            const version = entry.value_ptr.*;
            const name = self.package_names.items[pkg_id];
            try resolution.packages.put(name, try version.clone(self.allocator));
        }

        return resolution;
    }

    /// Unit propagation phase
    const PropagationResult = union(enum) {
        ok: void,
        conflict: IncompId,
    };

    fn unitPropagation(self: *Solver, start_package: PackageId) !PropagationResult {
        var work_queue = std.ArrayList(PackageId){};
        defer work_queue.deinit(self.allocator);
        try work_queue.append(self.allocator, start_package);

        while (work_queue.items.len > 0) {
            const current = work_queue.pop();

            // Check all incompatibilities involving this package
            const incompats = self.incompat_by_package.get(current) orelse continue;

            for (incompats.items) |incompat_id| {
                const incompat = &self.incompatibilities.items[incompat_id];

                // Compute relation with partial solution
                const rel = self.computeRelation(incompat);

                switch (rel.rel) {
                    .satisfied => {
                        // Conflict! Need to resolve
                        const resolution = try self.conflictResolution(incompat_id);
                        switch (resolution) {
                            .terminal => |id| return .{ .conflict = id },
                            .backtracked => |info| {
                                // Clear work queue and restart with the package we derived
                                work_queue.clearRetainingCapacity();
                                try work_queue.append(self.allocator, info.package);
                            },
                        }
                    },
                    .almost_satisfied => |pkg| {
                        // Add derivation for the unsatisfied package
                        try self.partial_solution.addDerivation(
                            pkg,
                            incompat_id,
                            self.incompatibilities.items,
                        );
                        // Add to work queue
                        if (std.mem.indexOfScalar(PackageId, work_queue.items, pkg) == null) {
                            try work_queue.append(self.allocator, pkg);
                        }
                    },
                    .contradicted, .inconclusive => {},
                }
            }
        }

        return .ok;
    }

    /// Compute relation of incompatibility with partial solution
    fn computeRelation(self: *Solver, incompat: *const Incompatibility) struct { rel: Incompatibility.Relation, package: ?PackageId } {
        var num_inconclusive: u32 = 0;
        var inconclusive_package: ?PackageId = null;

        for (incompat.iter()) |pt| {
            const solution_term = self.partial_solution.getTermForPackage(pt.package);
            if (solution_term == null) {
                num_inconclusive += 1;
                inconclusive_package = pt.package;
                if (num_inconclusive > 1) {
                    return .{ .rel = .inconclusive, .package = null };
                }
                continue;
            }

            const rel = pt.term.relationWith(solution_term.?) catch .inconclusive;
            switch (rel) {
                .satisfied => {},
                .contradicted => return .{ .rel = .contradicted, .package = pt.package },
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

    /// Conflict resolution using CDCL
    const ConflictResult = union(enum) {
        terminal: IncompId,
        backtracked: struct {
            package: PackageId,
            incompat: IncompId,
        },
    };

    fn conflictResolution(self: *Solver, initial_incompat: IncompId) !ConflictResult {
        var current_incompat = initial_incompat;

        while (true) {
            const incompat = &self.incompatibilities.items[current_incompat];

            // Check if terminal (only root package left)
            if (incompat.isTerminal(self.root_package, self.root_version)) {
                return .{ .terminal = current_incompat };
            }

            // Find the satisfier and check decision levels
            const satisfier_result = self.findSatisfier(incompat);
            if (satisfier_result.different_levels) {
                // Backtrack to previous level
                self.partial_solution.backtrack(satisfier_result.previous_level);

                // Add derivation for the satisfier package
                try self.partial_solution.addDerivation(
                    satisfier_result.package,
                    current_incompat,
                    self.incompatibilities.items,
                );

                return .{ .backtracked = .{
                    .package = satisfier_result.package,
                    .incompat = current_incompat,
                } };
            } else {
                // Same decision level - derive prior cause
                const satisfier_cause = satisfier_result.satisfier_cause orelse return error.NoSatisfierCause;
                const cause_incompat = &self.incompatibilities.items[satisfier_cause];

                const prior = try Incompatibility.priorCause(
                    self.allocator,
                    incompat.*,
                    cause_incompat.*,
                    current_incompat,
                    satisfier_cause,
                    satisfier_result.package,
                );
                current_incompat = try self.addIncompatibility(prior);
            }
        }
    }

    /// Find the satisfier for an incompatibility
    fn findSatisfier(self: *Solver, incompat: *const Incompatibility) struct {
        package: PackageId,
        different_levels: bool,
        previous_level: u32,
        satisfier_cause: ?IncompId,
    } {
        // Simple implementation: find the term with highest decision level
        var satisfier_pkg: PackageId = 0;
        var satisfier_level: u32 = 0;
        var satisfier_cause: ?IncompId = null;
        var previous_level: u32 = 0;

        for (incompat.iter()) |pt| {
            const assignment = self.partial_solution.assignments.get(pt.package) orelse continue;
            const level = assignment.highest_decision_level;

            if (level > satisfier_level) {
                previous_level = satisfier_level;
                satisfier_level = level;
                satisfier_pkg = pt.package;

                // Get cause from derivation history
                if (assignment.derivation_history.items.len > 0) {
                    satisfier_cause = assignment.derivation_history.items[assignment.derivation_history.items.len - 1].cause;
                }
            } else if (level > previous_level) {
                previous_level = level;
            }
        }

        return .{
            .package = satisfier_pkg,
            .different_levels = previous_level < satisfier_level,
            .previous_level = previous_level,
            .satisfier_cause = satisfier_cause,
        };
    }

    /// Pick highest priority undecided package
    fn pickHighestPriorityPackage(self: *Solver) ?PackageId {
        var best_package: ?PackageId = null;
        var best_priority: i64 = std.math.minInt(i64);

        var iter = self.partial_solution.assignments.iterator();
        while (iter.next()) |entry| {
            const assignment = entry.value_ptr;

            // Skip decided packages
            if (assignment.hasDecision()) continue;

            // Only consider positive derivations
            switch (assignment.state) {
                .derivations => |t| {
                    if (!t.positive) continue;
                },
                else => continue,
            }

            const package = entry.key_ptr.*;
            const name = self.package_names.items[package];
            const term = self.partial_solution.getTermForPackage(package) orelse continue;

            const priority = self.provider.prioritize(name, term.range);
            if (priority > best_priority) {
                best_priority = priority;
                best_package = package;
            }
        }

        return best_package;
    }

    /// Choose a version satisfying the range
    fn chooseVersion(self: *Solver, package_name: []const u8, range: Range) !?Version {
        const versions = try self.provider.getVersions(package_name);

        // Find first version in range (versions should be newest first)
        for (versions) |v| {
            if (range.contains(v)) {
                return try v.clone(self.allocator);
            }
        }

        return null;
    }
};

/// Convenience function to resolve dependencies
pub fn resolve(
    allocator: std.mem.Allocator,
    provider: DependencyProvider,
    root_package: []const u8,
    root_version: []const u8,
) !Resolution {
    var solver = Solver.init(allocator, provider);
    defer solver.deinit();
    return solver.resolve(root_package, root_version);
}
