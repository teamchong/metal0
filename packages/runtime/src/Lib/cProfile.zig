//! CPython source: Lib/cProfile.py
//!
//! Provides a deterministic profiler for Python programs.
//!
//! Mirrors: CPython Lib/cProfile.py

// Re-export types
pub const ProfileEntry = @import("cProfile/types.zig").ProfileEntry;
pub const CallStackEntry = @import("cProfile/types.zig").CallStackEntry;

// Re-export sort
pub const SortKey = @import("cProfile/sort.zig").SortKey;

// Re-export profiler
pub const Profile = @import("cProfile/profiler.zig").Profile;

// Re-export stats
pub const Stats = @import("cProfile/stats.zig").Stats;

// Re-export module functions
pub const run = @import("cProfile/module_functions.zig").run;
pub const runMain = @import("cProfile/module_functions.zig").runMain;
pub const label = @import("cProfile/module_functions.zig").label;
pub const init = @import("cProfile/module_functions.zig").init;
pub const reset = @import("cProfile/module_functions.zig").reset;
