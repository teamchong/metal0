//! test.test_capi.test_module7 - C API Module Tests Part 7 - String Operations
const std = @import("std");

/// Unicode string object
pub const PyUnicode = struct {
    data: []const u8,
    length: usize,
    kind: StringKind,
    hash: ?u64 = null,

    pub const StringKind = enum {
        ASCII,
        UCS1,
        UCS2,
        UCS4,
    };

    pub fn fromString(data: []const u8) PyUnicode {
        return .{
            .data = data,
            .length = data.len,
            .kind = .ASCII,
        };
    }

    pub fn len(self: *const PyUnicode) usize {
        return self.length;
    }

    pub fn asSlice(self: *const PyUnicode) []const u8 {
        return self.data;
    }

    pub fn getHash(self: *PyUnicode) u64 {
        if (self.hash) |h| return h;
        self.hash = std.hash.Wyhash.hash(0, self.data);
        return self.hash.?;
    }

    pub fn eql(self: *const PyUnicode, other: *const PyUnicode) bool {
        return std.mem.eql(u8, self.data, other.data);
    }

    pub fn startsWith(self: *const PyUnicode, prefix: []const u8) bool {
        return std.mem.startsWith(u8, self.data, prefix);
    }

    pub fn endsWith(self: *const PyUnicode, suffix: []const u8) bool {
        return std.mem.endsWith(u8, self.data, suffix);
    }

    pub fn contains(self: *const PyUnicode, needle: []const u8) bool {
        return std.mem.indexOf(u8, self.data, needle) != null;
    }

    pub fn find(self: *const PyUnicode, needle: []const u8) ?usize {
        return std.mem.indexOf(u8, self.data, needle);
    }
};

/// String builder for efficient concatenation
pub const StringBuilder = struct {
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) StringBuilder {
        return .{ .buffer = std.ArrayList(u8).init(allocator) };
    }

    pub fn deinit(self: *StringBuilder) void {
        self.buffer.deinit();
    }

    pub fn append(self: *StringBuilder, str: []const u8) !void {
        try self.buffer.appendSlice(str);
    }

    pub fn appendChar(self: *StringBuilder, char: u8) !void {
        try self.buffer.append(char);
    }

    pub fn toString(self: *StringBuilder) []const u8 {
        return self.buffer.items;
    }

    pub fn clear(self: *StringBuilder) void {
        self.buffer.clearRetainingCapacity();
    }

    pub fn len(self: *const StringBuilder) usize {
        return self.buffer.items.len;
    }
};

/// String formatting
pub const StringFormatter = struct {
    format: []const u8,

    pub fn init(format: []const u8) StringFormatter {
        return .{ .format = format };
    }

    pub fn formatInt(self: *const StringFormatter, allocator: std.mem.Allocator, value: i64) ![]u8 {
        _ = self;
        return std.fmt.allocPrint(allocator, "{d}", .{value});
    }

    pub fn formatFloat(self: *const StringFormatter, allocator: std.mem.Allocator, value: f64) ![]u8 {
        _ = self;
        return std.fmt.allocPrint(allocator, "{d:.6}", .{value});
    }
};

/// String case operations
pub fn toUpper(allocator: std.mem.Allocator, str: []const u8) ![]u8 {
    const result = try allocator.alloc(u8, str.len);
    for (str, 0..) |c, i| {
        result[i] = std.ascii.toUpper(c);
    }
    return result;
}

pub fn toLower(allocator: std.mem.Allocator, str: []const u8) ![]u8 {
    const result = try allocator.alloc(u8, str.len);
    for (str, 0..) |c, i| {
        result[i] = std.ascii.toLower(c);
    }
    return result;
}

/// String trimming
pub fn strip(str: []const u8) []const u8 {
    return std.mem.trim(u8, str, &std.ascii.whitespace);
}

pub fn lstrip(str: []const u8) []const u8 {
    return std.mem.trimLeft(u8, str, &std.ascii.whitespace);
}

pub fn rstrip(str: []const u8) []const u8 {
    return std.mem.trimRight(u8, str, &std.ascii.whitespace);
}

test "PyUnicode creation" {
    const s = PyUnicode.fromString("hello");
    try std.testing.expectEqual(@as(usize, 5), s.len());
    try std.testing.expectEqualStrings("hello", s.asSlice());
}

test "PyUnicode equality" {
    var s1 = PyUnicode.fromString("test");
    var s2 = PyUnicode.fromString("test");
    var s3 = PyUnicode.fromString("other");

    try std.testing.expect(s1.eql(&s2));
    try std.testing.expect(!s1.eql(&s3));
}

test "PyUnicode methods" {
    const s = PyUnicode.fromString("hello world");

    try std.testing.expect(s.startsWith("hello"));
    try std.testing.expect(s.endsWith("world"));
    try std.testing.expect(s.contains("lo wo"));
    try std.testing.expectEqual(@as(usize, 6), s.find("world").?);
}

test "StringBuilder" {
    const allocator = std.testing.allocator;
    var sb = StringBuilder.init(allocator);
    defer sb.deinit();

    try sb.append("Hello");
    try sb.appendChar(' ');
    try sb.append("World");

    try std.testing.expectEqualStrings("Hello World", sb.toString());
}

test "case conversion" {
    const allocator = std.testing.allocator;

    const upper = try toUpper(allocator, "hello");
    defer allocator.free(upper);
    try std.testing.expectEqualStrings("HELLO", upper);

    const lower = try toLower(allocator, "WORLD");
    defer allocator.free(lower);
    try std.testing.expectEqualStrings("world", lower);
}

test "string trim" {
    try std.testing.expectEqualStrings("hello", strip("  hello  "));
    try std.testing.expectEqualStrings("hello  ", lstrip("  hello  "));
    try std.testing.expectEqualStrings("  hello", rstrip("  hello  "));
}
