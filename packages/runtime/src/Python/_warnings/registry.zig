/// Warning Registry
/// Mirrors cpython/Python/_warnings.c - tracking shown warnings

const std = @import("std");
const Allocator = std.mem.Allocator;
const WarningCategory = @import("category.zig").WarningCategory;

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
