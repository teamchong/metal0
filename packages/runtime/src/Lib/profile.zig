//! CPython source: Lib/profile.py
//!
//! Provides deterministic profiling of Python programs.
//!
//! Mirrors: CPython Lib/profile.py
//!
//! This module has been split into a modular directory structure:
//! - types.zig - Core types (FuncStats, SortKey)
//! - profile_class.zig - Profile class implementation
//! - stats_class.zig - Stats class implementation
//! - module_functions.zig - Module-level run/runctx functions

// Re-export types
pub const FuncStats = @import("profile/types.zig").FuncStats;
pub const SortKey = @import("profile/types.zig").SortKey;

// Re-export classes
pub const Profile = @import("profile/profile_class.zig").Profile;
pub const Stats = @import("profile/stats_class.zig").Stats;

// Re-export module functions
pub const run = @import("profile/module_functions.zig").run;
pub const runctx = @import("profile/module_functions.zig").runctx;
