//! tomllib._types - Type definitions for TOML parsing
//! Reference: cpython/Lib/tomllib/_types.py
//!
//! Internal type definitions for TOML values.

const std = @import("std");

/// TOML value types
pub const TomlValue = union(enum) {
    string: []const u8,
    integer: i64,
    float: f64,
    boolean: bool,
    datetime: DateTime,
    date: Date,
    time: Time,
    array: TomlArray,
    table: TomlTable,
};

/// TOML array type
pub const TomlArray = struct {
    const Self = @This();

    items: std.ArrayList(TomlValue),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .items = std.ArrayList(TomlValue).init(allocator) };
    }

    pub fn deinit(self: *Self) void {
        self.items.deinit();
    }

    pub fn append(self: *Self, value: TomlValue) !void {
        try self.items.append(value);
    }
};

/// TOML table type (ordered map)
pub const TomlTable = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    map: std.StringHashMap(TomlValue),
    order: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .map = std.StringHashMap(TomlValue).init(allocator),
            .order = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.map.deinit();
        self.order.deinit(self.allocator);
    }

    pub fn put(self: *Self, key: []const u8, value: TomlValue) !void {
        if (!self.map.contains(key)) {
            try self.order.append(self.allocator, key);
        }
        try self.map.put(key, value);
    }

    pub fn get(self: *Self, key: []const u8) ?TomlValue {
        return self.map.get(key);
    }

    pub fn contains(self: *Self, key: []const u8) bool {
        return self.map.contains(key);
    }
};

/// TOML datetime (RFC 3339)
pub const DateTime = struct {
    year: u16,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
    microsecond: u32 = 0,
    offset: ?i16 = null, // Offset in minutes, null = local

    pub fn format(self: DateTime, allocator: std.mem.Allocator) ![]const u8 {
        if (self.offset) |off| {
            const sign: u8 = if (off >= 0) '+' else '-';
            const abs_off = if (off >= 0) @as(u16, @intCast(off)) else @as(u16, @intCast(-off));
            return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}{c}{d:0>2}:{d:0>2}", .{
                self.year,
                self.month,
                self.day,
                self.hour,
                self.minute,
                self.second,
                sign,
                abs_off / 60,
                abs_off % 60,
            });
        } else {
            return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}", .{
                self.year,
                self.month,
                self.day,
                self.hour,
                self.minute,
                self.second,
            });
        }
    }
};

/// TOML date
pub const Date = struct {
    year: u16,
    month: u8,
    day: u8,

    pub fn format(self: Date, allocator: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{
            self.year,
            self.month,
            self.day,
        });
    }
};

/// TOML time
pub const Time = struct {
    hour: u8,
    minute: u8,
    second: u8,
    microsecond: u32 = 0,

    pub fn format(self: Time, allocator: std.mem.Allocator) ![]const u8 {
        if (self.microsecond > 0) {
            return std.fmt.allocPrint(allocator, "{d:0>2}:{d:0>2}:{d:0>2}.{d:0>6}", .{
                self.hour,
                self.minute,
                self.second,
                self.microsecond,
            });
        } else {
            return std.fmt.allocPrint(allocator, "{d:0>2}:{d:0>2}:{d:0>2}", .{
                self.hour,
                self.minute,
                self.second,
            });
        }
    }
};

/// Key path for nested tables
pub const KeyPath = struct {
    const Self = @This();

    parts: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .parts = std.ArrayList([]const u8).init(allocator) };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.parts.deinit(allocator);
    }

    pub fn push(self: *Self, part: []const u8) !void {
        try self.parts.append(part);
    }

    pub fn pop(self: *Self) ?[]const u8 {
        return self.parts.popOrNull();
    }

    pub fn format(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        if (self.parts.items.len == 0) return "";

        var result: std.ArrayList(u8) = .{};
        for (self.parts.items, 0..) |part, i| {
            if (i > 0) try result.append(allocator, '.');
            try result.appendSlice(allocator, part);
        }
        return result.toOwnedSlice(allocator);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "TomlTable" {
    const allocator = std.testing.allocator;
    var table = TomlTable.init(allocator);
    defer table.deinit();

    try table.put("key", .{ .string = "value" });
    try std.testing.expect(table.contains("key"));

    if (table.get("key")) |v| {
        try std.testing.expectEqualStrings("value", v.string);
    } else {
        return error.TestUnexpectedResult;
    }
}

test "Date format" {
    const allocator = std.testing.allocator;
    const date = Date{ .year = 2024, .month = 1, .day = 15 };
    const formatted = try date.format(allocator);
    defer allocator.free(formatted);
    try std.testing.expectEqualStrings("2024-01-15", formatted);
}

test "Time format" {
    const allocator = std.testing.allocator;
    const time = Time{ .hour = 14, .minute = 30, .second = 45 };
    const formatted = try time.format(allocator);
    defer allocator.free(formatted);
    try std.testing.expectEqualStrings("14:30:45", formatted);
}
