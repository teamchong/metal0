/// _py_warnings - Python Warnings Implementation
/// Mirrors cpython/Lib/_py_warnings.py (note: CPython has _warnings C module)
///
/// Pure Zig implementation of the warnings machinery.
/// Handles warning categories, filters, and formatting.

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");
const Allocator = std.mem.Allocator;

// ============================================================================
// Warning Categories
// ============================================================================

/// Warning category enumeration
pub const WarningCategory = enum {
    warning,
    user_warning,
    deprecation_warning,
    syntax_warning,
    runtime_warning,
    future_warning,
    pending_deprecation_warning,
    import_warning,
    unicode_warning,
    bytes_warning,
    encoding_warning,
    resource_warning,

    pub fn getName(self: WarningCategory) []const u8 {
        return switch (self) {
            .warning => "Warning",
            .user_warning => "UserWarning",
            .deprecation_warning => "DeprecationWarning",
            .syntax_warning => "SyntaxWarning",
            .runtime_warning => "RuntimeWarning",
            .future_warning => "FutureWarning",
            .pending_deprecation_warning => "PendingDeprecationWarning",
            .import_warning => "ImportWarning",
            .unicode_warning => "UnicodeWarning",
            .bytes_warning => "BytesWarning",
            .encoding_warning => "EncodingWarning",
            .resource_warning => "ResourceWarning",
        };
    }

    pub fn fromString(name: []const u8) ?WarningCategory {
        const map = std.StaticStringMap(WarningCategory).initComptime(.{
            .{ "Warning", .warning },
            .{ "UserWarning", .user_warning },
            .{ "DeprecationWarning", .deprecation_warning },
            .{ "SyntaxWarning", .syntax_warning },
            .{ "RuntimeWarning", .runtime_warning },
            .{ "FutureWarning", .future_warning },
            .{ "PendingDeprecationWarning", .pending_deprecation_warning },
            .{ "ImportWarning", .import_warning },
            .{ "UnicodeWarning", .unicode_warning },
            .{ "BytesWarning", .bytes_warning },
            .{ "EncodingWarning", .encoding_warning },
            .{ "ResourceWarning", .resource_warning },
        });
        return map.get(name);
    }
};

// ============================================================================
// Warning Filter Actions
// ============================================================================

/// Filter action
pub const FilterAction = enum {
    default, // Print first occurrence per location
    @"error", // Raise exception
    ignore, // Never print
    always, // Always print
    module, // Print first occurrence per module
    once, // Print first occurrence globally

    pub fn getName(self: FilterAction) []const u8 {
        return switch (self) {
            .default => "default",
            .@"error" => "error",
            .ignore => "ignore",
            .always => "always",
            .module => "module",
            .once => "once",
        };
    }

    pub fn fromString(name: []const u8) ?FilterAction {
        const map = std.StaticStringMap(FilterAction).initComptime(.{
            .{ "default", .default },
            .{ "error", .@"error" },
            .{ "ignore", .ignore },
            .{ "always", .always },
            .{ "module", .module },
            .{ "once", .once },
        });
        return map.get(name);
    }
};

// ============================================================================
// Warning Filter
// ============================================================================

/// Warning filter entry
pub const WarningFilter = struct {
    action: FilterAction,
    message: ?[]const u8 = null, // Message regex pattern (null = match all)
    category: ?WarningCategory = null, // Category (null = match all)
    module: ?[]const u8 = null, // Module regex pattern (null = match all)
    lineno: ?u32 = null, // Line number (null = match all, 0 = match all)

    pub fn matches(
        self: *const WarningFilter,
        message: []const u8,
        category: WarningCategory,
        module_name: []const u8,
        lineno: u32,
    ) bool {
        // Check category
        if (self.category) |cat| {
            if (cat != category) return false;
        }

        // Check line number
        if (self.lineno) |line| {
            if (line != 0 and line != lineno) return false;
        }

        // Check message pattern (simple substring match for now)
        if (self.message) |pattern| {
            if (std.mem.indexOf(u8, message, pattern) == null) return false;
        }

        // Check module pattern (simple substring match for now)
        if (self.module) |pattern| {
            if (std.mem.indexOf(u8, module_name, pattern) == null) return false;
        }

        return true;
    }
};

// ============================================================================
// Warning Record
// ============================================================================

/// Record of a warning that was issued
pub const WarningRecord = struct {
    message: []const u8,
    category: WarningCategory,
    filename: []const u8,
    lineno: u32,
    module: []const u8,
};

// ============================================================================
// Warnings State
// ============================================================================

/// Warnings state manager
pub const WarningsState = struct {
    const Self = @This();

    /// Warning filters (checked in order)
    filters: std.ArrayList(WarningFilter),
    /// Registry of warnings already shown (for once/default/module)
    registry: hashmap_helper.StringHashMap(void),
    /// Once registry (category + message hash)
    once_registry: std.AutoHashMap(u64, void),
    /// Default action when no filter matches
    default_action: FilterAction = .default,
    /// Allocator
    allocator: Allocator,

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .filters = std.ArrayList(WarningFilter).init(allocator),
            .registry = hashmap_helper.StringHashMap(void).init(allocator),
            .once_registry = std.AutoHashMap(u64, void).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.filters.deinit();
        self.registry.deinit();
        self.once_registry.deinit();
    }

    /// Add a filter
    pub fn addFilter(self: *Self, filter: WarningFilter) !void {
        try self.filters.append(filter);
    }

    /// Insert filter at beginning (higher priority)
    pub fn insertFilter(self: *Self, filter: WarningFilter) !void {
        try self.filters.insert(0, filter);
    }

    /// Reset filters to default
    pub fn resetFilters(self: *Self) void {
        self.filters.clearRetainingCapacity();
    }

    /// Get action for a warning
    pub fn getAction(
        self: *const Self,
        message: []const u8,
        category: WarningCategory,
        module_name: []const u8,
        lineno: u32,
    ) FilterAction {
        for (self.filters.items) |*filter| {
            if (filter.matches(message, category, module_name, lineno)) {
                return filter.action;
            }
        }
        return self.default_action;
    }

    /// Check if warning should be shown (handles once/default/module)
    pub fn shouldShow(
        self: *Self,
        action: FilterAction,
        message: []const u8,
        category: WarningCategory,
        filename: []const u8,
        lineno: u32,
        module_name: []const u8,
    ) bool {
        switch (action) {
            .always => return true,
            .ignore => return false,
            .@"error" => return true, // Will raise
            .once => {
                // Show once globally per category+message
                var hasher = std.hash.Wyhash.init(0);
                hasher.update(message);
                hasher.update(category.getName());
                const hash = hasher.final();
                const result = self.once_registry.getOrPut(hash) catch return false;
                return !result.found_existing;
            },
            .module => {
                // Show once per module
                const result = self.registry.getOrPut(module_name) catch return false;
                return !result.found_existing;
            },
            .default => {
                // Show once per location
                var buf: [256]u8 = undefined;
                const key = std.fmt.bufPrint(&buf, "{s}:{d}", .{ filename, lineno }) catch return true;
                const result = self.registry.getOrPut(key) catch return false;
                return !result.found_existing;
            },
        }
    }
};

// ============================================================================
// Warning Functions
// ============================================================================

/// Format a warning message
pub fn formatWarning(
    allocator: Allocator,
    message: []const u8,
    category: WarningCategory,
    filename: []const u8,
    lineno: u32,
    line: ?[]const u8,
) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    const writer = result.writer();

    // Main warning line
    try writer.print("{s}:{d}: {s}: {s}\n", .{
        filename,
        lineno,
        category.getName(),
        message,
    });

    // Source line if available
    if (line) |src| {
        const trimmed = std.mem.trim(u8, src, " \t\r\n");
        if (trimmed.len > 0) {
            try writer.print("  {s}\n", .{trimmed});
        }
    }

    return result.toOwnedSlice();
}

/// Simple warn function
pub fn warn(
    message: []const u8,
    category: WarningCategory,
) void {
    std.debug.print("{s}: {s}\n", .{ category.getName(), message });
}

/// Warn with full context
pub fn warnExplicit(
    message: []const u8,
    category: WarningCategory,
    filename: []const u8,
    lineno: u32,
    module: ?[]const u8,
    source: ?[]const u8,
) void {
    _ = module;
    _ = source;
    std.debug.print("{s}:{d}: {s}: {s}\n", .{
        filename,
        lineno,
        category.getName(),
        message,
    });
}

// ============================================================================
// Default Filters
// ============================================================================

/// Get default warning filters
pub fn getDefaultFilters(allocator: Allocator) !std.ArrayList(WarningFilter) {
    var filters = std.ArrayList(WarningFilter).init(allocator);

    // Default CPython filters:
    // 1. Ignore DeprecationWarning and PendingDeprecationWarning by default
    try filters.append(.{
        .action = .default,
        .category = .deprecation_warning,
    });

    try filters.append(.{
        .action = .default,
        .category = .pending_deprecation_warning,
    });

    // 2. Ignore ImportWarning
    try filters.append(.{
        .action = .default,
        .category = .import_warning,
    });

    // 3. Ignore ResourceWarning
    try filters.append(.{
        .action = .default,
        .category = .resource_warning,
    });

    return filters;
}

// ============================================================================
// Simplefilter
// ============================================================================

/// Simple filter specification (like warnings.simplefilter)
pub fn simpleFilter(action: FilterAction, category: ?WarningCategory) WarningFilter {
    return .{
        .action = action,
        .category = category,
    };
}

/// Filter specification with all options (like warnings.filterwarnings)
pub fn filterWarnings(
    action: FilterAction,
    message: ?[]const u8,
    category: ?WarningCategory,
    module: ?[]const u8,
    lineno: ?u32,
) WarningFilter {
    return .{
        .action = action,
        .message = message,
        .category = category,
        .module = module,
        .lineno = lineno,
    };
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;
var global_state: ?WarningsState = null;

/// Initialize the _py_warnings module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Get global warnings state
pub fn getState(allocator: Allocator) *WarningsState {
    if (global_state == null) {
        global_state = WarningsState.init(allocator);
    }
    return &global_state.?;
}

/// Reset module state
pub fn reset() void {
    if (global_state) |*state| {
        state.deinit();
    }
    global_state = null;
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "warning category names" {
    try std.testing.expectEqualStrings("DeprecationWarning", WarningCategory.deprecation_warning.getName());
    try std.testing.expectEqualStrings("UserWarning", WarningCategory.user_warning.getName());
}

test "warning category from string" {
    try std.testing.expectEqual(WarningCategory.deprecation_warning, WarningCategory.fromString("DeprecationWarning").?);
    try std.testing.expect(WarningCategory.fromString("NotAWarning") == null);
}

test "filter action names" {
    try std.testing.expectEqualStrings("ignore", FilterAction.ignore.getName());
    try std.testing.expectEqualStrings("error", FilterAction.@"error".getName());
}

test "filter matching" {
    const filter = WarningFilter{
        .action = .ignore,
        .category = .deprecation_warning,
    };

    try std.testing.expect(filter.matches("test", .deprecation_warning, "mymodule", 10));
    try std.testing.expect(!filter.matches("test", .user_warning, "mymodule", 10));
}

test "filter with message pattern" {
    const filter = WarningFilter{
        .action = .ignore,
        .message = "deprecated",
    };

    try std.testing.expect(filter.matches("this is deprecated", .user_warning, "mod", 1));
    try std.testing.expect(!filter.matches("this is fine", .user_warning, "mod", 1));
}

test "warnings state" {
    const allocator = std.testing.allocator;
    var state = WarningsState.init(allocator);
    defer state.deinit();

    try state.addFilter(.{
        .action = .ignore,
        .category = .deprecation_warning,
    });

    const action = state.getAction("test", .deprecation_warning, "mod", 1);
    try std.testing.expectEqual(FilterAction.ignore, action);

    const action2 = state.getAction("test", .user_warning, "mod", 1);
    try std.testing.expectEqual(FilterAction.default, action2);
}

test "format warning" {
    const allocator = std.testing.allocator;
    const formatted = try formatWarning(
        allocator,
        "test message",
        .user_warning,
        "test.py",
        10,
        "    x = 1",
    );
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "test.py:10") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "UserWarning") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "test message") != null);
}

test "simple filter" {
    const filter = simpleFilter(.ignore, .deprecation_warning);
    try std.testing.expectEqual(FilterAction.ignore, filter.action);
    try std.testing.expectEqual(WarningCategory.deprecation_warning, filter.category.?);
}
