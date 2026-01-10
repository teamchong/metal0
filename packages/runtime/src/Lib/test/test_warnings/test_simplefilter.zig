//! test.test_warnings.test_simplefilter - Comprehensive tests for simplefilter
//!
//! Tests the simplefilter function for setting simple warning filters.
//! Mirrors CPython's simplefilter tests.

const std = @import("std");
const warnings = @import("Lib.warnings");

// ============================================================================
// Test Types
// ============================================================================

/// Simple filter configuration for testing
pub const SimpleFilterConfig = struct {
    action: warnings.FilterAction,
    category: warnings.WarningCategory = .Warning,

    pub fn toFilter(self: SimpleFilterConfig) warnings.WarningFilter {
        return .{
            .action = self.action,
            .category = self.category,
        };
    }
};

/// Simple filter test harness
pub const SimpleFilterHarness = struct {
    state: warnings.WarningsState,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SimpleFilterHarness {
        return .{
            .state = warnings.WarningsState.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SimpleFilterHarness) void {
        self.state.deinit();
    }

    pub fn addSimpleFilter(self: *SimpleFilterHarness, action: warnings.FilterAction, category: warnings.WarningCategory) !void {
        try self.state.appendFilter(.{
            .action = action,
            .category = category,
        });
    }

    pub fn getAction(self: SimpleFilterHarness, message: []const u8, category: warnings.WarningCategory) warnings.FilterAction {
        return self.state.getAction(message, category, "<module>", 0);
    }

    pub fn getFilterCount(self: SimpleFilterHarness) usize {
        return self.state.filters.items.len;
    }

    pub fn reset(self: *SimpleFilterHarness) void {
        self.state.resetFilters();
    }
};

/// Action test case
pub const ActionTestCase = struct {
    action: warnings.FilterAction,
    expected_behavior: ExpectedBehavior,

    pub const ExpectedBehavior = enum {
        suppress,
        show,
        raise_error,
        show_once,
    };

    pub fn describe(self: ActionTestCase) []const u8 {
        return switch (self.expected_behavior) {
            .suppress => "warning should be suppressed",
            .show => "warning should be shown",
            .raise_error => "warning should raise error",
            .show_once => "warning should be shown once",
        };
    }
};

/// Filter priority tracker
pub const FilterPriorityTracker = struct {
    filters: std.ArrayList(SimpleFilterConfig),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FilterPriorityTracker {
        return .{
            .filters = std.ArrayList(SimpleFilterConfig).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FilterPriorityTracker) void {
        self.filters.deinit();
    }

    pub fn push(self: *FilterPriorityTracker, config: SimpleFilterConfig) !void {
        try self.filters.append(config);
    }

    pub fn pop(self: *FilterPriorityTracker) ?SimpleFilterConfig {
        if (self.filters.items.len > 0) {
            return self.filters.pop();
        }
        return null;
    }

    pub fn getTopAction(self: FilterPriorityTracker) ?warnings.FilterAction {
        if (self.filters.items.len > 0) {
            return self.filters.items[self.filters.items.len - 1].action;
        }
        return null;
    }

    pub fn count(self: FilterPriorityTracker) usize {
        return self.filters.items.len;
    }
};

// ============================================================================
// Basic SimpleFilter Tests
// ============================================================================

test "simplefilter_ignore" {
    var harness = SimpleFilterHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.addSimpleFilter(.ignore, .Warning);

    const action = harness.getAction("test", .UserWarning);
    try std.testing.expectEqual(warnings.FilterAction.ignore, action);
}

test "simplefilter_error" {
    var harness = SimpleFilterHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.addSimpleFilter(.@"error", .Warning);

    const action = harness.getAction("test", .UserWarning);
    try std.testing.expectEqual(warnings.FilterAction.@"error", action);
}

test "simplefilter_always" {
    var harness = SimpleFilterHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.addSimpleFilter(.always, .Warning);

    const action = harness.getAction("test", .UserWarning);
    try std.testing.expectEqual(warnings.FilterAction.always, action);
}

test "simplefilter_default" {
    var harness = SimpleFilterHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.addSimpleFilter(.default, .Warning);

    const action = harness.getAction("test", .UserWarning);
    try std.testing.expectEqual(warnings.FilterAction.default, action);
}

test "simplefilter_module" {
    var harness = SimpleFilterHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.addSimpleFilter(.module, .Warning);

    const action = harness.getAction("test", .UserWarning);
    try std.testing.expectEqual(warnings.FilterAction.module, action);
}

test "simplefilter_once" {
    var harness = SimpleFilterHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.addSimpleFilter(.once, .Warning);

    const action = harness.getAction("test", .UserWarning);
    try std.testing.expectEqual(warnings.FilterAction.once, action);
}

// ============================================================================
// Category-Specific Tests
// ============================================================================

test "simplefilter_deprecation_only" {
    var harness = SimpleFilterHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.addSimpleFilter(.ignore, .DeprecationWarning);

    // Should ignore DeprecationWarning
    const dep_action = harness.getAction("test", .DeprecationWarning);
    try std.testing.expectEqual(warnings.FilterAction.ignore, dep_action);

    // Should use default for other categories
    const user_action = harness.getAction("test", .UserWarning);
    try std.testing.expectEqual(warnings.FilterAction.default, user_action);
}

test "simplefilter_user_warning_only" {
    var harness = SimpleFilterHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.addSimpleFilter(.always, .UserWarning);

    // Should always show UserWarning
    const user_action = harness.getAction("test", .UserWarning);
    try std.testing.expectEqual(warnings.FilterAction.always, user_action);

    // Should use default for other categories
    const runtime_action = harness.getAction("test", .RuntimeWarning);
    try std.testing.expectEqual(warnings.FilterAction.default, runtime_action);
}

test "simplefilter_warning_matches_all" {
    var harness = SimpleFilterHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.addSimpleFilter(.ignore, .Warning);

    // Warning category should match all warning types
    const categories = [_]warnings.WarningCategory{
        .UserWarning,
        .DeprecationWarning,
        .RuntimeWarning,
        .SyntaxWarning,
        .FutureWarning,
    };

    for (categories) |cat| {
        const action = harness.getAction("test", cat);
        try std.testing.expectEqual(warnings.FilterAction.ignore, action);
    }
}

// ============================================================================
// Multiple Filters Tests
// ============================================================================

test "simplefilter_multiple_filters_first_wins" {
    var harness = SimpleFilterHarness.init(std.testing.allocator);
    defer harness.deinit();

    // Add ignore for DeprecationWarning first
    try harness.addSimpleFilter(.ignore, .DeprecationWarning);
    // Then add error for all warnings
    try harness.addSimpleFilter(.@"error", .Warning);

    // DeprecationWarning should match first filter
    const action = harness.getAction("test", .DeprecationWarning);
    try std.testing.expectEqual(warnings.FilterAction.ignore, action);
}

test "simplefilter_filter_order_matters" {
    var harness = SimpleFilterHarness.init(std.testing.allocator);
    defer harness.deinit();

    // Add error for all warnings first
    try harness.addSimpleFilter(.@"error", .Warning);
    // Then add ignore for DeprecationWarning (won't be reached for DeprecationWarning)
    try harness.addSimpleFilter(.ignore, .DeprecationWarning);

    // DeprecationWarning should match first (more general) filter
    const action = harness.getAction("test", .DeprecationWarning);
    try std.testing.expectEqual(warnings.FilterAction.@"error", action);
}

test "simplefilter_count" {
    var harness = SimpleFilterHarness.init(std.testing.allocator);
    defer harness.deinit();

    try std.testing.expectEqual(@as(usize, 0), harness.getFilterCount());

    try harness.addSimpleFilter(.ignore, .Warning);
    try std.testing.expectEqual(@as(usize, 1), harness.getFilterCount());

    try harness.addSimpleFilter(.always, .DeprecationWarning);
    try std.testing.expectEqual(@as(usize, 2), harness.getFilterCount());
}

test "simplefilter_reset" {
    var harness = SimpleFilterHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.addSimpleFilter(.ignore, .Warning);
    try harness.addSimpleFilter(.always, .DeprecationWarning);
    try std.testing.expectEqual(@as(usize, 2), harness.getFilterCount());

    harness.reset();
    try std.testing.expectEqual(@as(usize, 0), harness.getFilterCount());
}

// ============================================================================
// SimpleFilterConfig Tests
// ============================================================================

test "config_to_filter" {
    const config = SimpleFilterConfig{
        .action = .ignore,
        .category = .DeprecationWarning,
    };

    const filter = config.toFilter();
    try std.testing.expectEqual(warnings.FilterAction.ignore, filter.action);
    try std.testing.expectEqual(warnings.WarningCategory.DeprecationWarning, filter.category);
}

test "config_default_category" {
    const config = SimpleFilterConfig{
        .action = .always,
    };

    try std.testing.expectEqual(warnings.WarningCategory.Warning, config.category);
}

// ============================================================================
// ActionTestCase Tests
// ============================================================================

test "action_test_case_describe" {
    const cases = [_]ActionTestCase{
        .{ .action = .ignore, .expected_behavior = .suppress },
        .{ .action = .always, .expected_behavior = .show },
        .{ .action = .@"error", .expected_behavior = .raise_error },
        .{ .action = .once, .expected_behavior = .show_once },
    };

    for (cases) |case| {
        const description = case.describe();
        try std.testing.expect(description.len > 0);
    }
}

// ============================================================================
// FilterPriorityTracker Tests
// ============================================================================

test "priority_tracker_push_pop" {
    var tracker = FilterPriorityTracker.init(std.testing.allocator);
    defer tracker.deinit();

    try tracker.push(.{ .action = .ignore });
    try tracker.push(.{ .action = .always });
    try tracker.push(.{ .action = .@"error" });

    try std.testing.expectEqual(@as(usize, 3), tracker.count());

    const popped = tracker.pop();
    try std.testing.expectEqual(warnings.FilterAction.@"error", popped.?.action);
    try std.testing.expectEqual(@as(usize, 2), tracker.count());
}

test "priority_tracker_get_top" {
    var tracker = FilterPriorityTracker.init(std.testing.allocator);
    defer tracker.deinit();

    try std.testing.expect(tracker.getTopAction() == null);

    try tracker.push(.{ .action = .ignore });
    try std.testing.expectEqual(warnings.FilterAction.ignore, tracker.getTopAction().?);

    try tracker.push(.{ .action = .always });
    try std.testing.expectEqual(warnings.FilterAction.always, tracker.getTopAction().?);
}

test "priority_tracker_empty_pop" {
    var tracker = FilterPriorityTracker.init(std.testing.allocator);
    defer tracker.deinit();

    try std.testing.expect(tracker.pop() == null);
}

// ============================================================================
// Integration Tests
// ============================================================================

test "integration_simplefilter_workflow" {
    var harness = SimpleFilterHarness.init(std.testing.allocator);
    defer harness.deinit();

    // Start with ignoring deprecation warnings
    try harness.addSimpleFilter(.ignore, .DeprecationWarning);

    // Check that deprecation is ignored
    var action = harness.getAction("deprecated feature", .DeprecationWarning);
    try std.testing.expectEqual(warnings.FilterAction.ignore, action);

    // User warnings still use default
    action = harness.getAction("user issue", .UserWarning);
    try std.testing.expectEqual(warnings.FilterAction.default, action);

    // Add always show for user warnings
    try harness.addSimpleFilter(.always, .UserWarning);

    // Now user warnings should be shown
    action = harness.getAction("user issue", .UserWarning);
    try std.testing.expectEqual(warnings.FilterAction.always, action);
}

test "integration_all_actions" {
    var harness = SimpleFilterHarness.init(std.testing.allocator);
    defer harness.deinit();

    const actions = [_]warnings.FilterAction{
        .default,
        .@"error",
        .ignore,
        .always,
        .module,
        .once,
    };

    for (actions) |action| {
        harness.reset();
        try harness.addSimpleFilter(action, .Warning);

        const result = harness.getAction("test", .UserWarning);
        try std.testing.expectEqual(action, result);
    }
}

test "integration_category_hierarchy" {
    var harness = SimpleFilterHarness.init(std.testing.allocator);
    defer harness.deinit();

    // Add filter for base Warning
    try harness.addSimpleFilter(.always, .Warning);

    // All specific categories should match
    const categories = [_]warnings.WarningCategory{
        .Warning,
        .UserWarning,
        .DeprecationWarning,
        .PendingDeprecationWarning,
        .SyntaxWarning,
        .RuntimeWarning,
        .FutureWarning,
        .ImportWarning,
        .UnicodeWarning,
        .BytesWarning,
        .EncodingWarning,
        .ResourceWarning,
    };

    for (categories) |cat| {
        const action = harness.getAction("test", cat);
        try std.testing.expectEqual(warnings.FilterAction.always, action);
    }
}
