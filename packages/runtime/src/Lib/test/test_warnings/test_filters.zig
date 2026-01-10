//! test.test_warnings.test_filters - Comprehensive tests for warning filters
//!
//! Tests the warning filter system including filter creation, matching, priorities,
//! and filter chain behavior. Mirrors CPython's test_warnings filter tests.

const std = @import("std");
const warnings = @import("Lib.warnings");

// ============================================================================
// Test Types
// ============================================================================

/// Test filter configuration
pub const FilterConfig = struct {
    action: warnings.FilterAction,
    message: ?[]const u8 = null,
    category: warnings.WarningCategory = .Warning,
    module: ?[]const u8 = null,
    lineno: ?usize = null,

    pub fn toWarningFilter(self: FilterConfig) warnings.WarningFilter {
        return .{
            .action = self.action,
            .message = self.message,
            .category = self.category,
            .module = self.module,
            .lineno = self.lineno,
        };
    }
};

/// Test result collector
pub const FilterTestResult = struct {
    matched: bool,
    action: ?warnings.FilterAction,
    filter_index: ?usize,

    pub fn init() FilterTestResult {
        return .{
            .matched = false,
            .action = null,
            .filter_index = null,
        };
    }
};

/// Filter test harness
pub const FilterTestHarness = struct {
    filters: std.ArrayList(warnings.WarningFilter),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FilterTestHarness {
        return .{
            .filters = std.ArrayList(warnings.WarningFilter).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FilterTestHarness) void {
        self.filters.deinit();
    }

    pub fn addFilter(self: *FilterTestHarness, config: FilterConfig) !void {
        try self.filters.append(config.toWarningFilter());
    }

    pub fn insertFilter(self: *FilterTestHarness, index: usize, config: FilterConfig) !void {
        try self.filters.insert(index, config.toWarningFilter());
    }

    pub fn testMatch(
        self: FilterTestHarness,
        message: []const u8,
        category: warnings.WarningCategory,
        module_name: []const u8,
        lineno: usize,
    ) FilterTestResult {
        var result = FilterTestResult.init();

        for (self.filters.items, 0..) |filter, i| {
            if (filter.matches(message, category, module_name, lineno)) {
                result.matched = true;
                result.action = filter.action;
                result.filter_index = i;
                break;
            }
        }

        return result;
    }

    pub fn clear(self: *FilterTestHarness) void {
        self.filters.clearRetainingCapacity();
    }

    pub fn count(self: FilterTestHarness) usize {
        return self.filters.items.len;
    }
};

// ============================================================================
// Filter Creation Tests
// ============================================================================

test "filter_creation_default" {
    const filter = warnings.WarningFilter{
        .action = .default,
    };
    try std.testing.expectEqual(warnings.FilterAction.default, filter.action);
    try std.testing.expect(filter.message == null);
    try std.testing.expectEqual(warnings.WarningCategory.Warning, filter.category);
    try std.testing.expect(filter.module == null);
    try std.testing.expect(filter.lineno == null);
}

test "filter_creation_with_all_fields" {
    const filter = warnings.WarningFilter{
        .action = .ignore,
        .message = "deprecated",
        .category = .DeprecationWarning,
        .module = "mymodule",
        .lineno = 42,
    };
    try std.testing.expectEqual(warnings.FilterAction.ignore, filter.action);
    try std.testing.expectEqualStrings("deprecated", filter.message.?);
    try std.testing.expectEqual(warnings.WarningCategory.DeprecationWarning, filter.category);
    try std.testing.expectEqualStrings("mymodule", filter.module.?);
    try std.testing.expectEqual(@as(usize, 42), filter.lineno.?);
}

test "filter_action_all_types" {
    const actions = [_]warnings.FilterAction{
        .default,
        .@"error",
        .ignore,
        .always,
        .module,
        .once,
    };

    for (actions) |action| {
        const filter = warnings.WarningFilter{ .action = action };
        try std.testing.expectEqual(action, filter.action);
    }
}

// ============================================================================
// Filter Matching Tests
// ============================================================================

test "filter_matches_any_warning" {
    const filter = warnings.WarningFilter{
        .action = .always,
        .category = .Warning,
    };

    // Should match all warning types (all are subclass of Warning)
    try std.testing.expect(filter.matches("test", .UserWarning, "mod", 1));
    try std.testing.expect(filter.matches("test", .DeprecationWarning, "mod", 1));
    try std.testing.expect(filter.matches("test", .RuntimeWarning, "mod", 1));
    try std.testing.expect(filter.matches("test", .FutureWarning, "mod", 1));
}

test "filter_matches_specific_category" {
    const filter = warnings.WarningFilter{
        .action = .ignore,
        .category = .DeprecationWarning,
    };

    // Should match DeprecationWarning
    try std.testing.expect(filter.matches("test", .DeprecationWarning, "mod", 1));

    // Should not match other categories (not subclasses of DeprecationWarning)
    try std.testing.expect(!filter.matches("test", .UserWarning, "mod", 1));
    try std.testing.expect(!filter.matches("test", .RuntimeWarning, "mod", 1));
}

test "filter_matches_message_pattern" {
    const filter = warnings.WarningFilter{
        .action = .ignore,
        .message = "deprecated",
    };

    // Should match messages containing "deprecated"
    try std.testing.expect(filter.matches("this is deprecated", .UserWarning, "mod", 1));
    try std.testing.expect(filter.matches("deprecated feature", .UserWarning, "mod", 1));
    try std.testing.expect(filter.matches("deprecated", .UserWarning, "mod", 1));

    // Should not match messages without "deprecated"
    try std.testing.expect(!filter.matches("old feature", .UserWarning, "mod", 1));
    try std.testing.expect(!filter.matches("warning message", .UserWarning, "mod", 1));
}

test "filter_matches_module_pattern" {
    const filter = warnings.WarningFilter{
        .action = .ignore,
        .module = "mypackage",
    };

    // Should match modules containing "mypackage"
    try std.testing.expect(filter.matches("test", .UserWarning, "mypackage.module", 1));
    try std.testing.expect(filter.matches("test", .UserWarning, "mypackage", 1));
    try std.testing.expect(filter.matches("test", .UserWarning, "test.mypackage.sub", 1));

    // Should not match other modules
    try std.testing.expect(!filter.matches("test", .UserWarning, "otherpackage", 1));
}

test "filter_matches_specific_lineno" {
    const filter = warnings.WarningFilter{
        .action = .ignore,
        .lineno = 42,
    };

    // Should match specific line number
    try std.testing.expect(filter.matches("test", .UserWarning, "mod", 42));

    // Should not match other line numbers
    try std.testing.expect(!filter.matches("test", .UserWarning, "mod", 1));
    try std.testing.expect(!filter.matches("test", .UserWarning, "mod", 100));
}

test "filter_lineno_zero_matches_all" {
    const filter = warnings.WarningFilter{
        .action = .ignore,
        .lineno = 0,
    };

    // Lineno 0 should match any line
    try std.testing.expect(filter.matches("test", .UserWarning, "mod", 0));
    try std.testing.expect(filter.matches("test", .UserWarning, "mod", 1));
    try std.testing.expect(filter.matches("test", .UserWarning, "mod", 999));
}

test "filter_combined_criteria" {
    const filter = warnings.WarningFilter{
        .action = .ignore,
        .message = "deprecated",
        .category = .DeprecationWarning,
        .module = "mymodule",
    };

    // Should match when all criteria are met
    try std.testing.expect(filter.matches("deprecated feature", .DeprecationWarning, "mymodule", 1));

    // Should not match when any criterion fails
    try std.testing.expect(!filter.matches("other message", .DeprecationWarning, "mymodule", 1));
    try std.testing.expect(!filter.matches("deprecated", .UserWarning, "mymodule", 1));
    try std.testing.expect(!filter.matches("deprecated", .DeprecationWarning, "other", 1));
}

// ============================================================================
// Filter Chain Tests
// ============================================================================

test "filter_chain_first_match_wins" {
    var harness = FilterTestHarness.init(std.testing.allocator);
    defer harness.deinit();

    // Add filters in order
    try harness.addFilter(.{ .action = .ignore, .category = .DeprecationWarning });
    try harness.addFilter(.{ .action = .@"error", .category = .Warning });

    // DeprecationWarning should match first filter (ignore)
    const result = harness.testMatch("test", .DeprecationWarning, "mod", 1);
    try std.testing.expect(result.matched);
    try std.testing.expectEqual(warnings.FilterAction.ignore, result.action.?);
    try std.testing.expectEqual(@as(usize, 0), result.filter_index.?);
}

test "filter_chain_fallthrough" {
    var harness = FilterTestHarness.init(std.testing.allocator);
    defer harness.deinit();

    // First filter only matches DeprecationWarning
    try harness.addFilter(.{ .action = .ignore, .category = .DeprecationWarning });
    // Second filter catches everything else
    try harness.addFilter(.{ .action = .@"error", .category = .Warning });

    // UserWarning should fall through to second filter
    const result = harness.testMatch("test", .UserWarning, "mod", 1);
    try std.testing.expect(result.matched);
    try std.testing.expectEqual(warnings.FilterAction.@"error", result.action.?);
    try std.testing.expectEqual(@as(usize, 1), result.filter_index.?);
}

test "filter_chain_no_match" {
    var harness = FilterTestHarness.init(std.testing.allocator);
    defer harness.deinit();

    // Filter only matches specific message
    try harness.addFilter(.{ .action = .ignore, .message = "specific" });

    // Non-matching message should not match any filter
    const result = harness.testMatch("other message", .UserWarning, "mod", 1);
    try std.testing.expect(!result.matched);
    try std.testing.expect(result.action == null);
}

test "filter_chain_priority_order" {
    var harness = FilterTestHarness.init(std.testing.allocator);
    defer harness.deinit();

    // More general filter first
    try harness.addFilter(.{ .action = .always, .category = .Warning });
    // More specific filter second - won't be reached
    try harness.addFilter(.{ .action = .ignore, .category = .DeprecationWarning });

    // DeprecationWarning matches the first (more general) filter
    const result = harness.testMatch("test", .DeprecationWarning, "mod", 1);
    try std.testing.expectEqual(warnings.FilterAction.always, result.action.?);
    try std.testing.expectEqual(@as(usize, 0), result.filter_index.?);
}

test "filter_insert_at_front" {
    var harness = FilterTestHarness.init(std.testing.allocator);
    defer harness.deinit();

    // Add general filter
    try harness.addFilter(.{ .action = .always, .category = .Warning });
    // Insert specific filter at front
    try harness.insertFilter(0, .{ .action = .ignore, .category = .DeprecationWarning });

    // Now DeprecationWarning should match the inserted filter
    const result = harness.testMatch("test", .DeprecationWarning, "mod", 1);
    try std.testing.expectEqual(warnings.FilterAction.ignore, result.action.?);
    try std.testing.expectEqual(@as(usize, 0), result.filter_index.?);
}

// ============================================================================
// Filter Action String Conversion Tests
// ============================================================================

test "filter_action_from_string" {
    try std.testing.expectEqual(warnings.FilterAction.default, warnings.FilterAction.fromString("default").?);
    try std.testing.expectEqual(warnings.FilterAction.@"error", warnings.FilterAction.fromString("error").?);
    try std.testing.expectEqual(warnings.FilterAction.ignore, warnings.FilterAction.fromString("ignore").?);
    try std.testing.expectEqual(warnings.FilterAction.always, warnings.FilterAction.fromString("always").?);
    try std.testing.expectEqual(warnings.FilterAction.module, warnings.FilterAction.fromString("module").?);
    try std.testing.expectEqual(warnings.FilterAction.once, warnings.FilterAction.fromString("once").?);
}

test "filter_action_from_string_invalid" {
    try std.testing.expect(warnings.FilterAction.fromString("invalid") == null);
    try std.testing.expect(warnings.FilterAction.fromString("") == null);
    try std.testing.expect(warnings.FilterAction.fromString("ERROR") == null); // Case sensitive
}

test "filter_action_to_string" {
    try std.testing.expectEqualStrings("default", warnings.FilterAction.default.toString());
    try std.testing.expectEqualStrings("error", warnings.FilterAction.@"error".toString());
    try std.testing.expectEqualStrings("ignore", warnings.FilterAction.ignore.toString());
    try std.testing.expectEqualStrings("always", warnings.FilterAction.always.toString());
    try std.testing.expectEqualStrings("module", warnings.FilterAction.module.toString());
    try std.testing.expectEqualStrings("once", warnings.FilterAction.once.toString());
}

test "filter_action_roundtrip" {
    const actions = [_]warnings.FilterAction{
        .default,
        .@"error",
        .ignore,
        .always,
        .module,
        .once,
    };

    for (actions) |action| {
        const str = action.toString();
        const parsed = warnings.FilterAction.fromString(str);
        try std.testing.expectEqual(action, parsed.?);
    }
}

// ============================================================================
// Filter Harness Utility Tests
// ============================================================================

test "harness_clear" {
    var harness = FilterTestHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.addFilter(.{ .action = .ignore });
    try harness.addFilter(.{ .action = .always });
    try std.testing.expectEqual(@as(usize, 2), harness.count());

    harness.clear();
    try std.testing.expectEqual(@as(usize, 0), harness.count());
}

test "harness_multiple_filters" {
    var harness = FilterTestHarness.init(std.testing.allocator);
    defer harness.deinit();

    // Add 10 filters
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        try harness.addFilter(.{ .action = .ignore });
    }

    try std.testing.expectEqual(@as(usize, 10), harness.count());
}
