/// Public API
/// Mirrors cpython/Python/_warnings.c - public warning functions

const std = @import("std");
const Allocator = std.mem.Allocator;
const allocator_helper = @import("utils.allocator_helper");
const WarningAction = @import("action.zig").WarningAction;
const WarningCategory = @import("category.zig").WarningCategory;
const WarningFilter = @import("filter.zig").WarningFilter;
const WarningsState = @import("state.zig").WarningsState;

// ============================================================================
// Warning Functions
// ============================================================================

/// Format a warning message
pub fn formatWarning(
    allocator: Allocator,
    filename: []const u8,
    lineno: u32,
    category: WarningCategory,
    message: []const u8,
) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}:{d}: {s}: {s}", .{
        filename,
        lineno,
        category.name(),
        message,
    });
}

/// Default warning handler (prints to stderr)
pub fn defaultShowWarning(
    message: []const u8,
    category: WarningCategory,
    filename: []const u8,
    lineno: u32,
) void {
    const stderr = std.io.getStdErr().writer();
    stderr.print("{s}:{d}: {s}: {s}\n", .{
        filename,
        lineno,
        category.name(),
        message,
    }) catch {};
}

// ============================================================================
// Global State
// ============================================================================

var global_state: ?WarningsState = null;

/// Get or create global warnings state
pub fn getState() *WarningsState {
    if (global_state == null) {
        global_state = WarningsState.create(allocator_helper.fast_allocator);
    }
    return &global_state.?;
}

/// Deinitialize global state
pub fn deinitState() void {
    if (global_state) |*state| {
        state.deinit();
        global_state = null;
    }
}

// ============================================================================
// Public API
// ============================================================================

/// Issue a warning
pub fn warn(
    message: []const u8,
    category: WarningCategory,
    stacklevel: u32,
) !void {
    _ = stacklevel;
    const state = getState();
    if (!state.enabled) return;

    const filename = "<unknown>";
    const lineno: u32 = 0;
    const mod = "<module>";

    const action = state.getAction(message, category, mod, lineno);

    switch (action) {
        .error_action => return error.WarningAsError,
        .ignore => return,
        .always => {},
        .default => {
            if (state.registry.wasShownAtLocation(message, category, lineno)) {
                return;
            }
            try state.registry.markShownAtLocation(message, category, lineno);
        },
        .once => {
            if (state.registry.wasShownOnce(message, category)) {
                return;
            }
            try state.registry.markShownOnce(message, category);
        },
        .module => {
            // Similar to default but per-module
            if (state.registry.wasShownAtLocation(message, category, 0)) {
                return;
            }
            try state.registry.markShownAtLocation(message, category, 0);
        },
    }

    // Show the warning
    if (state.handler) |handler| {
        handler(message, category, filename, lineno);
    } else {
        defaultShowWarning(message, category, filename, lineno);
    }
}

/// Issue a warning with explicit location
pub fn warnExplicit(
    message: []const u8,
    category: WarningCategory,
    filename: []const u8,
    lineno: u32,
    mod: ?[]const u8,
) !void {
    const state = getState();
    if (!state.enabled) return;

    const module_name = mod orelse "<module>";
    const action = state.getAction(message, category, module_name, lineno);

    switch (action) {
        .error_action => return error.WarningAsError,
        .ignore => return,
        .always => {},
        .default => {
            if (state.registry.wasShownAtLocation(message, category, lineno)) {
                return;
            }
            try state.registry.markShownAtLocation(message, category, lineno);
        },
        .once => {
            if (state.registry.wasShownOnce(message, category)) {
                return;
            }
            try state.registry.markShownOnce(message, category);
        },
        .module => {
            if (state.registry.wasShownAtLocation(message, category, 0)) {
                return;
            }
            try state.registry.markShownAtLocation(message, category, 0);
        },
    }

    if (state.handler) |handler| {
        handler(message, category, filename, lineno);
    } else {
        defaultShowWarning(message, category, filename, lineno);
    }
}

/// Convenience functions for specific warning types
pub fn warnDeprecation(message: []const u8) !void {
    return warn(message, .DeprecationWarning, 1);
}

pub fn warnRuntime(message: []const u8) !void {
    return warn(message, .RuntimeWarning, 1);
}

pub fn warnUser(message: []const u8) !void {
    return warn(message, .UserWarning, 1);
}

// ============================================================================
// Filter Management API
// ============================================================================

/// Add a filter using string arguments (like Python's warnings.filterwarnings)
pub fn filterwarnings(
    action: []const u8,
    message: ?[]const u8,
    category_name: ?[]const u8,
    mod: ?[]const u8,
    lineno: u32,
) !void {
    const state = getState();

    const act = WarningAction.fromString(action) orelse return error.InvalidAction;
    const cat = if (category_name) |n| WarningCategory.fromString(n) else null;

    const filter = WarningFilter.init(act, message, cat, mod, lineno);
    try state.insertFilter(filter);
}

/// Simple filter: always show warnings of a category
pub fn simplefilter(action: []const u8, category: ?[]const u8) !void {
    return filterwarnings(action, null, category, null, 0);
}

/// Reset all filters to default
pub fn resetwarnings() !void {
    try getState().resetFilters();
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}
