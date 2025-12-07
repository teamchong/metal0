//! CPython source: Lib/warnings.py
//!
//! Provides functions to issue warnings and control warning behavior.
//!
//! Mirrors: CPython Lib/warnings.py

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Warning Categories
// ============================================================================

/// Warning category hierarchy
pub const WarningCategory = enum {
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

    pub fn name(self: WarningCategory) []const u8 {
        return switch (self) {
            .Warning => "Warning",
            .UserWarning => "UserWarning",
            .DeprecationWarning => "DeprecationWarning",
            .PendingDeprecationWarning => "PendingDeprecationWarning",
            .SyntaxWarning => "SyntaxWarning",
            .RuntimeWarning => "RuntimeWarning",
            .FutureWarning => "FutureWarning",
            .ImportWarning => "ImportWarning",
            .UnicodeWarning => "UnicodeWarning",
            .BytesWarning => "BytesWarning",
            .EncodingWarning => "EncodingWarning",
            .ResourceWarning => "ResourceWarning",
        };
    }

    /// Check if this category is a subclass of another
    pub fn isSubclassOf(self: WarningCategory, other: WarningCategory) bool {
        if (self == other) return true;
        // All warnings are subclass of Warning
        if (other == .Warning) return true;
        return false;
    }
};

// ============================================================================
// Filter Actions
// ============================================================================

/// Warning filter actions
pub const FilterAction = enum {
    default, // Print first occurrence
    @"error", // Raise as exception
    ignore, // Never print
    always, // Always print
    module, // Print first occurrence per module
    once, // Print first occurrence anywhere

    pub fn fromString(s: []const u8) ?FilterAction {
        if (std.mem.eql(u8, s, "default")) return .default;
        if (std.mem.eql(u8, s, "error")) return .@"error";
        if (std.mem.eql(u8, s, "ignore")) return .ignore;
        if (std.mem.eql(u8, s, "always")) return .always;
        if (std.mem.eql(u8, s, "module")) return .module;
        if (std.mem.eql(u8, s, "once")) return .once;
        return null;
    }

    pub fn toString(self: FilterAction) []const u8 {
        return switch (self) {
            .default => "default",
            .@"error" => "error",
            .ignore => "ignore",
            .always => "always",
            .module => "module",
            .once => "once",
        };
    }
};

// ============================================================================
// Warning Filter
// ============================================================================

/// A single warning filter entry
pub const WarningFilter = struct {
    action: FilterAction,
    message: ?[]const u8 = null, // Pattern to match message
    category: WarningCategory = .Warning,
    module: ?[]const u8 = null, // Pattern to match module name
    lineno: ?usize = null, // Specific line number (0 = all)

    pub fn matches(
        self: WarningFilter,
        message: []const u8,
        category: WarningCategory,
        module_name: []const u8,
        lineno: usize,
    ) bool {
        // Check category (must be same or subclass)
        if (!category.isSubclassOf(self.category)) {
            return false;
        }

        // Check message pattern
        if (self.message) |pattern| {
            if (std.mem.indexOf(u8, message, pattern) == null) {
                return false;
            }
        }

        // Check module pattern
        if (self.module) |mod_pattern| {
            if (std.mem.indexOf(u8, module_name, mod_pattern) == null) {
                return false;
            }
        }

        // Check line number
        if (self.lineno) |ln| {
            if (ln != 0 and ln != lineno) {
                return false;
            }
        }

        return true;
    }
};

// ============================================================================
// Warnings State
// ============================================================================

/// Global warnings state
pub const WarningsState = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    filters: std.ArrayList(WarningFilter),
    once_registry: hashmap_helper.StringHashMap(void),
    default_action: FilterAction = .default,
    show_source: bool = true,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .filters = std.ArrayList(WarningFilter).init(allocator),
            .once_registry = hashmap_helper.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.filters.deinit();
        self.once_registry.deinit();
    }

    /// Add a filter at the beginning of the filter list
    pub fn insertFilter(self: *Self, filter: WarningFilter) !void {
        try self.filters.insert(0, filter);
    }

    /// Add a filter at the end of the filter list
    pub fn appendFilter(self: *Self, filter: WarningFilter) !void {
        try self.filters.append(filter);
    }

    /// Get the action for a warning
    pub fn getAction(
        self: Self,
        message: []const u8,
        category: WarningCategory,
        module_name: []const u8,
        lineno: usize,
    ) FilterAction {
        for (self.filters.items) |filter| {
            if (filter.matches(message, category, module_name, lineno)) {
                return filter.action;
            }
        }
        return self.default_action;
    }

    /// Check if a warning has been seen (for 'once' action)
    pub fn hasSeen(self: *Self, key: []const u8) bool {
        return self.once_registry.contains(key);
    }

    /// Mark a warning as seen
    pub fn markSeen(self: *Self, key: []const u8) !void {
        try self.once_registry.put(key, {});
    }

    /// Reset all filters
    pub fn resetFilters(self: *Self) void {
        self.filters.clearRetainingCapacity();
    }
};

// ============================================================================
// Global State
// ============================================================================

var global_state: ?WarningsState = null;

fn getState(allocator: std.mem.Allocator) *WarningsState {
    if (global_state == null) {
        global_state = WarningsState.init(allocator);
    }
    return &global_state.?;
}

// ============================================================================
// Warning Functions
// ============================================================================

/// Issue a warning
pub fn warn(
    allocator: std.mem.Allocator,
    message: []const u8,
    category: WarningCategory,
    stacklevel: usize,
) !void {
    _ = stacklevel; // Would be used for finding the correct stack frame

    const state = getState(allocator);
    const action = state.getAction(message, category, "<module>", 0);

    switch (action) {
        .ignore => return,
        .@"error" => return error.Warning,
        .always => {
            try printWarning(message, category, "<module>", 0);
        },
        .default, .module => {
            // Check if already shown (simplified)
            const key = message;
            if (!state.hasSeen(key)) {
                try state.markSeen(key);
                try printWarning(message, category, "<module>", 0);
            }
        },
        .once => {
            // Show only once ever
            if (!state.hasSeen(message)) {
                try state.markSeen(message);
                try printWarning(message, category, "<module>", 0);
            }
        },
    }
}

/// Issue a warning with explicit origin
pub fn warnExplicit(
    allocator: std.mem.Allocator,
    message: []const u8,
    category: WarningCategory,
    filename: []const u8,
    lineno: usize,
    module_name: ?[]const u8,
) !void {
    const state = getState(allocator);
    const mod = module_name orelse filename;
    const action = state.getAction(message, category, mod, lineno);

    switch (action) {
        .ignore => return,
        .@"error" => return error.Warning,
        else => {
            try printWarning(message, category, filename, lineno);
        },
    }
}

fn printWarning(
    message: []const u8,
    category: WarningCategory,
    filename: []const u8,
    lineno: usize,
) !void {
    const stderr = std.io.getStdErr().writer();
    if (lineno > 0) {
        try stderr.print("{s}:{d}: {s}: {s}\n", .{ filename, lineno, category.name(), message });
    } else {
        try stderr.print("{s}: {s}\n", .{ category.name(), message });
    }
}

// ============================================================================
// Filter Management Functions
// ============================================================================

/// Add a simple filter
pub fn simpleFilter(
    allocator: std.mem.Allocator,
    action: FilterAction,
    category: WarningCategory,
) !void {
    const state = getState(allocator);
    try state.appendFilter(.{
        .action = action,
        .category = category,
    });
}

/// Add a filter by string specification
pub fn filterWarnings(
    allocator: std.mem.Allocator,
    action: []const u8,
    message: ?[]const u8,
    category: WarningCategory,
    module: ?[]const u8,
    lineno: ?usize,
) !void {
    const filter_action = FilterAction.fromString(action) orelse return error.InvalidAction;
    const state = getState(allocator);
    try state.insertFilter(.{
        .action = filter_action,
        .message = message,
        .category = category,
        .module = module,
        .lineno = lineno,
    });
}

/// Reset all warning filters
pub fn resetWarnings(allocator: std.mem.Allocator) void {
    const state = getState(allocator);
    state.resetFilters();
}

// ============================================================================
// Convenience Functions
// ============================================================================

/// Issue a DeprecationWarning
pub fn deprecationWarning(allocator: std.mem.Allocator, message: []const u8) !void {
    try warn(allocator, message, .DeprecationWarning, 2);
}

/// Issue a PendingDeprecationWarning
pub fn pendingDeprecationWarning(allocator: std.mem.Allocator, message: []const u8) !void {
    try warn(allocator, message, .PendingDeprecationWarning, 2);
}

/// Issue a RuntimeWarning
pub fn runtimeWarning(allocator: std.mem.Allocator, message: []const u8) !void {
    try warn(allocator, message, .RuntimeWarning, 2);
}

/// Issue a SyntaxWarning
pub fn syntaxWarning(allocator: std.mem.Allocator, message: []const u8) !void {
    try warn(allocator, message, .SyntaxWarning, 2);
}

/// Issue a UserWarning
pub fn userWarning(allocator: std.mem.Allocator, message: []const u8) !void {
    try warn(allocator, message, .UserWarning, 2);
}

/// Issue a FutureWarning
pub fn futureWarning(allocator: std.mem.Allocator, message: []const u8) !void {
    try warn(allocator, message, .FutureWarning, 2);
}

/// Issue an ImportWarning
pub fn importWarning(allocator: std.mem.Allocator, message: []const u8) !void {
    try warn(allocator, message, .ImportWarning, 2);
}

/// Issue a ResourceWarning
pub fn resourceWarning(allocator: std.mem.Allocator, message: []const u8) !void {
    try warn(allocator, message, .ResourceWarning, 2);
}

// ============================================================================
// Catch Warnings Context Manager
// ============================================================================

/// Context manager for temporarily modifying warning filters
pub const CatchWarnings = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    record: bool,
    module: ?*WarningsState = null,
    saved_filters: ?std.ArrayList(WarningFilter) = null,
    log: std.ArrayList(WarningRecord),

    pub const WarningRecord = struct {
        message: []const u8,
        category: WarningCategory,
        filename: []const u8,
        lineno: usize,
    };

    pub fn init(allocator: std.mem.Allocator, record: bool) Self {
        return .{
            .allocator = allocator,
            .record = record,
            .log = std.ArrayList(WarningRecord).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.log.deinit();
        if (self.saved_filters) |*sf| {
            sf.deinit();
        }
    }

    pub fn enter(self: *Self) *std.ArrayList(WarningRecord) {
        self.module = getState(self.allocator);
        // Save current filters
        self.saved_filters = std.ArrayList(WarningFilter).init(self.allocator);
        for (self.module.?.filters.items) |f| {
            self.saved_filters.?.append(f) catch {};
        }
        return &self.log;
    }

    pub fn exit(self: *Self) void {
        // Restore saved filters
        if (self.saved_filters) |sf| {
            self.module.?.filters.clearRetainingCapacity();
            for (sf.items) |f| {
                self.module.?.filters.append(f) catch {};
            }
        }
    }
};

/// Create a catch_warnings context manager
pub fn catchWarnings(allocator: std.mem.Allocator, record: bool) CatchWarnings {
    return CatchWarnings.init(allocator, record);
}

// ============================================================================
// Format Warning
// ============================================================================

/// Format a warning message (like formatwarning in Python)
pub fn formatWarning(
    allocator: std.mem.Allocator,
    message: []const u8,
    category: WarningCategory,
    filename: []const u8,
    lineno: usize,
    line: ?[]const u8,
) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    const writer = result.writer();

    try writer.print("{s}:{d}: {s}: {s}\n", .{ filename, lineno, category.name(), message });

    if (line) |l| {
        try writer.print("  {s}\n", .{l});
    }

    return result.toOwnedSlice();
}

// ============================================================================
// Show Warning (customizable hook)
// ============================================================================

/// Default show warning function
pub fn showWarning(
    message: []const u8,
    category: WarningCategory,
    filename: []const u8,
    lineno: usize,
    _: ?std.fs.File,
    _: ?[]const u8,
) void {
    const stderr = std.io.getStdErr().writer();
    stderr.print("{s}:{d}: {s}: {s}\n", .{ filename, lineno, category.name(), message }) catch {};
}

// ============================================================================
// Tests
// ============================================================================

test "WarningCategory names" {
    try std.testing.expectEqualStrings("DeprecationWarning", WarningCategory.DeprecationWarning.name());
    try std.testing.expectEqualStrings("UserWarning", WarningCategory.UserWarning.name());
    try std.testing.expectEqualStrings("RuntimeWarning", WarningCategory.RuntimeWarning.name());
}

test "WarningCategory isSubclassOf" {
    try std.testing.expect(WarningCategory.DeprecationWarning.isSubclassOf(.Warning));
    try std.testing.expect(WarningCategory.UserWarning.isSubclassOf(.Warning));
    try std.testing.expect(WarningCategory.Warning.isSubclassOf(.Warning));
    try std.testing.expect(!WarningCategory.DeprecationWarning.isSubclassOf(.UserWarning));
}

test "FilterAction conversion" {
    try std.testing.expectEqual(FilterAction.default, FilterAction.fromString("default").?);
    try std.testing.expectEqual(FilterAction.@"error", FilterAction.fromString("error").?);
    try std.testing.expectEqual(FilterAction.ignore, FilterAction.fromString("ignore").?);
    try std.testing.expect(FilterAction.fromString("invalid") == null);

    try std.testing.expectEqualStrings("always", FilterAction.always.toString());
}

test "WarningFilter matches" {
    const filter = WarningFilter{
        .action = .ignore,
        .category = .DeprecationWarning,
    };

    // Should match DeprecationWarning
    try std.testing.expect(filter.matches("test", .DeprecationWarning, "module", 1));

    // Should not match UserWarning (not a subclass of DeprecationWarning)
    try std.testing.expect(!filter.matches("test", .UserWarning, "module", 1));
}

test "WarningsState" {
    const allocator = std.testing.allocator;

    var state = WarningsState.init(allocator);
    defer state.deinit();

    try state.appendFilter(.{
        .action = .ignore,
        .category = .DeprecationWarning,
    });

    try std.testing.expectEqual(FilterAction.ignore, state.getAction("test", .DeprecationWarning, "mod", 1));
    try std.testing.expectEqual(FilterAction.default, state.getAction("test", .UserWarning, "mod", 1));
}

test "CatchWarnings" {
    const allocator = std.testing.allocator;

    var cw = catchWarnings(allocator, true);
    defer cw.deinit();

    _ = cw.enter();
    // Would record warnings here
    cw.exit();
}

test "formatWarning" {
    const allocator = std.testing.allocator;

    const formatted = try formatWarning(
        allocator,
        "test warning",
        .UserWarning,
        "test.py",
        42,
        null,
    );
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "UserWarning") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "test.py") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "42") != null);
}
