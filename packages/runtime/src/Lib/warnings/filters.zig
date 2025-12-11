//! Filter management functions
//!
//! Functions for adding and managing warning filters.

const std = @import("std");
const types = @import("types.zig");
const state = @import("state.zig");

/// Add a simple filter
pub fn simpleFilter(
    allocator: std.mem.Allocator,
    action: types.FilterAction,
    category: types.WarningCategory,
) !void {
    const warnings_state = state.getState(allocator);
    try warnings_state.appendFilter(.{
        .action = action,
        .category = category,
    });
}

/// Add a filter by string specification
pub fn filterWarnings(
    allocator: std.mem.Allocator,
    action: []const u8,
    message: ?[]const u8,
    category: types.WarningCategory,
    module: ?[]const u8,
    lineno: ?usize,
) !void {
    const filter_action = types.FilterAction.fromString(action) orelse return error.InvalidAction;
    const warnings_state = state.getState(allocator);
    try warnings_state.insertFilter(.{
        .action = filter_action,
        .message = message,
        .category = category,
        .module = module,
        .lineno = lineno,
    });
}

/// Reset all warning filters
pub fn resetWarnings(allocator: std.mem.Allocator) void {
    const warnings_state = state.getState(allocator);
    warnings_state.resetFilters();
}
