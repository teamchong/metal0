/// helpers - Argument Parsing Helpers
/// Utility functions for argument validation.

const std = @import("std");
const types = @import("types.zig");

pub const ArgError = types.ArgError;

// ============================================================================
// Argument Validation
// ============================================================================

/// No-keyword argument checker
pub fn noKeywords(function_name: []const u8, kwargs: ?*anyopaque) bool {
    _ = function_name;
    return kwargs == null;
}

/// No-positional argument checker
pub fn noPositional(function_name: []const u8, args: []const *anyopaque) bool {
    _ = function_name;
    return args.len == 0;
}

/// Check if kwargs contains only string keys
pub fn hasOnlyStringKeys(_: ?*anyopaque) bool {
    // Would iterate kwargs and check key types
    return true;
}

/// Unpack positional args only (for methods with no kwargs)
pub fn unpackTupleOnly(
    args: []const *anyopaque,
    min: usize,
    max: usize,
    function_name: []const u8,
) ArgError!void {
    if (args.len < min) {
        _ = function_name;
        return ArgError.MissingArgument;
    }
    if (args.len > max) {
        return ArgError.TooManyArguments;
    }
}

// ============================================================================
// Module Functions
// ============================================================================

/// Finalization - cleanup any cached parser state
pub fn fini() void {
    // Cleanup any global parser caches
}

/// Initialize the argument parsing module
pub fn init() void {
    // Initialize any global state
}
