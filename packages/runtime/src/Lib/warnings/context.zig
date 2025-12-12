//! CatchWarnings context manager
//!
//! Context manager for temporarily modifying warning filters and recording warnings.

const std = @import("std");
const types = @import("types.zig");
const state = @import("state.zig");

/// Context manager for temporarily modifying warning filters
pub const CatchWarnings = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    record: bool,
    module: ?*state.WarningsState = null,
    saved_filters: std.ArrayList(types.WarningFilter) = .{},
    log: std.ArrayList(types.WarningRecord) = .{},

    pub fn init(allocator: std.mem.Allocator, record: bool) Self {
        return .{
            .allocator = allocator,
            .record = record,
        };
    }

    pub fn deinit(self: *Self) void {
        self.log.deinit(self.allocator);
        self.saved_filters.deinit(self.allocator);
    }

    pub fn enter(self: *Self) *std.ArrayList(types.WarningRecord) {
        self.module = state.getState(self.allocator);
        // Save current filters
        for (self.module.?.filters.items) |f| {
            self.saved_filters.append(self.allocator, f) catch {};
        }
        return &self.log;
    }

    pub fn exit(self: *Self) void {
        // Restore saved filters
        self.module.?.filters.clearRetainingCapacity();
        for (self.saved_filters.items) |f| {
            self.module.?.filters.append(self.allocator, f) catch {};
        }
    }
};

/// Create a catch_warnings context manager
pub fn catchWarnings(allocator: std.mem.Allocator, record: bool) CatchWarnings {
    return CatchWarnings.init(allocator, record);
}
