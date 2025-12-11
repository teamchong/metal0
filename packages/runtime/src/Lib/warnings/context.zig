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
    saved_filters: ?std.ArrayList(types.WarningFilter) = null,
    log: std.ArrayList(types.WarningRecord),

    pub fn init(allocator: std.mem.Allocator, record: bool) Self {
        return .{
            .allocator = allocator,
            .record = record,
            .log = std.ArrayList(types.WarningRecord).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.log.deinit();
        if (self.saved_filters) |*sf| {
            sf.deinit();
        }
    }

    pub fn enter(self: *Self) *std.ArrayList(types.WarningRecord) {
        self.module = state.getState(self.allocator);
        // Save current filters
        self.saved_filters = std.ArrayList(types.WarningFilter).init(self.allocator);
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
