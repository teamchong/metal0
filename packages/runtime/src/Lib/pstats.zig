//! CPython source: Lib/pstats.py
//!
//! Provides statistics browser for profiler data.
//!
//! Mirrors: CPython Lib/pstats.py
//!
//! This module has been split into a modular directory structure:
//! - types.zig: Core types (SortKey, FuncStat, FuncId, CallerInfo)
//! - stats.zig: Main Stats container with core methods
//! - sorting.zig: Sorting-related functionality
//! - printing.zig: Print methods (printStats, printCallers, printCallees)
//! - io.zig: File I/O operations (load, dump)
//! - utils.zig: Utility functions

// Re-export all public APIs
pub const types = @import("pstats/types.zig");
pub const stats = @import("pstats/stats.zig");
pub const sorting = @import("pstats/sorting.zig");
pub const printing = @import("pstats/printing.zig");
pub const io = @import("pstats/io.zig");
pub const utils = @import("pstats/utils.zig");

// Re-export commonly used types and functions
pub const SortKey = types.SortKey;
pub const FuncId = types.FuncId;
pub const CallerInfo = types.CallerInfo;
pub const FuncStat = types.FuncStat;
pub const Stats = stats.Stats;

// Re-export utility functions
pub const funcKey = utils.funcKey;
pub const stripPath = utils.stripPath;
pub const formatTime = utils.formatTime;
pub const formatCalls = utils.formatCalls;
