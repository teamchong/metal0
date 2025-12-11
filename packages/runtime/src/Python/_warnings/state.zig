/// Warning State
/// Mirrors cpython/Python/_warnings.c - global warning state management

const std = @import("std");
const Allocator = std.mem.Allocator;
const WarningAction = @import("action.zig").WarningAction;
const WarningCategory = @import("category.zig").WarningCategory;
const WarningFilter = @import("filter.zig").WarningFilter;
const WarningRegistry = @import("registry.zig").WarningRegistry;

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
