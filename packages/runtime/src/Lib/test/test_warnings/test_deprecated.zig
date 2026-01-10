//! test.test_warnings.test_deprecated - Comprehensive tests for deprecation warnings
//!
//! Tests for DeprecationWarning, PendingDeprecationWarning, and FutureWarning
//! handling. Mirrors CPython's deprecation warning tests.

const std = @import("std");
const warnings = @import("Lib.warnings");

// ============================================================================
// Test Types
// ============================================================================

/// Deprecation warning info
pub const DeprecationInfo = struct {
    feature: []const u8,
    version: ?[]const u8 = null,
    replacement: ?[]const u8 = null,
    category: DeprecationCategory = .current,

    pub const DeprecationCategory = enum {
        current, // DeprecationWarning
        pending, // PendingDeprecationWarning
        future, // FutureWarning
    };

    pub fn toWarningCategory(self: DeprecationInfo) warnings.WarningCategory {
        return switch (self.category) {
            .current => .DeprecationWarning,
            .pending => .PendingDeprecationWarning,
            .future => .FutureWarning,
        };
    }

    pub fn formatMessage(self: DeprecationInfo, allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        const writer = result.writer();

        try writer.print("{s} is deprecated", .{self.feature});

        if (self.version) |ver| {
            try writer.print(" since version {s}", .{ver});
        }

        if (self.replacement) |repl| {
            try writer.print(". Use {s} instead", .{repl});
        }

        return result.toOwnedSlice();
    }
};

/// Deprecation registry for tracking deprecated features
pub const DeprecationRegistry = struct {
    entries: std.ArrayList(DeprecationInfo),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DeprecationRegistry {
        return .{
            .entries = std.ArrayList(DeprecationInfo).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DeprecationRegistry) void {
        self.entries.deinit();
    }

    pub fn register(self: *DeprecationRegistry, info: DeprecationInfo) !void {
        try self.entries.append(info);
    }

    pub fn count(self: DeprecationRegistry) usize {
        return self.entries.items.len;
    }

    pub fn countByCategory(self: DeprecationRegistry, category: DeprecationInfo.DeprecationCategory) usize {
        var count: usize = 0;
        for (self.entries.items) |entry| {
            if (entry.category == category) {
                count += 1;
            }
        }
        return count;
    }

    pub fn findByFeature(self: DeprecationRegistry, feature: []const u8) ?DeprecationInfo {
        for (self.entries.items) |entry| {
            if (std.mem.eql(u8, entry.feature, feature)) {
                return entry;
            }
        }
        return null;
    }
};

/// Deprecation test harness
pub const DeprecationHarness = struct {
    state: warnings.WarningsState,
    registry: DeprecationRegistry,
    warnings_issued: std.ArrayList(DeprecationInfo),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DeprecationHarness {
        return .{
            .state = warnings.WarningsState.init(allocator),
            .registry = DeprecationRegistry.init(allocator),
            .warnings_issued = std.ArrayList(DeprecationInfo).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DeprecationHarness) void {
        self.warnings_issued.deinit();
        self.registry.deinit();
        self.state.deinit();
    }

    pub fn registerDeprecation(self: *DeprecationHarness, info: DeprecationInfo) !void {
        try self.registry.register(info);
    }

    pub fn addFilter(self: *DeprecationHarness, filter: warnings.WarningFilter) !void {
        try self.state.appendFilter(filter);
    }

    pub fn issueDeprecationWarning(self: *DeprecationHarness, feature: []const u8) !IssueResult {
        const info = self.registry.findByFeature(feature) orelse return .not_found;

        const category = info.toWarningCategory();
        const message = try info.formatMessage(self.allocator);
        defer self.allocator.free(message);

        const action = self.state.getAction(message, category, "<module>", 0);

        switch (action) {
            .ignore => return .ignored,
            .@"error" => return .raised_error,
            else => {
                try self.warnings_issued.append(info);
                return .issued;
            },
        }
    }

    pub fn getIssuedCount(self: DeprecationHarness) usize {
        return self.warnings_issued.items.len;
    }

    pub fn reset(self: *DeprecationHarness) void {
        self.warnings_issued.clearRetainingCapacity();
        self.state.resetFilters();
    }

    pub const IssueResult = enum {
        issued,
        ignored,
        raised_error,
        not_found,
    };
};

/// Version comparator for deprecation versions
pub const VersionComparator = struct {
    pub fn compare(v1: []const u8, v2: []const u8) Ordering {
        const parts1 = parseVersion(v1);
        const parts2 = parseVersion(v2);

        if (parts1.major != parts2.major) {
            return if (parts1.major < parts2.major) .less else .greater;
        }
        if (parts1.minor != parts2.minor) {
            return if (parts1.minor < parts2.minor) .less else .greater;
        }
        if (parts1.patch != parts2.patch) {
            return if (parts1.patch < parts2.patch) .less else .greater;
        }
        return .equal;
    }

    const VersionParts = struct {
        major: u32 = 0,
        minor: u32 = 0,
        patch: u32 = 0,
    };

    fn parseVersion(version: []const u8) VersionParts {
        var parts = VersionParts{};
        var iter = std.mem.splitScalar(u8, version, '.');
        var i: usize = 0;

        while (iter.next()) |part| {
            const num = std.fmt.parseInt(u32, part, 10) catch 0;
            switch (i) {
                0 => parts.major = num,
                1 => parts.minor = num,
                2 => parts.patch = num,
                else => {},
            }
            i += 1;
        }

        return parts;
    }

    pub const Ordering = enum {
        less,
        equal,
        greater,
    };
};

// ============================================================================
// DeprecationInfo Tests
// ============================================================================

test "deprecation_info_basic" {
    const info = DeprecationInfo{
        .feature = "old_function",
    };

    try std.testing.expectEqualStrings("old_function", info.feature);
    try std.testing.expectEqual(DeprecationInfo.DeprecationCategory.current, info.category);
}

test "deprecation_info_with_version" {
    const info = DeprecationInfo{
        .feature = "legacy_api",
        .version = "3.10",
    };

    try std.testing.expectEqualStrings("3.10", info.version.?);
}

test "deprecation_info_with_replacement" {
    const info = DeprecationInfo{
        .feature = "old_method",
        .replacement = "new_method",
    };

    try std.testing.expectEqualStrings("new_method", info.replacement.?);
}

test "deprecation_info_to_category" {
    const current = DeprecationInfo{ .feature = "a", .category = .current };
    try std.testing.expectEqual(warnings.WarningCategory.DeprecationWarning, current.toWarningCategory());

    const pending = DeprecationInfo{ .feature = "b", .category = .pending };
    try std.testing.expectEqual(warnings.WarningCategory.PendingDeprecationWarning, pending.toWarningCategory());

    const future = DeprecationInfo{ .feature = "c", .category = .future };
    try std.testing.expectEqual(warnings.WarningCategory.FutureWarning, future.toWarningCategory());
}

test "deprecation_info_format_message" {
    const info = DeprecationInfo{
        .feature = "old_func",
        .version = "3.9",
        .replacement = "new_func",
    };

    const msg = try info.formatMessage(std.testing.allocator);
    defer std.testing.allocator.free(msg);

    try std.testing.expect(std.mem.indexOf(u8, msg, "old_func") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "deprecated") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "3.9") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "new_func") != null);
}

test "deprecation_info_format_minimal" {
    const info = DeprecationInfo{
        .feature = "simple_feature",
    };

    const msg = try info.formatMessage(std.testing.allocator);
    defer std.testing.allocator.free(msg);

    try std.testing.expectEqualStrings("simple_feature is deprecated", msg);
}

// ============================================================================
// DeprecationRegistry Tests
// ============================================================================

test "registry_init" {
    var registry = DeprecationRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try std.testing.expectEqual(@as(usize, 0), registry.count());
}

test "registry_register" {
    var registry = DeprecationRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.register(.{ .feature = "func1" });
    try registry.register(.{ .feature = "func2" });

    try std.testing.expectEqual(@as(usize, 2), registry.count());
}

test "registry_count_by_category" {
    var registry = DeprecationRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.register(.{ .feature = "a", .category = .current });
    try registry.register(.{ .feature = "b", .category = .current });
    try registry.register(.{ .feature = "c", .category = .pending });
    try registry.register(.{ .feature = "d", .category = .future });

    try std.testing.expectEqual(@as(usize, 2), registry.countByCategory(.current));
    try std.testing.expectEqual(@as(usize, 1), registry.countByCategory(.pending));
    try std.testing.expectEqual(@as(usize, 1), registry.countByCategory(.future));
}

test "registry_find_by_feature" {
    var registry = DeprecationRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.register(.{ .feature = "old_api", .version = "3.8" });

    const found = registry.findByFeature("old_api");
    try std.testing.expect(found != null);
    try std.testing.expectEqualStrings("3.8", found.?.version.?);

    const not_found = registry.findByFeature("unknown");
    try std.testing.expect(not_found == null);
}

// ============================================================================
// DeprecationHarness Tests
// ============================================================================

test "harness_init" {
    var harness = DeprecationHarness.init(std.testing.allocator);
    defer harness.deinit();

    try std.testing.expectEqual(@as(usize, 0), harness.getIssuedCount());
}

test "harness_register_and_issue" {
    var harness = DeprecationHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.registerDeprecation(.{ .feature = "old_feature" });
    try harness.addFilter(.{ .action = .always, .category = .Warning });

    const result = try harness.issueDeprecationWarning("old_feature");
    try std.testing.expectEqual(DeprecationHarness.IssueResult.issued, result);
    try std.testing.expectEqual(@as(usize, 1), harness.getIssuedCount());
}

test "harness_issue_not_found" {
    var harness = DeprecationHarness.init(std.testing.allocator);
    defer harness.deinit();

    const result = try harness.issueDeprecationWarning("unknown_feature");
    try std.testing.expectEqual(DeprecationHarness.IssueResult.not_found, result);
}

test "harness_issue_ignored" {
    var harness = DeprecationHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.registerDeprecation(.{ .feature = "ignored_feature" });
    try harness.addFilter(.{ .action = .ignore, .category = .DeprecationWarning });

    const result = try harness.issueDeprecationWarning("ignored_feature");
    try std.testing.expectEqual(DeprecationHarness.IssueResult.ignored, result);
}

test "harness_issue_error" {
    var harness = DeprecationHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.registerDeprecation(.{ .feature = "error_feature" });
    try harness.addFilter(.{ .action = .@"error", .category = .DeprecationWarning });

    const result = try harness.issueDeprecationWarning("error_feature");
    try std.testing.expectEqual(DeprecationHarness.IssueResult.raised_error, result);
}

test "harness_reset" {
    var harness = DeprecationHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.registerDeprecation(.{ .feature = "test" });
    try harness.addFilter(.{ .action = .always, .category = .Warning });
    _ = try harness.issueDeprecationWarning("test");

    try std.testing.expectEqual(@as(usize, 1), harness.getIssuedCount());

    harness.reset();
    try std.testing.expectEqual(@as(usize, 0), harness.getIssuedCount());
}

// ============================================================================
// VersionComparator Tests
// ============================================================================

test "version_compare_equal" {
    try std.testing.expectEqual(VersionComparator.Ordering.equal, VersionComparator.compare("3.10.0", "3.10.0"));
    try std.testing.expectEqual(VersionComparator.Ordering.equal, VersionComparator.compare("3.10", "3.10.0"));
}

test "version_compare_less" {
    try std.testing.expectEqual(VersionComparator.Ordering.less, VersionComparator.compare("3.9", "3.10"));
    try std.testing.expectEqual(VersionComparator.Ordering.less, VersionComparator.compare("3.10.0", "3.10.1"));
    try std.testing.expectEqual(VersionComparator.Ordering.less, VersionComparator.compare("2.7", "3.0"));
}

test "version_compare_greater" {
    try std.testing.expectEqual(VersionComparator.Ordering.greater, VersionComparator.compare("3.11", "3.10"));
    try std.testing.expectEqual(VersionComparator.Ordering.greater, VersionComparator.compare("3.10.5", "3.10.4"));
}

// ============================================================================
// All Deprecation Categories Tests
// ============================================================================

test "deprecation_all_categories" {
    var harness = DeprecationHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.addFilter(.{ .action = .always, .category = .Warning });

    // Register deprecations of each type
    try harness.registerDeprecation(.{
        .feature = "current_deprecated",
        .category = .current,
    });
    try harness.registerDeprecation(.{
        .feature = "pending_deprecated",
        .category = .pending,
    });
    try harness.registerDeprecation(.{
        .feature = "future_deprecated",
        .category = .future,
    });

    // Issue each
    _ = try harness.issueDeprecationWarning("current_deprecated");
    _ = try harness.issueDeprecationWarning("pending_deprecated");
    _ = try harness.issueDeprecationWarning("future_deprecated");

    try std.testing.expectEqual(@as(usize, 3), harness.getIssuedCount());
}

// ============================================================================
// Integration Tests
// ============================================================================

test "integration_deprecation_workflow" {
    var harness = DeprecationHarness.init(std.testing.allocator);
    defer harness.deinit();

    // Register some deprecations
    try harness.registerDeprecation(.{
        .feature = "old_function",
        .version = "3.8",
        .replacement = "new_function",
        .category = .current,
    });
    try harness.registerDeprecation(.{
        .feature = "soon_deprecated",
        .version = "3.12",
        .category = .pending,
    });
    try harness.registerDeprecation(.{
        .feature = "behavior_change",
        .version = "4.0",
        .category = .future,
    });

    // Set up filters - ignore pending deprecations
    try harness.addFilter(.{ .action = .ignore, .category = .PendingDeprecationWarning });
    try harness.addFilter(.{ .action = .always, .category = .Warning });

    // Issue warnings
    const current_result = try harness.issueDeprecationWarning("old_function");
    try std.testing.expectEqual(DeprecationHarness.IssueResult.issued, current_result);

    const pending_result = try harness.issueDeprecationWarning("soon_deprecated");
    try std.testing.expectEqual(DeprecationHarness.IssueResult.ignored, pending_result);

    const future_result = try harness.issueDeprecationWarning("behavior_change");
    try std.testing.expectEqual(DeprecationHarness.IssueResult.issued, future_result);

    // Only 2 warnings should be issued (pending was ignored)
    try std.testing.expectEqual(@as(usize, 2), harness.getIssuedCount());
}

test "integration_strict_deprecation_mode" {
    var harness = DeprecationHarness.init(std.testing.allocator);
    defer harness.deinit();

    // Register deprecations
    try harness.registerDeprecation(.{ .feature = "strict_feature" });

    // Strict mode - all deprecations are errors
    try harness.addFilter(.{ .action = .@"error", .category = .DeprecationWarning });

    const result = try harness.issueDeprecationWarning("strict_feature");
    try std.testing.expectEqual(DeprecationHarness.IssueResult.raised_error, result);
}

test "integration_version_based_filtering" {
    var registry = DeprecationRegistry.init(std.testing.allocator);
    defer registry.deinit();

    // Register deprecations with versions
    try registry.register(.{ .feature = "old_v38", .version = "3.8" });
    try registry.register(.{ .feature = "old_v310", .version = "3.10" });
    try registry.register(.{ .feature = "old_v312", .version = "3.12" });

    // Count by checking if version is less than current (simulated 3.11)
    var old_count: usize = 0;
    for (registry.entries.items) |entry| {
        if (entry.version) |ver| {
            if (VersionComparator.compare(ver, "3.11") == .less) {
                old_count += 1;
            }
        }
    }

    try std.testing.expectEqual(@as(usize, 2), old_count); // 3.8 and 3.10 are < 3.11
}
