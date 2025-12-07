/// _warnings - Warnings Subsystem Implementation
/// Mirrors cpython/Python/_warnings.c
///
/// This module provides the low-level warnings infrastructure:
/// - Warning categories and filters
/// - Warning message formatting
/// - Default and custom warning handlers
/// - Per-module warning state

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Warning Categories
// ============================================================================

/// Built-in warning categories
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

    pub fn fromString(s: []const u8) ?WarningCategory {
        const categories = [_]WarningCategory{
            .Warning,            .UserWarning,
            .DeprecationWarning, .PendingDeprecationWarning,
            .SyntaxWarning,      .RuntimeWarning,
            .FutureWarning,      .ImportWarning,
            .UnicodeWarning,     .BytesWarning,
            .EncodingWarning,    .ResourceWarning,
        };
        for (categories) |cat| {
            if (std.mem.eql(u8, s, cat.name())) {
                return cat;
            }
        }
        return null;
    }
};

// ============================================================================
// Warning Actions
// ============================================================================

/// Actions for handling warnings
pub const WarningAction = enum {
    error_action, // Turn into exception
    ignore, // Ignore completely
    always, // Always show
    default, // Show first occurrence per location
    module, // Show first occurrence per module
    once, // Show first occurrence globally

    pub fn fromString(s: []const u8) ?WarningAction {
        if (std.mem.eql(u8, s, "error")) return .error_action;
        if (std.mem.eql(u8, s, "ignore")) return .ignore;
        if (std.mem.eql(u8, s, "always")) return .always;
        if (std.mem.eql(u8, s, "default")) return .default;
        if (std.mem.eql(u8, s, "module")) return .module;
        if (std.mem.eql(u8, s, "once")) return .once;
        return null;
    }

    pub fn toString(self: WarningAction) []const u8 {
        return switch (self) {
            .error_action => "error",
            .ignore => "ignore",
            .always => "always",
            .default => "default",
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
    action: WarningAction,
    message_pattern: ?[]const u8,
    category: ?WarningCategory,
    module_pattern: ?[]const u8,
    lineno: u32, // 0 = any line

    const Self = @This();

    pub fn init(
        action: WarningAction,
        message: ?[]const u8,
        category: ?WarningCategory,
        mod: ?[]const u8,
        lineno: u32,
    ) Self {
        return .{
            .action = action,
            .message_pattern = message,
            .category = category,
            .module_pattern = mod,
            .lineno = lineno,
        };
    }

    /// Check if filter matches a warning
    pub fn matches(
        self: *const Self,
        message: []const u8,
        category: WarningCategory,
        mod: []const u8,
        lineno: u32,
    ) bool {
        // Check lineno (0 means any)
        if (self.lineno != 0 and self.lineno != lineno) {
            return false;
        }

        // Check category
        if (self.category) |cat| {
            if (cat != category) return false;
        }

        // Check message pattern (simple substring for now)
        if (self.message_pattern) |pattern| {
            if (std.mem.indexOf(u8, message, pattern) == null) {
                return false;
            }
        }

        // Check module pattern (simple substring)
        if (self.module_pattern) |pattern| {
            if (std.mem.indexOf(u8, mod, pattern) == null) {
                return false;
            }
        }

        return true;
    }
};

// ============================================================================
// Warning Registry
// ============================================================================

/// Registry for tracking shown warnings
pub const WarningRegistry = struct {
    /// Warnings that have been shown (by key)
    shown: std.AutoHashMap(u64, bool),
    /// Allocator
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .shown = std.AutoHashMap(u64, bool).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.shown.deinit();
    }

    fn computeKey(message: []const u8, category: WarningCategory, lineno: u32) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(message);
        hasher.update(&[_]u8{@intFromEnum(category)});
        hasher.update(std.mem.asBytes(&lineno));
        return hasher.final();
    }

    /// Check if warning was shown globally (for "once" action)
    pub fn wasShownOnce(self: *Self, message: []const u8, category: WarningCategory) bool {
        const key = computeKey(message, category, 0);
        return self.shown.contains(key);
    }

    /// Mark warning as shown globally
    pub fn markShownOnce(self: *Self, message: []const u8, category: WarningCategory) !void {
        const key = computeKey(message, category, 0);
        try self.shown.put(key, true);
    }

    /// Check if warning was shown at this location (for "default" action)
    pub fn wasShownAtLocation(
        self: *Self,
        message: []const u8,
        category: WarningCategory,
        lineno: u32,
    ) bool {
        const key = computeKey(message, category, lineno);
        return self.shown.contains(key);
    }

    /// Mark warning as shown at location
    pub fn markShownAtLocation(
        self: *Self,
        message: []const u8,
        category: WarningCategory,
        lineno: u32,
    ) !void {
        const key = computeKey(message, category, lineno);
        try self.shown.put(key, true);
    }
};

// ============================================================================
// Warning State
// ============================================================================

/// Global warnings state
pub const WarningsState = struct {
    /// Warning filters (checked in order)
    filters: std.ArrayList(WarningFilter),
    /// Warning registry for tracking shown warnings
    registry: WarningRegistry,
    /// Default filter for unmatched warnings
    default_action: WarningAction,
    /// Whether warnings are enabled
    enabled: bool,
    /// Custom warning handler
    handler: ?*const fn ([]const u8, WarningCategory, []const u8, u32) void,
    /// Allocator
    allocator: Allocator,

    const Self = @This();

    pub fn create(allocator: Allocator) Self {
        return .{
            .filters = std.ArrayList(WarningFilter).init(allocator),
            .registry = WarningRegistry.init(allocator),
            .default_action = .default,
            .enabled = true,
            .handler = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.filters.deinit();
        self.registry.deinit();
    }

    /// Add a warning filter
    pub fn addFilter(self: *Self, filter: WarningFilter) !void {
        try self.filters.append(filter);
    }

    /// Insert filter at beginning (highest priority)
    pub fn insertFilter(self: *Self, filter: WarningFilter) !void {
        try self.filters.insert(0, filter);
    }

    /// Clear all filters
    pub fn clearFilters(self: *Self) void {
        self.filters.clearRetainingCapacity();
    }

    /// Reset to default filters
    pub fn resetFilters(self: *Self) !void {
        self.clearFilters();
        // Add default filters (Python's default warning filters)
        try self.addFilter(WarningFilter.init(.default, null, .DeprecationWarning, "__main__", 0));
        try self.addFilter(WarningFilter.init(.ignore, null, .DeprecationWarning, null, 0));
        try self.addFilter(WarningFilter.init(.ignore, null, .PendingDeprecationWarning, null, 0));
        try self.addFilter(WarningFilter.init(.ignore, null, .ImportWarning, null, 0));
        try self.addFilter(WarningFilter.init(.ignore, null, .ResourceWarning, null, 0));
    }

    /// Find matching filter for a warning
    pub fn findFilter(
        self: *const Self,
        message: []const u8,
        category: WarningCategory,
        mod: []const u8,
        lineno: u32,
    ) ?*const WarningFilter {
        for (self.filters.items) |*filter| {
            if (filter.matches(message, category, mod, lineno)) {
                return filter;
            }
        }
        return null;
    }

    /// Get action for a warning
    pub fn getAction(
        self: *const Self,
        message: []const u8,
        category: WarningCategory,
        mod: []const u8,
        lineno: u32,
    ) WarningAction {
        if (self.findFilter(message, category, mod, lineno)) |filter| {
            return filter.action;
        }
        return self.default_action;
    }
};

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
        global_state = WarningsState.create(std.heap.page_allocator);
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
    var state = WarningsState.create(std.testing.allocator);
    defer state.deinit();

    try std.testing.expect(state.enabled);
    try std.testing.expectEqual(WarningAction.default, state.default_action);

    // Add a filter
    const filter = WarningFilter.init(.ignore, null, .DeprecationWarning, null, 0);
    try state.addFilter(filter);

    // Check action
    const action = state.getAction("test", .DeprecationWarning, "module", 10);
    try std.testing.expectEqual(WarningAction.ignore, action);

    // Unmatched uses default
    const action2 = state.getAction("test", .UserWarning, "module", 10);
    try std.testing.expectEqual(WarningAction.default, action2);
}

test "warning registry" {
    var registry = WarningRegistry.init(std.testing.allocator);
    defer registry.deinit();

    // Test once tracking
    try std.testing.expect(!registry.wasShownOnce("msg", .UserWarning));
    try registry.markShownOnce("msg", .UserWarning);
    try std.testing.expect(registry.wasShownOnce("msg", .UserWarning));

    // Test location tracking
    try std.testing.expect(!registry.wasShownAtLocation("msg2", .RuntimeWarning, 42));
    try registry.markShownAtLocation("msg2", .RuntimeWarning, 42);
    try std.testing.expect(registry.wasShownAtLocation("msg2", .RuntimeWarning, 42));
    try std.testing.expect(!registry.wasShownAtLocation("msg2", .RuntimeWarning, 43));
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
