/// _warnings - Warnings Subsystem Implementation
/// Mirrors cpython/Python/_warnings.c
///
/// This module provides the low-level warnings infrastructure:
/// - Warning categories and filters
/// - Warning message formatting
/// - Default and custom warning handlers
/// - Per-module warning state

const std = @import("std");

// Re-export all submodules
pub const category = @import("_warnings/category.zig");
pub const action = @import("_warnings/action.zig");
pub const filter = @import("_warnings/filter.zig");
pub const registry = @import("_warnings/registry.zig");
pub const state = @import("_warnings/state.zig");
pub const api = @import("_warnings/api.zig");

// Re-export primary types
pub const WarningCategory = category.WarningCategory;
pub const WarningAction = action.WarningAction;
pub const WarningFilter = filter.WarningFilter;
pub const WarningRegistry = registry.WarningRegistry;
pub const WarningsState = state.WarningsState;

// Re-export primary functions
pub const formatWarning = api.formatWarning;
pub const defaultShowWarning = api.defaultShowWarning;
pub const getState = api.getState;
pub const deinitState = api.deinitState;
pub const warn = api.warn;
pub const warnExplicit = api.warnExplicit;
pub const warnDeprecation = api.warnDeprecation;
pub const warnRuntime = api.warnRuntime;
pub const warnUser = api.warnUser;
pub const filterwarnings = api.filterwarnings;
pub const simplefilter = api.simplefilter;
pub const resetwarnings = api.resetwarnings;
pub const init = api.init;

// ============================================================================
// Tests
// ============================================================================

test "warning category names" {
    try std.testing.expectEqualStrings("DeprecationWarning", WarningCategory.DeprecationWarning.name());
    try std.testing.expectEqualStrings("UserWarning", WarningCategory.UserWarning.name());

    const cat = WarningCategory.fromString("RuntimeWarning");
    try std.testing.expect(cat != null);
    try std.testing.expectEqual(WarningCategory.RuntimeWarning, cat.?);

    const unknown = WarningCategory.fromString("UnknownWarning");
    try std.testing.expect(unknown == null);
}

test "warning action parsing" {
    try std.testing.expectEqual(WarningAction.error_action, WarningAction.fromString("error").?);
    try std.testing.expectEqual(WarningAction.ignore, WarningAction.fromString("ignore").?);
    try std.testing.expectEqual(WarningAction.always, WarningAction.fromString("always").?);
    try std.testing.expect(WarningAction.fromString("invalid") == null);
}

test "warning filter matching" {
    const filter1 = WarningFilter.init(.ignore, null, .DeprecationWarning, null, 0);
    try std.testing.expect(filter1.matches("test message", .DeprecationWarning, "mymodule", 10));
    try std.testing.expect(!filter1.matches("test message", .RuntimeWarning, "mymodule", 10));

    const filter2 = WarningFilter.init(.error_action, "test", null, "mymodule", 0);
    try std.testing.expect(filter2.matches("this is a test", .UserWarning, "mymodule.sub", 5));
    try std.testing.expect(!filter2.matches("no match", .UserWarning, "mymodule.sub", 5));
    try std.testing.expect(!filter2.matches("test", .UserWarning, "other", 5));
}

test "warnings state basic" {
    var state_instance = WarningsState.create(std.testing.allocator);
    defer state_instance.deinit();

    try std.testing.expect(state_instance.enabled);
    try std.testing.expectEqual(WarningAction.default, state_instance.default_action);

    // Add a filter
    const filter_instance = WarningFilter.init(.ignore, null, .DeprecationWarning, null, 0);
    try state_instance.addFilter(filter_instance);

    // Check action
    const action_result = state_instance.getAction("test", .DeprecationWarning, "module", 10);
    try std.testing.expectEqual(WarningAction.ignore, action_result);

    // Unmatched uses default
    const action2 = state_instance.getAction("test", .UserWarning, "module", 10);
    try std.testing.expectEqual(WarningAction.default, action2);
}

test "warning registry" {
    var registry_instance = WarningRegistry.init(std.testing.allocator);
    defer registry_instance.deinit();

    // Test once tracking
    try std.testing.expect(!registry_instance.wasShownOnce("msg", .UserWarning));
    try registry_instance.markShownOnce("msg", .UserWarning);
    try std.testing.expect(registry_instance.wasShownOnce("msg", .UserWarning));

    // Test location tracking
    try std.testing.expect(!registry_instance.wasShownAtLocation("msg2", .RuntimeWarning, 42));
    try registry_instance.markShownAtLocation("msg2", .RuntimeWarning, 42);
    try std.testing.expect(registry_instance.wasShownAtLocation("msg2", .RuntimeWarning, 42));
    try std.testing.expect(!registry_instance.wasShownAtLocation("msg2", .RuntimeWarning, 43));
}

test "format warning" {
    const formatted = try formatWarning(
        std.testing.allocator,
        "test.py",
        42,
        .DeprecationWarning,
        "This is deprecated",
    );
    defer std.testing.allocator.free(formatted);

    try std.testing.expectEqualStrings(
        "test.py:42: DeprecationWarning: This is deprecated",
        formatted,
    );
}
