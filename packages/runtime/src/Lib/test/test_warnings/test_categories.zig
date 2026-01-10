//! test.test_warnings.test_categories - Comprehensive tests for warning categories
//!
//! Tests the warning category hierarchy, inheritance relationships, and category
//! properties. Mirrors CPython's warning category tests.

const std = @import("std");
const warnings = @import("Lib.warnings");

// ============================================================================
// Category Types
// ============================================================================

/// Category info for testing
pub const CategoryInfo = struct {
    category: warnings.WarningCategory,
    name: []const u8,
    is_builtin: bool = true,

    pub fn getName(self: CategoryInfo) []const u8 {
        return self.category.name();
    }

    pub fn isSubclassOf(self: CategoryInfo, other: warnings.WarningCategory) bool {
        return self.category.isSubclassOf(other);
    }
};

/// All builtin warning categories
pub const BUILTIN_CATEGORIES = [_]CategoryInfo{
    .{ .category = .Warning, .name = "Warning" },
    .{ .category = .UserWarning, .name = "UserWarning" },
    .{ .category = .DeprecationWarning, .name = "DeprecationWarning" },
    .{ .category = .PendingDeprecationWarning, .name = "PendingDeprecationWarning" },
    .{ .category = .SyntaxWarning, .name = "SyntaxWarning" },
    .{ .category = .RuntimeWarning, .name = "RuntimeWarning" },
    .{ .category = .FutureWarning, .name = "FutureWarning" },
    .{ .category = .ImportWarning, .name = "ImportWarning" },
    .{ .category = .UnicodeWarning, .name = "UnicodeWarning" },
    .{ .category = .BytesWarning, .name = "BytesWarning" },
    .{ .category = .EncodingWarning, .name = "EncodingWarning" },
    .{ .category = .ResourceWarning, .name = "ResourceWarning" },
};

/// Category test harness
pub const CategoryTestHarness = struct {
    categories: std.ArrayList(warnings.WarningCategory),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CategoryTestHarness {
        return .{
            .categories = std.ArrayList(warnings.WarningCategory).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CategoryTestHarness) void {
        self.categories.deinit();
    }

    pub fn addCategory(self: *CategoryTestHarness, cat: warnings.WarningCategory) !void {
        try self.categories.append(cat);
    }

    pub fn containsCategory(self: CategoryTestHarness, cat: warnings.WarningCategory) bool {
        for (self.categories.items) |c| {
            if (c == cat) return true;
        }
        return false;
    }

    pub fn getSubclassesOf(self: *CategoryTestHarness, base: warnings.WarningCategory) ![]warnings.WarningCategory {
        var result = std.ArrayList(warnings.WarningCategory).init(self.allocator);
        defer result.deinit();

        for (BUILTIN_CATEGORIES) |info| {
            if (info.category.isSubclassOf(base)) {
                try result.append(info.category);
            }
        }

        return result.toOwnedSlice();
    }

    pub fn count(self: CategoryTestHarness) usize {
        return self.categories.items.len;
    }
};

/// Category hierarchy validator
pub const HierarchyValidator = struct {
    validated: std.AutoHashMap(warnings.WarningCategory, bool),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) HierarchyValidator {
        return .{
            .validated = std.AutoHashMap(warnings.WarningCategory, bool).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *HierarchyValidator) void {
        self.validated.deinit();
    }

    pub fn validate(self: *HierarchyValidator, cat: warnings.WarningCategory) !bool {
        // All categories should be subclass of Warning
        if (!cat.isSubclassOf(.Warning)) {
            return false;
        }

        // Every category is subclass of itself
        if (!cat.isSubclassOf(cat)) {
            return false;
        }

        try self.validated.put(cat, true);
        return true;
    }

    pub fn validateAll(self: *HierarchyValidator) !bool {
        for (BUILTIN_CATEGORIES) |info| {
            if (!try self.validate(info.category)) {
                return false;
            }
        }
        return true;
    }
};

// ============================================================================
// Category Name Tests
// ============================================================================

test "category_names" {
    try std.testing.expectEqualStrings("Warning", warnings.WarningCategory.Warning.name());
    try std.testing.expectEqualStrings("UserWarning", warnings.WarningCategory.UserWarning.name());
    try std.testing.expectEqualStrings("DeprecationWarning", warnings.WarningCategory.DeprecationWarning.name());
    try std.testing.expectEqualStrings("PendingDeprecationWarning", warnings.WarningCategory.PendingDeprecationWarning.name());
    try std.testing.expectEqualStrings("SyntaxWarning", warnings.WarningCategory.SyntaxWarning.name());
    try std.testing.expectEqualStrings("RuntimeWarning", warnings.WarningCategory.RuntimeWarning.name());
    try std.testing.expectEqualStrings("FutureWarning", warnings.WarningCategory.FutureWarning.name());
    try std.testing.expectEqualStrings("ImportWarning", warnings.WarningCategory.ImportWarning.name());
    try std.testing.expectEqualStrings("UnicodeWarning", warnings.WarningCategory.UnicodeWarning.name());
    try std.testing.expectEqualStrings("BytesWarning", warnings.WarningCategory.BytesWarning.name());
    try std.testing.expectEqualStrings("EncodingWarning", warnings.WarningCategory.EncodingWarning.name());
    try std.testing.expectEqualStrings("ResourceWarning", warnings.WarningCategory.ResourceWarning.name());
}

test "category_name_consistency" {
    for (BUILTIN_CATEGORIES) |info| {
        try std.testing.expectEqualStrings(info.name, info.category.name());
    }
}

test "category_name_not_empty" {
    for (BUILTIN_CATEGORIES) |info| {
        try std.testing.expect(info.category.name().len > 0);
    }
}

// ============================================================================
// Category Hierarchy Tests
// ============================================================================

test "category_all_subclass_of_warning" {
    for (BUILTIN_CATEGORIES) |info| {
        try std.testing.expect(info.category.isSubclassOf(.Warning));
    }
}

test "category_self_subclass" {
    for (BUILTIN_CATEGORIES) |info| {
        try std.testing.expect(info.category.isSubclassOf(info.category));
    }
}

test "category_warning_base" {
    // Warning is the base class
    try std.testing.expect(warnings.WarningCategory.Warning.isSubclassOf(.Warning));

    // Other categories are not base for Warning
    try std.testing.expect(!warnings.WarningCategory.Warning.isSubclassOf(.UserWarning));
    try std.testing.expect(!warnings.WarningCategory.Warning.isSubclassOf(.DeprecationWarning));
}

test "category_no_cross_inheritance" {
    // UserWarning is not subclass of DeprecationWarning
    try std.testing.expect(!warnings.WarningCategory.UserWarning.isSubclassOf(.DeprecationWarning));

    // DeprecationWarning is not subclass of UserWarning
    try std.testing.expect(!warnings.WarningCategory.DeprecationWarning.isSubclassOf(.UserWarning));

    // RuntimeWarning is not subclass of SyntaxWarning
    try std.testing.expect(!warnings.WarningCategory.RuntimeWarning.isSubclassOf(.SyntaxWarning));
}

test "category_deprecation_variants" {
    // PendingDeprecationWarning is separate from DeprecationWarning
    try std.testing.expect(!warnings.WarningCategory.PendingDeprecationWarning.isSubclassOf(.DeprecationWarning));
    try std.testing.expect(!warnings.WarningCategory.DeprecationWarning.isSubclassOf(.PendingDeprecationWarning));

    // Both are subclass of Warning
    try std.testing.expect(warnings.WarningCategory.DeprecationWarning.isSubclassOf(.Warning));
    try std.testing.expect(warnings.WarningCategory.PendingDeprecationWarning.isSubclassOf(.Warning));
}

test "category_future_warning" {
    // FutureWarning is for features that will change
    try std.testing.expect(warnings.WarningCategory.FutureWarning.isSubclassOf(.Warning));
    try std.testing.expect(!warnings.WarningCategory.FutureWarning.isSubclassOf(.DeprecationWarning));
}

// ============================================================================
// Category Comparison Tests
// ============================================================================

test "category_equality" {
    try std.testing.expectEqual(warnings.WarningCategory.UserWarning, warnings.WarningCategory.UserWarning);
    try std.testing.expect(warnings.WarningCategory.UserWarning != warnings.WarningCategory.RuntimeWarning);
}

test "category_all_distinct" {
    for (BUILTIN_CATEGORIES, 0..) |info1, i| {
        for (BUILTIN_CATEGORIES, 0..) |info2, j| {
            if (i != j) {
                try std.testing.expect(info1.category != info2.category);
            }
        }
    }
}

test "category_count" {
    try std.testing.expectEqual(@as(usize, 12), BUILTIN_CATEGORIES.len);
}

// ============================================================================
// Category Usage Tests
// ============================================================================

test "category_in_filter" {
    const filter = warnings.WarningFilter{
        .action = .ignore,
        .category = .DeprecationWarning,
    };

    // Filter should match DeprecationWarning
    try std.testing.expect(filter.matches("test", .DeprecationWarning, "mod", 1));

    // Should not match other categories
    try std.testing.expect(!filter.matches("test", .UserWarning, "mod", 1));
}

test "category_warning_filter_matches_all" {
    const filter = warnings.WarningFilter{
        .action = .ignore,
        .category = .Warning,
    };

    // Warning category should match all warning types
    for (BUILTIN_CATEGORIES) |info| {
        try std.testing.expect(filter.matches("test", info.category, "mod", 1));
    }
}

// ============================================================================
// Category Harness Tests
// ============================================================================

test "harness_add_category" {
    var harness = CategoryTestHarness.init(std.testing.allocator);
    defer harness.deinit();

    try harness.addCategory(.UserWarning);
    try harness.addCategory(.DeprecationWarning);

    try std.testing.expectEqual(@as(usize, 2), harness.count());
    try std.testing.expect(harness.containsCategory(.UserWarning));
    try std.testing.expect(harness.containsCategory(.DeprecationWarning));
    try std.testing.expect(!harness.containsCategory(.RuntimeWarning));
}

test "harness_get_subclasses" {
    var harness = CategoryTestHarness.init(std.testing.allocator);
    defer harness.deinit();

    // Get all subclasses of Warning (should be all categories)
    const subclasses = try harness.getSubclassesOf(.Warning);
    defer std.testing.allocator.free(subclasses);

    try std.testing.expectEqual(@as(usize, 12), subclasses.len);
}

// ============================================================================
// Hierarchy Validator Tests
// ============================================================================

test "validator_single_category" {
    var validator = HierarchyValidator.init(std.testing.allocator);
    defer validator.deinit();

    try std.testing.expect(try validator.validate(.UserWarning));
    try std.testing.expect(try validator.validate(.DeprecationWarning));
}

test "validator_all_categories" {
    var validator = HierarchyValidator.init(std.testing.allocator);
    defer validator.deinit();

    try std.testing.expect(try validator.validateAll());
}

// ============================================================================
// Category Info Tests
// ============================================================================

test "category_info_get_name" {
    const info = CategoryInfo{
        .category = .UserWarning,
        .name = "UserWarning",
    };

    try std.testing.expectEqualStrings("UserWarning", info.getName());
}

test "category_info_is_subclass" {
    const info = CategoryInfo{
        .category = .DeprecationWarning,
        .name = "DeprecationWarning",
    };

    try std.testing.expect(info.isSubclassOf(.Warning));
    try std.testing.expect(info.isSubclassOf(.DeprecationWarning));
    try std.testing.expect(!info.isSubclassOf(.UserWarning));
}

test "category_info_builtin_flag" {
    for (BUILTIN_CATEGORIES) |info| {
        try std.testing.expect(info.is_builtin);
    }
}

// ============================================================================
// Edge Cases
// ============================================================================

test "category_resource_warning" {
    // ResourceWarning is for unclosed resources
    try std.testing.expect(warnings.WarningCategory.ResourceWarning.isSubclassOf(.Warning));
    try std.testing.expectEqualStrings("ResourceWarning", warnings.WarningCategory.ResourceWarning.name());
}

test "category_encoding_warning" {
    // EncodingWarning is for encoding-related issues
    try std.testing.expect(warnings.WarningCategory.EncodingWarning.isSubclassOf(.Warning));
    try std.testing.expectEqualStrings("EncodingWarning", warnings.WarningCategory.EncodingWarning.name());
}

test "category_bytes_warning" {
    // BytesWarning is for bytes-related issues
    try std.testing.expect(warnings.WarningCategory.BytesWarning.isSubclassOf(.Warning));
    try std.testing.expectEqualStrings("BytesWarning", warnings.WarningCategory.BytesWarning.name());
}

test "category_unicode_warning" {
    // UnicodeWarning is for unicode-related issues
    try std.testing.expect(warnings.WarningCategory.UnicodeWarning.isSubclassOf(.Warning));
    try std.testing.expectEqualStrings("UnicodeWarning", warnings.WarningCategory.UnicodeWarning.name());
}

test "category_import_warning" {
    // ImportWarning is for import-related issues
    try std.testing.expect(warnings.WarningCategory.ImportWarning.isSubclassOf(.Warning));
    try std.testing.expectEqualStrings("ImportWarning", warnings.WarningCategory.ImportWarning.name());
}

test "category_syntax_warning" {
    // SyntaxWarning is for dubious syntax
    try std.testing.expect(warnings.WarningCategory.SyntaxWarning.isSubclassOf(.Warning));
    try std.testing.expectEqualStrings("SyntaxWarning", warnings.WarningCategory.SyntaxWarning.name());
}
