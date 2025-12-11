//! namedtuple - Create tuple subclass with named fields
//!
//! Mirrors: CPython Lib/collections/__init__.py - namedtuple

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

/// Create a namedtuple type with given field names
pub fn namedtuple(comptime name: []const u8, comptime fields: []const []const u8) type {
    return struct {
        const Self = @This();
        pub const _name = name;
        pub const _fields = fields;

        values: [fields.len][]const u8,

        /// Create a new named tuple
        pub fn init(values: [fields.len][]const u8) Self {
            return .{ .values = values };
        }

        /// Get value by field name
        pub fn get(self: Self, comptime field_name: []const u8) []const u8 {
            inline for (fields, 0..) |f, i| {
                if (comptime std.mem.eql(u8, f, field_name)) {
                    return self.values[i];
                }
            }
            @compileError("Unknown field: " ++ field_name);
        }

        /// Get value by index
        pub fn getIndex(self: Self, index: usize) ?[]const u8 {
            if (index < fields.len) {
                return self.values[index];
            }
            return null;
        }

        /// Convert to slice
        pub fn toSlice(self: Self) []const []const u8 {
            return &self.values;
        }

        /// Get the number of fields
        pub fn len() usize {
            return fields.len;
        }

        /// Replace values
        pub fn replace(self: Self, comptime field_name: []const u8, new_value: []const u8) Self {
            var result = self;
            inline for (fields, 0..) |f, i| {
                if (comptime std.mem.eql(u8, f, field_name)) {
                    result.values[i] = new_value;
                    return result;
                }
            }
            @compileError("Unknown field: " ++ field_name);
        }

        /// Convert to dict-like representation
        pub fn asDict(self: Self, allocator: std.mem.Allocator) !hashmap_helper.StringHashMap([]const u8) {
            var dict = hashmap_helper.StringHashMap([]const u8).init(allocator);
            errdefer dict.deinit();
            inline for (fields, 0..) |f, i| {
                try dict.put(f, self.values[i]);
            }
            return dict;
        }
    };
}

test "namedtuple" {
    const Point = namedtuple("Point", &.{ "x", "y" });
    const p = Point.init(.{ "10", "20" });

    try std.testing.expectEqualStrings("10", p.get("x"));
    try std.testing.expectEqualStrings("20", p.get("y"));
    try std.testing.expectEqual(@as(usize, 2), Point.len());
}
