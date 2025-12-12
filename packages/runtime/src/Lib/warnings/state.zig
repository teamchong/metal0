//! Global warnings state management
//!
//! Manages warning filters and tracking of seen warnings.

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");
const types = @import("types.zig");

/// Global warnings state
pub const WarningsState = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    filters: std.ArrayList(types.WarningFilter) = .{},
    once_registry: hashmap_helper.StringHashMap(void),
    default_action: types.FilterAction = .default,
    show_source: bool = true,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .once_registry = hashmap_helper.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.filters.deinit(self.allocator);
        self.once_registry.deinit();
    }

    /// Add a filter at the beginning of the filter list
    pub fn insertFilter(self: *Self, filter: types.WarningFilter) !void {
        try self.filters.insert(self.allocator, 0, filter);
    }

    /// Add a filter at the end of the filter list
    pub fn appendFilter(self: *Self, filter: types.WarningFilter) !void {
        try self.filters.append(self.allocator, filter);
    }

    /// Get the action for a warning
    pub fn getAction(
        self: Self,
        message: []const u8,
        category: types.WarningCategory,
        module_name: []const u8,
        lineno: usize,
    ) types.FilterAction {
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

pub fn getState(allocator: std.mem.Allocator) *WarningsState {
    if (global_state == null) {
        global_state = WarningsState.init(allocator);
    }
    return &global_state.?;
}
