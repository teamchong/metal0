//! Module-level profiling functions
//!
//! Provides convenience functions for profiling code without explicitly
//! managing Profile instances.

const std = @import("std");
const types = @import("types.zig");
const profile_class = @import("profile_class.zig");

const SortKey = types.SortKey;
const Profile = profile_class.Profile;

// ============================================================================
// Module Functions
// ============================================================================

/// Run a command string under profiler
pub fn run(allocator: std.mem.Allocator, statement: []const u8, filename: ?[]const u8, sort: SortKey) !void {
    var prof = Profile.init(allocator, null, null);
    defer prof.deinit();

    try prof.run(statement);
    prof.createStats();

    if (filename) |f| {
        try prof.dumpStats(f);
    } else {
        try prof.printStats(sort);
    }
}

/// Profile a function call
pub fn runctx(allocator: std.mem.Allocator, statement: []const u8, globals: ?*anyopaque, locals: ?*anyopaque, filename: ?[]const u8, sort: SortKey) !void {
    var prof = Profile.init(allocator, null, null);
    defer prof.deinit();

    try prof.runctx(statement, globals, locals);
    prof.createStats();

    if (filename) |f| {
        try prof.dumpStats(f);
    } else {
        try prof.printStats(sort);
    }
}
