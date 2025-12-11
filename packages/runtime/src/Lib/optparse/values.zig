//! CPython source: Lib/optparse.py
//!
//! Container for parsed option values.
//! Mirrors: CPython Lib/optparse.py

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

/// Container for parsed option values
pub const Values = struct {
    const Self = @This();
    const ValueMap = hashmap_helper.StringHashMap(Value);

    allocator: std.mem.Allocator,
    values: ValueMap,

    pub const Value = union(enum) {
        string: []const u8,
        string_list: std.ArrayList([]const u8),
        boolean: bool,
        integer: i64,
        float: f64,
        count: u32,
        none,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .values = ValueMap.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.values.iterator();
        while (it.next()) |entry| {
            switch (entry.value_ptr.*) {
                .string_list => |*list| list.deinit(),
                else => {},
            }
        }
        self.values.deinit();
    }

    pub fn set(self: *Self, key: []const u8, value: Value) !void {
        try self.values.put(key, value);
    }

    pub fn get(self: Self, key: []const u8) ?Value {
        return self.values.get(key);
    }

    pub fn getString(self: Self, key: []const u8) ?[]const u8 {
        if (self.values.get(key)) |val| {
            return switch (val) {
                .string => |s| s,
                else => null,
            };
        }
        return null;
    }

    pub fn getBool(self: Self, key: []const u8) bool {
        if (self.values.get(key)) |val| {
            return switch (val) {
                .boolean => |b| b,
                else => false,
            };
        }
        return false;
    }

    pub fn getInt(self: Self, key: []const u8) ?i64 {
        if (self.values.get(key)) |val| {
            return switch (val) {
                .integer => |i| i,
                .string => |s| std.fmt.parseInt(i64, s, 10) catch null,
                else => null,
            };
        }
        return null;
    }

    pub fn getCount(self: Self, key: []const u8) u32 {
        if (self.values.get(key)) |val| {
            return switch (val) {
                .count => |c| c,
                else => 0,
            };
        }
        return 0;
    }

    pub fn has(self: Self, key: []const u8) bool {
        return self.values.contains(key);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Values" {
    const allocator = std.testing.allocator;
    var values = Values.init(allocator);
    defer values.deinit();

    try values.set("name", .{ .string = "test" });
    try values.set("verbose", .{ .boolean = true });
    try values.set("count", .{ .count = 3 });

    try std.testing.expectEqualStrings("test", values.getString("name").?);
    try std.testing.expect(values.getBool("verbose"));
    try std.testing.expectEqual(@as(u32, 3), values.getCount("count"));
    try std.testing.expect(values.has("name"));
    try std.testing.expect(!values.has("missing"));
}
