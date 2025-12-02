//! Partial Solution - Tracks the current state of resolution
//!
//! Contains all package assignments (decisions and derivations) organized
//! by package and decision level.
//!
//! A "decision" is when we commit to a specific version for a package.
//! A "derivation" is a constraint inferred from incompatibilities.

const std = @import("std");
const Term = @import("term.zig").Term;
const Range = @import("range.zig").Range;
const Version = @import("version.zig").Version;
const Incompatibility = @import("incompatibility.zig").Incompatibility;
const IncompId = @import("incompatibility.zig").IncompId;
const PackageId = @import("incompatibility.zig").PackageId;

/// Decision level - increases with each decision
pub const DecisionLevel = u32;

/// A derivation with its context
pub const Derivation = struct {
    /// When this derivation was made
    global_index: u32,
    /// The decision level when made
    decision_level: DecisionLevel,
    /// The incompatibility that caused this derivation
    cause: IncompId,
    /// The accumulated term intersection up to this point
    accumulated: Term,

    pub fn deinit(self: *Derivation) void {
        self.accumulated.deinit();
    }
};

/// Assignment for a single package
pub const PackageAssignment = struct {
    /// Either a decided version or accumulated derivations
    state: union(enum) {
        decision: struct {
            version: Version,
            decision_level: DecisionLevel,
        },
        derivations: Term,
    },
    /// History of derivations for backtracking
    derivation_history: std.ArrayList(Derivation),
    /// Smallest decision level with a derivation
    smallest_decision_level: DecisionLevel,
    /// Highest decision level with a derivation
    highest_decision_level: DecisionLevel,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PackageAssignment {
        return .{
            .state = .{ .derivations = Term.any(allocator) },
            .derivation_history = std.ArrayList(Derivation){},
            .smallest_decision_level = 0,
            .highest_decision_level = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PackageAssignment) void {
        switch (self.state) {
            .decision => |*d| d.version.deinit(self.allocator),
            .derivations => |*t| t.deinit(),
        }
        for (self.derivation_history.items) |*d| {
            d.deinit();
        }
        self.derivation_history.deinit(self.allocator);
    }

    /// Get the current term for this package
    pub fn term(self: *const PackageAssignment) Term {
        return switch (self.state) {
            .decision => |d| Term.exact(self.allocator, d.version) catch Term.any(self.allocator),
            .derivations => |t| t,
        };
    }

    /// Check if this package has a decision
    pub fn hasDecision(self: PackageAssignment) bool {
        return self.state == .decision;
    }
};

/// The partial solution tracks all package assignments
pub const PartialSolution = struct {
    /// Package ID -> Assignment mapping
    assignments: std.AutoHashMap(PackageId, PackageAssignment),
    /// Current decision level
    decision_level: DecisionLevel,
    /// Global index counter
    next_global_index: u32,
    /// Packages that need priority updates
    outdated_priorities: std.AutoHashMap(PackageId, void),
    /// Whether we've ever backtracked
    has_backtracked: bool,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PartialSolution {
        return .{
            .assignments = std.AutoHashMap(PackageId, PackageAssignment).init(allocator),
            .decision_level = 0,
            .next_global_index = 0,
            .outdated_priorities = std.AutoHashMap(PackageId, void).init(allocator),
            .has_backtracked = false,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PartialSolution) void {
        var iter = self.assignments.valueIterator();
        while (iter.next()) |assignment| {
            var mut_assignment = assignment;
            mut_assignment.deinit();
        }
        self.assignments.deinit();
        self.outdated_priorities.deinit();
    }

    /// Add a derivation for a package
    pub fn addDerivation(
        self: *PartialSolution,
        package: PackageId,
        cause: IncompId,
        incompat_store: []const Incompatibility,
    ) !void {
        const incompat = &incompat_store[cause];
        const incompat_term = incompat.get(package) orelse return error.PackageNotInIncompat;

        // Negate the incompatibility term to get what the package MUST satisfy
        var negated = try incompat_term.negate();

        const derivation = Derivation{
            .global_index = self.next_global_index,
            .decision_level = self.decision_level,
            .cause = cause,
            .accumulated = negated,
        };
        self.next_global_index += 1;

        const result = try self.assignments.getOrPut(package);
        if (result.found_existing) {
            // Update existing assignment
            var assignment = result.value_ptr;
            switch (assignment.state) {
                .decision => return error.AlreadyDecided,
                .derivations => |*current| {
                    // Intersect with new derivation
                    var new_term = try current.intersection(negated);
                    current.deinit();
                    current.* = new_term;

                    // Update accumulated in derivation
                    var deriv_copy = derivation;
                    deriv_copy.accumulated = try new_term.clone();
                    try assignment.derivation_history.append(self.allocator, deriv_copy);
                },
            }
            assignment.highest_decision_level = self.decision_level;
        } else {
            // New package
            var assignment = PackageAssignment.init(self.allocator);
            assignment.state = .{ .derivations = try negated.clone() };
            assignment.smallest_decision_level = self.decision_level;
            assignment.highest_decision_level = self.decision_level;
            try assignment.derivation_history.append(self.allocator, derivation);
            result.value_ptr.* = assignment;
        }

        try self.outdated_priorities.put(package, {});
    }

    /// Add a decision for a package
    pub fn addDecision(self: *PartialSolution, package: PackageId, version: Version) !void {
        self.decision_level += 1;

        const result = try self.assignments.getOrPut(package);
        if (result.found_existing) {
            var assignment = result.value_ptr;
            switch (assignment.state) {
                .decision => return error.AlreadyDecided,
                .derivations => |*t| t.deinit(),
            }
            assignment.state = .{
                .decision = .{
                    .version = try version.clone(self.allocator),
                    .decision_level = self.decision_level,
                },
            };
            assignment.highest_decision_level = self.decision_level;
        } else {
            var assignment = PackageAssignment.init(self.allocator);
            assignment.state = .{
                .decision = .{
                    .version = try version.clone(self.allocator),
                    .decision_level = self.decision_level,
                },
            };
            assignment.smallest_decision_level = self.decision_level;
            assignment.highest_decision_level = self.decision_level;
            result.value_ptr.* = assignment;
        }

        _ = self.outdated_priorities.remove(package);
    }

    /// Get the term intersection for a package (null if not assigned)
    pub fn getTermForPackage(self: *const PartialSolution, package: PackageId) ?Term {
        const assignment = self.assignments.get(package) orelse return null;
        return assignment.term();
    }

    /// Backtrack to a given decision level
    pub fn backtrack(self: *PartialSolution, target_level: DecisionLevel) void {
        self.decision_level = target_level;
        self.has_backtracked = true;

        var to_remove = std.ArrayList(PackageId).init(self.allocator);
        defer to_remove.deinit(self.allocator);

        var iter = self.assignments.iterator();
        while (iter.next()) |entry| {
            const package = entry.key_ptr.*;
            var assignment = entry.value_ptr;

            if (assignment.smallest_decision_level > target_level) {
                // Remove completely
                to_remove.append(self.allocator, package) catch continue;
            } else if (assignment.highest_decision_level > target_level) {
                // Truncate derivation history
                while (assignment.derivation_history.items.len > 0) {
                    const last = &assignment.derivation_history.items[assignment.derivation_history.items.len - 1];
                    if (last.decision_level <= target_level) break;
                    var popped = assignment.derivation_history.pop();
                    popped.deinit();
                }

                // Reset state to derivations
                if (assignment.derivation_history.items.len > 0) {
                    const last = &assignment.derivation_history.items[assignment.derivation_history.items.len - 1];
                    switch (assignment.state) {
                        .decision => |*d| d.version.deinit(self.allocator),
                        .derivations => |*t| t.deinit(),
                    }
                    assignment.state = .{ .derivations = last.accumulated.clone() catch Term.any(self.allocator) };
                    assignment.highest_decision_level = last.decision_level;
                }

                self.outdated_priorities.put(package, {}) catch {};
            }
        }

        for (to_remove.items) |package| {
            if (self.assignments.fetchRemove(package)) |kv| {
                var assignment = kv.value;
                assignment.deinit();
            }
        }
    }

    /// Get all packages that need decisions (have positive derivations but no decision)
    pub fn undecidedPackages(self: *const PartialSolution) std.ArrayList(PackageId) {
        var result = std.ArrayList(PackageId).init(self.allocator);
        var iter = self.assignments.iterator();
        while (iter.next()) |entry| {
            const assignment = entry.value_ptr;
            switch (assignment.state) {
                .decision => continue,
                .derivations => |t| {
                    if (t.positive) {
                        result.append(self.allocator, entry.key_ptr.*) catch continue;
                    }
                },
            }
        }
        return result;
    }

    /// Extract the solution (all decisions)
    pub fn extractSolution(self: *const PartialSolution) std.AutoHashMap(PackageId, Version) {
        var result = std.AutoHashMap(PackageId, Version).init(self.allocator);
        var iter = self.assignments.iterator();
        while (iter.next()) |entry| {
            const assignment = entry.value_ptr;
            switch (assignment.state) {
                .decision => |d| {
                    result.put(entry.key_ptr.*, d.version.clone(self.allocator) catch continue) catch continue;
                },
                .derivations => continue,
            }
        }
        return result;
    }
};
