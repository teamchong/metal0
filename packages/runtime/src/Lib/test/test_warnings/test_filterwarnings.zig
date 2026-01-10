//! test.test_warnings.test_filterwarnings - Comprehensive tests for filterwarnings
//!
//! Tests the filterwarnings function for adding detailed warning filters.
//! Mirrors CPython's filterwarnings tests.

const std = @import("std");
const warnings = @import("Lib.warnings");

// ============================================================================
// Test Types
// ============================================================================

/// Filter specification for testing
pub const FilterSpec = struct {
    action: warnings.FilterAction,
    message: ?[]const u8 = null,
    category: warnings.WarningCategory = .Warning,
    module: ?[]const u8 = null,
    lineno: ?usize = null,

    pub fn toFilter(self: FilterSpec) warnings.WarningFilter {
        return .{
            .action = self.action,
            .message = self.message,
            .category = self.category,
            .module = self.module,
            .lineno = self.lineno,
        };
    }

    pub fn matches(
        self: FilterSpec,
        message: []const u8,
        category: warnings.WarningCategory,
        module_name: []const u8,
        lineno: usize,
    ) bool {
        return self.toFilter().matches(message, category, module_name, lineno);
    }
};

/// Filterwarnings test harness
pub const FilterwarningsHarness = struct {
    state: warnings.WarningsState,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FilterwarningsHarness {
        return .{
            .state = warnings.WarningsState.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FilterwarningsHarness) void {
        self.state.deinit();
    }

    pub fn filterwarnings(
        self: *FilterwarningsHarness,
        action: warnings.FilterAction,
        message: ?[]const u8,
        category: warnings.WarningCategory,
        module: ?[]const u8,
        lineno: ?usize,
    ) !void {
        try self.state.insertFilter(.{
            .action = action,
            .message = message,
            .category = category,
            .module = module,
            .lineno = lineno,
        });
    }

    pub fn getAction(
        self: FilterwarningsHarness,
        message: []const u8,
        category: warnings.WarningCategory,
        module_name: []const u8,
        lineno: usize,
    ) warnings.FilterAction {
        return self.state.getAction(message, category, module_name, lineno);
    }

    pub fn getFilterCount(self: FilterwarningsHarness) usize {
        return self.state.filters.items.len;
    }

    pub fn resetwarnings(self: *FilterwarningsHarness) void {
        self.state.resetFilters();
    }
};

/// Test case for filterwarnings
pub const FilterwarningsTestCase = struct {
    name: []const u8,
    specs: []const FilterSpec,
    test_message: []const u8,
    test_category: warnings.WarningCategory,
    test_module: []const u8,
    test_lineno: usize,
    expected_action: warnings.FilterAction,

    pub fn run(self: FilterwarningsTestCase, allocator: std.mem.Allocator) !bool {
        var harness = FilterwarningsHarness.init(allocator);
        defer harness.deinit();

        for (self.specs) |spec| {
            try harness.filterwarnings(
                spec.action,
                spec.message,
                spec.category,
                spec.module,
                spec.lineno,
            );
        }

        const action = harness.getAction(
            self.test_message,
            self.test_category,
            self.test_module,
            self.test_lineno,
        );

        return action == self.expected_action;
    }
};

/// Filter registry for tracking applied filters
pub const FilterRegistry = struct {
    filters: std.ArrayList(FilterSpec),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FilterRegistry {
        return .{
            .filters = std.ArrayList(FilterSpec).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FilterRegistry) void {
        self.filters.deinit();
    }

    pub fn register(self: *FilterRegistry, spec: FilterSpec) !void {
        try self.filters.append(spec);
    }

    pub fn unregister(self: *FilterRegistry, index: usize) void {
        if (index < self.filters.items.len) {
            _ = self.filters.orderedRemove(index);
        }
    }

    pub fn count(self: FilterRegistry) usize {
        return self.filters.items.len;
    }

    pub fn getFirst(self: FilterRegistry) ?FilterSpec {
        if (self.filters.items.len > 0) {
            return self.filters.items[0];
        }
        return null;
    }

    pub fn getLast(self: FilterRegistry) ?FilterSpec {
        if (self.filters.items.len > 0) {
            return self.filters.items[self.filters.items.len - 1];
        }
        return null;
    }
};

// ============================================================================
// Basic Filterwarnings Tests
// ============================================================================

test "filterwarnings_basic" {
    var harness = FilterwarningsHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.filterwarnings(.ignore, null, .Warning, null, null);

    const action = harness.getAction("test", .UserWarning, "module", 1);
    try std.testing.expectEqual(warnings.FilterAction.ignore, action);
}

test "filterwarnings_with_message" {
    var harness = FilterwarningsHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.filterwarnings(.ignore, "deprecated", .Warning, null, null);

    // Should match message containing "deprecated"
    var action = harness.getAction("deprecated feature", .UserWarning, "mod", 1);
    try std.testing.expectEqual(warnings.FilterAction.ignore, action);

    // Should not match other messages (uses default)
    action = harness.getAction("other warning", .UserWarning, "mod", 1);
    try std.testing.expectEqual(warnings.FilterAction.default, action);
}

test "filterwarnings_with_category" {
    var harness = FilterwarningsHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.filterwarnings(.ignore, null, .DeprecationWarning, null, null);

    // Should match DeprecationWarning
    var action = harness.getAction("test", .DeprecationWarning, "mod", 1);
    try std.testing.expectEqual(warnings.FilterAction.ignore, action);

    // Should not match UserWarning
    action = harness.getAction("test", .UserWarning, "mod", 1);
    try std.testing.expectEqual(warnings.FilterAction.default, action);
}

test "filterwarnings_with_module" {
    var harness = FilterwarningsHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.filterwarnings(.ignore, null, .Warning, "mymodule", null);

    // Should match module containing "mymodule"
    var action = harness.getAction("test", .UserWarning, "mymodule.submod", 1);
    try std.testing.expectEqual(warnings.FilterAction.ignore, action);

    // Should not match other modules
    action = harness.getAction("test", .UserWarning, "othermodule", 1);
    try std.testing.expectEqual(warnings.FilterAction.default, action);
}

test "filterwarnings_with_lineno" {
    var harness = FilterwarningsHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.filterwarnings(.ignore, null, .Warning, null, 42);

    // Should match specific line
    var action = harness.getAction("test", .UserWarning, "mod", 42);
    try std.testing.expectEqual(warnings.FilterAction.ignore, action);

    // Should not match other lines
    action = harness.getAction("test", .UserWarning, "mod", 1);
    try std.testing.expectEqual(warnings.FilterAction.default, action);
}

// ============================================================================
// Combined Criteria Tests
// ============================================================================

test "filterwarnings_combined" {
    var harness = FilterwarningsHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.filterwarnings(
        .ignore,
        "deprecated",
        .DeprecationWarning,
        "mymodule",
        null,
    );

    // Should match when all criteria met
    var action = harness.getAction("deprecated feature", .DeprecationWarning, "mymodule", 1);
    try std.testing.expectEqual(warnings.FilterAction.ignore, action);

    // Should not match when message doesn't match
    action = harness.getAction("other", .DeprecationWarning, "mymodule", 1);
    try std.testing.expectEqual(warnings.FilterAction.default, action);

    // Should not match when category doesn't match
    action = harness.getAction("deprecated", .UserWarning, "mymodule", 1);
    try std.testing.expectEqual(warnings.FilterAction.default, action);

    // Should not match when module doesn't match
    action = harness.getAction("deprecated", .DeprecationWarning, "other", 1);
    try std.testing.expectEqual(warnings.FilterAction.default, action);
}

test "filterwarnings_all_criteria" {
    var harness = FilterwarningsHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.filterwarnings(
        .@"error",
        "critical",
        .RuntimeWarning,
        "critical_module",
        100,
    );

    // Should match only when ALL criteria match
    var action = harness.getAction("critical issue", .RuntimeWarning, "critical_module", 100);
    try std.testing.expectEqual(warnings.FilterAction.@"error", action);

    // Any mismatch should fail
    action = harness.getAction("critical issue", .RuntimeWarning, "critical_module", 99);
    try std.testing.expectEqual(warnings.FilterAction.default, action);
}

// ============================================================================
// Filter Priority Tests
// ============================================================================

test "filterwarnings_insert_at_front" {
    var harness = FilterwarningsHarness.init(std.testing.allocator);
    defer harness.deinit();

    // Add general filter first
    try harness.filterwarnings(.always, null, .Warning, null, null);
    // Then add specific filter (should go to front)
    try harness.filterwarnings(.ignore, null, .DeprecationWarning, null, null);

    // Specific filter should be checked first
    const action = harness.getAction("test", .DeprecationWarning, "mod", 1);
    try std.testing.expectEqual(warnings.FilterAction.ignore, action);
}

test "filterwarnings_order" {
    var harness = FilterwarningsHarness.init(std.testing.allocator);
    defer harness.deinit();

    // Add filters in sequence
    try harness.filterwarnings(.ignore, "first", .Warning, null, null);
    try harness.filterwarnings(.@"error", "second", .Warning, null, null);
    try harness.filterwarnings(.always, "third", .Warning, null, null);

    // Most recently added should be at front
    const action = harness.getAction("third warning", .UserWarning, "mod", 1);
    try std.testing.expectEqual(warnings.FilterAction.always, action);
}

test "filterwarnings_count" {
    var harness = FilterwarningsHarness.init(std.testing.allocator);
    defer harness.deinit();

    try std.testing.expectEqual(@as(usize, 0), harness.getFilterCount());

    try harness.filterwarnings(.ignore, null, .Warning, null, null);
    try std.testing.expectEqual(@as(usize, 1), harness.getFilterCount());

    try harness.filterwarnings(.@"error", "test", .UserWarning, null, null);
    try std.testing.expectEqual(@as(usize, 2), harness.getFilterCount());
}

test "filterwarnings_reset" {
    var harness = FilterwarningsHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.filterwarnings(.ignore, null, .Warning, null, null);
    try harness.filterwarnings(.@"error", null, .DeprecationWarning, null, null);
    try std.testing.expectEqual(@as(usize, 2), harness.getFilterCount());

    harness.resetwarnings();
    try std.testing.expectEqual(@as(usize, 0), harness.getFilterCount());
}

// ============================================================================
// FilterSpec Tests
// ============================================================================

test "filter_spec_default" {
    const spec = FilterSpec{ .action = .ignore };

    try std.testing.expectEqual(warnings.FilterAction.ignore, spec.action);
    try std.testing.expect(spec.message == null);
    try std.testing.expectEqual(warnings.WarningCategory.Warning, spec.category);
    try std.testing.expect(spec.module == null);
    try std.testing.expect(spec.lineno == null);
}

test "filter_spec_to_filter" {
    const spec = FilterSpec{
        .action = .@"error",
        .message = "deprecated",
        .category = .DeprecationWarning,
        .module = "mymodule",
        .lineno = 42,
    };

    const filter = spec.toFilter();
    try std.testing.expectEqual(warnings.FilterAction.@"error", filter.action);
    try std.testing.expectEqualStrings("deprecated", filter.message.?);
    try std.testing.expectEqual(warnings.WarningCategory.DeprecationWarning, filter.category);
    try std.testing.expectEqualStrings("mymodule", filter.module.?);
    try std.testing.expectEqual(@as(usize, 42), filter.lineno.?);
}

test "filter_spec_matches" {
    const spec = FilterSpec{
        .action = .ignore,
        .message = "deprecated",
        .category = .DeprecationWarning,
    };

    try std.testing.expect(spec.matches("deprecated feature", .DeprecationWarning, "mod", 1));
    try std.testing.expect(!spec.matches("other warning", .DeprecationWarning, "mod", 1));
    try std.testing.expect(!spec.matches("deprecated", .UserWarning, "mod", 1));
}

// ============================================================================
// FilterRegistry Tests
// ============================================================================

test "registry_init" {
    var registry = FilterRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try std.testing.expectEqual(@as(usize, 0), registry.count());
}

test "registry_register" {
    var registry = FilterRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.register(.{ .action = .ignore });
    try registry.register(.{ .action = .@"error" });

    try std.testing.expectEqual(@as(usize, 2), registry.count());
}

test "registry_unregister" {
    var registry = FilterRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.register(.{ .action = .ignore });
    try registry.register(.{ .action = .@"error" });
    try registry.register(.{ .action = .always });

    registry.unregister(1);
    try std.testing.expectEqual(@as(usize, 2), registry.count());
}

test "registry_get_first_last" {
    var registry = FilterRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try std.testing.expect(registry.getFirst() == null);
    try std.testing.expect(registry.getLast() == null);

    try registry.register(.{ .action = .ignore });
    try registry.register(.{ .action = .@"error" });
    try registry.register(.{ .action = .always });

    try std.testing.expectEqual(warnings.FilterAction.ignore, registry.getFirst().?.action);
    try std.testing.expectEqual(warnings.FilterAction.always, registry.getLast().?.action);
}

// ============================================================================
// TestCase Tests
// ============================================================================

test "test_case_run" {
    const case = FilterwarningsTestCase{
        .name = "basic ignore",
        .specs = &[_]FilterSpec{
            .{ .action = .ignore, .category = .DeprecationWarning },
        },
        .test_message = "test",
        .test_category = .DeprecationWarning,
        .test_module = "mod",
        .test_lineno = 1,
        .expected_action = .ignore,
    };

    const result = try case.run(std.testing.allocator);
    try std.testing.expect(result);
}

test "test_case_multiple_filters" {
    const case = FilterwarningsTestCase{
        .name = "multiple filters",
        .specs = &[_]FilterSpec{
            .{ .action = .always, .category = .Warning },
            .{ .action = .ignore, .category = .DeprecationWarning },
        },
        .test_message = "test",
        .test_category = .DeprecationWarning,
        .test_module = "mod",
        .test_lineno = 1,
        .expected_action = .ignore, // Last added is first checked
    };

    const result = try case.run(std.testing.allocator);
    try std.testing.expect(result);
}

// ============================================================================
// All Actions Tests
// ============================================================================

test "filterwarnings_all_actions" {
    var harness = FilterwarningsHarness.init(std.testing.allocator);
    defer harness.deinit();

    const actions = [_]warnings.FilterAction{
        .default,
        .@"error",
        .ignore,
        .always,
        .module,
        .once,
    };

    for (actions, 0..) |action, i| {
        const msg = switch (i) {
            0 => "default",
            1 => "error",
            2 => "ignore",
            3 => "always",
            4 => "module",
            5 => "once",
            else => "unknown",
        };

        try harness.filterwarnings(action, msg, .Warning, null, null);
    }

    try std.testing.expectEqual(@as(usize, 6), harness.getFilterCount());
}

// ============================================================================
// Integration Tests
// ============================================================================

test "integration_filterwarnings_workflow" {
    var harness = FilterwarningsHarness.init(std.testing.allocator);
    defer harness.deinit();

    // Ignore all deprecation warnings
    try harness.filterwarnings(.ignore, null, .DeprecationWarning, null, null);

    // But treat critical deprecations as errors
    try harness.filterwarnings(.@"error", "critical", .DeprecationWarning, null, null);

    // Critical should be error (checked first)
    var action = harness.getAction("critical feature", .DeprecationWarning, "mod", 1);
    try std.testing.expectEqual(warnings.FilterAction.@"error", action);

    // Non-critical should be ignored
    action = harness.getAction("old feature", .DeprecationWarning, "mod", 1);
    try std.testing.expectEqual(warnings.FilterAction.ignore, action);

    // Other warnings use default
    action = harness.getAction("test", .UserWarning, "mod", 1);
    try std.testing.expectEqual(warnings.FilterAction.default, action);
}

test "integration_module_specific_filters" {
    var harness = FilterwarningsHarness.init(std.testing.allocator);
    defer harness.deinit();

    // Ignore all warnings from test modules
    try harness.filterwarnings(.ignore, null, .Warning, "test_", null);

    // But show warnings from the main module
    try harness.filterwarnings(.always, null, .Warning, "main", null);

    // Test module warnings should be ignored
    var action = harness.getAction("test", .UserWarning, "test_module", 1);
    try std.testing.expectEqual(warnings.FilterAction.ignore, action);

    // Main module warnings should be shown
    action = harness.getAction("test", .UserWarning, "main_module", 1);
    try std.testing.expectEqual(warnings.FilterAction.always, action);
}

test "integration_complex_filter_chain" {
    var harness = FilterwarningsHarness.init(std.testing.allocator);
    defer harness.deinit();

    // Base rule: show all warnings
    try harness.filterwarnings(.always, null, .Warning, null, null);

    // Exception: ignore deprecation warnings
    try harness.filterwarnings(.ignore, null, .DeprecationWarning, null, null);

    // Exception to exception: error on future deprecations
    try harness.filterwarnings(.@"error", "future", .DeprecationWarning, null, null);

    // Future deprecation should be error
    var action = harness.getAction("future removal", .DeprecationWarning, "mod", 1);
    try std.testing.expectEqual(warnings.FilterAction.@"error", action);

    // Regular deprecation should be ignored
    action = harness.getAction("old feature", .DeprecationWarning, "mod", 1);
    try std.testing.expectEqual(warnings.FilterAction.ignore, action);

    // Other warnings should be shown
    action = harness.getAction("test", .UserWarning, "mod", 1);
    try std.testing.expectEqual(warnings.FilterAction.always, action);
}
