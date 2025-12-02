//! PubGrub - Modern Dependency Resolution Algorithm
//!
//! This is a complete implementation of the PubGrub version solving algorithm,
//! as used by Dart's pub package manager and Astral's uv.
//!
//! Features:
//! - Conflict-Driven Clause Learning (CDCL) for efficient backtracking
//! - PEP 440 version support
//! - Human-readable error messages
//! - Support for extras and optional dependencies

pub const Version = @import("version.zig").Version;
pub const Range = @import("range.zig").Range;
pub const Bound = @import("range.zig").Bound;
pub const Interval = @import("range.zig").Interval;
pub const Term = @import("term.zig").Term;
pub const Incompatibility = @import("incompatibility.zig").Incompatibility;
pub const IncompId = @import("incompatibility.zig").IncompId;
pub const PackageId = @import("incompatibility.zig").PackageId;
pub const PartialSolution = @import("partial_solution.zig").PartialSolution;
pub const Solver = @import("solver.zig").Solver;
pub const DependencyProvider = @import("solver.zig").DependencyProvider;
pub const Dependencies = @import("solver.zig").Dependencies;
pub const Dependency = @import("solver.zig").Dependency;
pub const Resolution = @import("solver.zig").Resolution;

/// Convenience function to resolve dependencies
pub const resolve = @import("solver.zig").resolve;

// PyPI integration
pub const PyPIProvider = @import("pypi_provider.zig").PyPIProvider;
pub const resolveFromPyPI = @import("pypi_provider.zig").resolveFromPyPI;

test {
    _ = @import("version.zig");
    _ = @import("range.zig");
    _ = @import("term.zig");
    _ = @import("pypi_provider.zig");
}
