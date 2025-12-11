//! Parse result struct and accessor methods
//!
//! Contains the ParseResult struct which holds parsed argument values.

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");
const types = @import("types.zig");

/// Result of parsing arguments
pub const ParseResult = struct {
    const Self = @This();
    const ValueMap = hashmap_helper.StringHashMap(types.ArgValue);
    const StringList = std.ArrayList([]const u8);

    allocator: std.mem.Allocator,
    values: ValueMap,
    remaining: StringList,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .values = ValueMap.init(allocator),
            .remaining = StringList.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.values.deinit();
        self.remaining.deinit();
    }

    /// Get a string argument
    pub fn getString(self: Self, name: []const u8) ?[]const u8 {
        if (self.values.get(name)) |val| {
            return switch (val) {
                .string => |s| s,
                else => null,
            };
        }
        return null;
    }

    /// Get a boolean argument
    pub fn getBool(self: Self, name: []const u8) bool {
        if (self.values.get(name)) |val| {
            return switch (val) {
                .boolean => |b| b,
                else => false,
            };
        }
        return false;
    }

    /// Get a count argument
    pub fn getCount(self: Self, name: []const u8) u32 {
        if (self.values.get(name)) |val| {
            return switch (val) {
                .count => |c| c,
                else => 0,
            };
        }
        return 0;
    }

    /// Get an integer argument
    pub fn getInt(self: Self, name: []const u8) ?i64 {
        if (self.getString(name)) |s| {
            return std.fmt.parseInt(i64, s, 10) catch null;
        }
        return null;
    }

    /// Check if an argument was provided
    pub fn has(self: Self, name: []const u8) bool {
        return self.values.contains(name);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "ParseResult" {
    const allocator = std.testing.allocator;

    var result = ParseResult.init(allocator);
    defer result.deinit();

    try result.values.put("verbose", .{ .boolean = true });
    try result.values.put("count", .{ .count = 3 });
    try result.values.put("name", .{ .string = "test" });

    try std.testing.expect(result.getBool("verbose"));
    try std.testing.expectEqual(@as(u32, 3), result.getCount("count"));
    try std.testing.expectEqualStrings("test", result.getString("name").?);
    try std.testing.expect(result.has("verbose"));
    try std.testing.expect(!result.has("missing"));
}
