/// Wide String List
/// Mirrors cpython/Python/initconfig.c - wide string list handling
///
/// This module provides a dynamic list of strings for configuration options like:
/// - argv (command-line arguments)
/// - sys.path (module search paths)
/// - environment variables

const std = @import("std");
const Allocator = std.mem.Allocator;

/// List of strings (for argv, path, etc.)
pub const PyWideStringList = struct {
    items: std.ArrayList([]const u8),

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .items = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.items.deinit();
    }

    pub fn append(self: *Self, item: []const u8) !void {
        try self.items.append(item);
    }

    pub fn insert(self: *Self, index: usize, item: []const u8) !void {
        try self.items.insert(index, item);
    }

    pub fn clear(self: *Self) void {
        self.items.clearRetainingCapacity();
    }

    pub fn length(self: *const Self) usize {
        return self.items.items.len;
    }

    pub fn get(self: *const Self, index: usize) ?[]const u8 {
        if (index >= self.items.items.len) return null;
        return self.items.items[index];
    }
};
