//! test.test_warnings - Warning system tests
//!
//! Comprehensive test suite for Python warnings module implementation.
//! Includes tests for filters, categories, context managers, and warning functions.

const std = @import("std");

// ============================================================================
// Submodule Imports
// ============================================================================

pub const test_filters = @import("test_filters.zig");
pub const test_categories = @import("test_categories.zig");
pub const test_catch_warnings = @import("test_catch_warnings.zig");
pub const test_showwarning = @import("test_showwarning.zig");
pub const test_formatwarning = @import("test_formatwarning.zig");
pub const test_simplefilter = @import("test_simplefilter.zig");
pub const test_filterwarnings = @import("test_filterwarnings.zig");
pub const test_warn = @import("test_warn.zig");
pub const test_warn_explicit = @import("test_warn_explicit.zig");
pub const test_deprecated = @import("test_deprecated.zig");

// ============================================================================
// Core Warning Types
// ============================================================================

pub const Warning = struct {
    message: []const u8,
    category: Category,
    filename: []const u8 = "",
    lineno: usize = 0,

    pub const Category = enum {
        Warning,
        UserWarning,
        DeprecationWarning,
        PendingDeprecationWarning,
        SyntaxWarning,
        RuntimeWarning,
        FutureWarning,
        ImportWarning,
        UnicodeWarning,
        BytesWarning,
        EncodingWarning,
        ResourceWarning,

        pub fn name(self: Category) []const u8 {
            return @tagName(self);
        }
    };

    pub fn init(message: []const u8, category: Category) Warning {
        return .{
            .message = message,
            .category = category,
        };
    }

    pub fn withLocation(self: Warning, filename: []const u8, lineno: usize) Warning {
        return .{
            .message = self.message,
            .category = self.category,
            .filename = filename,
            .lineno = lineno,
        };
    }
};

pub const WarningFilter = struct {
    action: Action,
    message: ?[]const u8 = null,
    category: ?Warning.Category = null,
    module: ?[]const u8 = null,
    lineno: usize = 0,

    pub const Action = enum {
        default,
        error_,
        ignore,
        always,
        module_,
        once,

        pub fn toString(self: Action) []const u8 {
            return switch (self) {
                .default => "default",
                .error_ => "error",
                .ignore => "ignore",
                .always => "always",
                .module_ => "module",
                .once => "once",
            };
        }

        pub fn fromString(str: []const u8) ?Action {
            if (std.mem.eql(u8, str, "default")) return .default;
            if (std.mem.eql(u8, str, "error")) return .error_;
            if (std.mem.eql(u8, str, "ignore")) return .ignore;
            if (std.mem.eql(u8, str, "always")) return .always;
            if (std.mem.eql(u8, str, "module")) return .module_;
            if (std.mem.eql(u8, str, "once")) return .once;
            return null;
        }
    };

    pub fn matches(
        self: WarningFilter,
        message: []const u8,
        category: Warning.Category,
        module_name: []const u8,
        lineno: usize,
    ) bool {
        // Check message pattern
        if (self.message) |msg_pattern| {
            if (std.mem.indexOf(u8, message, msg_pattern) == null) {
                return false;
            }
        }

        // Check category
        if (self.category) |cat| {
            if (cat != .Warning and cat != category) {
                return false;
            }
        }

        // Check module
        if (self.module) |mod_pattern| {
            if (std.mem.indexOf(u8, module_name, mod_pattern) == null) {
                return false;
            }
        }

        // Check lineno
        if (self.lineno != 0 and self.lineno != lineno) {
            return false;
        }

        return true;
    }
};

// ============================================================================
// Warnings Module
// ============================================================================

pub const WarningsModule = struct {
    filters: std.ArrayList(WarningFilter),
    once_registry: std.StringHashMap(bool),
    default_action: WarningFilter.Action = .default,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .filters = std.ArrayList(WarningFilter).init(allocator),
            .once_registry = std.StringHashMap(bool).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.filters.deinit();
        self.once_registry.deinit();
    }

    pub fn warn(self: *@This(), message: []const u8, category: Warning.Category) !void {
        const action = self.getAction(message, category);
        switch (action) {
            .error_ => return error.WarningAsError,
            .ignore => {},
            .always => std.debug.print("Warning: {s}\n", .{message}),
            .once => {
                if (!self.once_registry.contains(message)) {
                    try self.once_registry.put(message, true);
                    std.debug.print("Warning: {s}\n", .{message});
                }
            },
            else => std.debug.print("Warning: {s}\n", .{message}),
        }
    }

    pub fn filterwarnings(
        self: *@This(),
        action: WarningFilter.Action,
        message: ?[]const u8,
        category: ?Warning.Category,
    ) !void {
        try self.filters.append(.{ .action = action, .message = message, .category = category });
    }

    pub fn simplefilter(self: *@This(), action: WarningFilter.Action) !void {
        try self.filters.append(.{ .action = action });
    }

    pub fn resetwarnings(self: *@This()) void {
        self.filters.clearRetainingCapacity();
        self.once_registry.clearRetainingCapacity();
    }

    fn getAction(self: @This(), message: []const u8, category: Warning.Category) WarningFilter.Action {
        for (self.filters.items) |filter| {
            if (filter.message) |m| {
                if (!std.mem.eql(u8, m, message)) continue;
            }
            if (filter.category) |c| {
                if (c != category) continue;
            }
            return filter.action;
        }
        return self.default_action;
    }
};

// ============================================================================
// Utility Functions
// ============================================================================

pub fn warn(message: []const u8, category: Warning.Category) void {
    std.debug.print("{s}: {s}\n", .{ @tagName(category), message });
}

pub fn formatWarning(
    allocator: std.mem.Allocator,
    message: []const u8,
    category: Warning.Category,
    filename: []const u8,
    lineno: usize,
) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "{s}:{d}: {s}: {s}\n",
        .{ filename, lineno, category.name(), message },
    );
}

// ============================================================================
// Main Module Tests
// ============================================================================

test "warning_init" {
    const w = Warning{ .message = "test", .category = .UserWarning };
    try std.testing.expectEqualStrings("test", w.message);
}

test "warning_with_location" {
    const w = Warning.init("test", .UserWarning).withLocation("test.py", 42);
    try std.testing.expectEqualStrings("test.py", w.filename);
    try std.testing.expectEqual(@as(usize, 42), w.lineno);
}

test "warnings_module" {
    var wm = WarningsModule.init(std.testing.allocator);
    defer wm.deinit();
    try wm.simplefilter(.ignore);
    try std.testing.expectEqual(@as(usize, 1), wm.filters.items.len);
}

test "warnings_reset" {
    var wm = WarningsModule.init(std.testing.allocator);
    defer wm.deinit();
    try wm.simplefilter(.always);
    wm.resetwarnings();
    try std.testing.expectEqual(@as(usize, 0), wm.filters.items.len);
}

test "warning_categories" {
    try std.testing.expectEqual(Warning.Category.DeprecationWarning, Warning.Category.DeprecationWarning);
    try std.testing.expect(Warning.Category.UserWarning != Warning.Category.RuntimeWarning);
}

test "warning_category_names" {
    try std.testing.expectEqualStrings("UserWarning", Warning.Category.UserWarning.name());
    try std.testing.expectEqualStrings("DeprecationWarning", Warning.Category.DeprecationWarning.name());
    try std.testing.expectEqualStrings("RuntimeWarning", Warning.Category.RuntimeWarning.name());
}

test "warning_filter_action_strings" {
    try std.testing.expectEqualStrings("default", WarningFilter.Action.default.toString());
    try std.testing.expectEqualStrings("error", WarningFilter.Action.error_.toString());
    try std.testing.expectEqual(WarningFilter.Action.ignore, WarningFilter.Action.fromString("ignore").?);
}

test "warning_filter_matches" {
    const filter = WarningFilter{
        .action = .ignore,
        .message = "deprecated",
        .category = .DeprecationWarning,
    };

    try std.testing.expect(filter.matches("deprecated feature", .DeprecationWarning, "mod", 1));
    try std.testing.expect(!filter.matches("other message", .DeprecationWarning, "mod", 1));
}

test "format_warning" {
    const allocator = std.testing.allocator;
    const result = try formatWarning(allocator, "test message", .UserWarning, "test.py", 42);
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "test.py") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "42") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "UserWarning") != null);
}

// ============================================================================
// Reference All Submodule Tests
// ============================================================================

comptime {
    // Pull in all tests from submodules
    _ = test_filters;
    _ = test_categories;
    _ = test_catch_warnings;
    _ = test_showwarning;
    _ = test_formatwarning;
    _ = test_simplefilter;
    _ = test_filterwarnings;
    _ = test_warn;
    _ = test_warn_explicit;
    _ = test_deprecated;
}
