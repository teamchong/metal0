//! Module-level functions
//!
//! High-level functions for running code under the profiler.

const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");
const Profile = @import("profiler.zig").Profile;
const SortKey = @import("sort.zig").SortKey;

// ============================================================================
// Module Functions
// ============================================================================

/// Run a statement under the profiler
/// In AOT context, this records the statement as a profiled execution
pub fn run(statement: []const u8, filename: ?[]const u8, sort: ?SortKey) !void {
    const allocator = allocator_helper.fast_allocator;
    var profiler = Profile.init(allocator);
    defer profiler.deinit();

    profiler.enable();

    // Record the statement as a function call
    const fname = filename orelse "<string>";
    try profiler.recordCall(statement, fname, 1);

    // In AOT, actual execution happens in compiled code
    // This tracks it for profiling purposes

    try profiler.recordReturn(statement);

    profiler.disable();

    // Print stats with requested sort key
    try profiler.printStats(sort orelse .cumulative);
}

/// Run a main module under the profiler
pub fn runMain(allocator: std.mem.Allocator) !void {
    var profiler = Profile.init(allocator);
    defer profiler.deinit();

    profiler.enable();

    // In AOT context, the main module execution is compiled
    // This serves as the profiler entry point
    try profiler.recordCall("<module>", "__main__", 1);

    // Actual execution happens via compiled code
    // Generated code should call profiler.recordCall/recordReturn

    try profiler.recordReturn("<module>");

    profiler.disable();

    try profiler.printStats(.cumulative);
}

/// Create a label for a function
pub fn label(code: anytype) []const u8 {
    _ = code;
    return "<function>";
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

/// Initialize the cProfile module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}
