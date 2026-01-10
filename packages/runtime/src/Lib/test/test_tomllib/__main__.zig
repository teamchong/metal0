//! test.test_tomllib - TOML parsing tests
const std = @import("std");

pub const TOMLValue = union(enum) {
    string: []const u8,
    integer: i64,
    float: f64,
    boolean: bool,
    datetime: DateTime,
    array: std.ArrayList(TOMLValue),
    table: std.StringHashMap(TOMLValue),
};

pub const DateTime = struct {
    year: u16 = 0,
    month: u8 = 0,
    day: u8 = 0,
    hour: u8 = 0,
    minute: u8 = 0,
    second: u8 = 0,
};

pub const TOMLParser = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator };
    }
    
    pub fn parse(self: @This(), input: []const u8) !std.StringHashMap(TOMLValue) {
        var result = std.StringHashMap(TOMLValue).init(self.allocator);
        var lines = std.mem.splitScalar(u8, input, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#') continue;
            if (std.mem.indexOf(u8, trimmed, "=")) |eq| {
                const key = std.mem.trim(u8, trimmed[0..eq], " \t");
                const val = std.mem.trim(u8, trimmed[eq+1..], " \t");
                try result.put(key, try self.parseValue(val));
            }
        }
        return result;
    }
    
    fn parseValue(self: @This(), val: []const u8) !TOMLValue {
        _ = self;
        if (val.len == 0) return .{ .string = "" };
        if (val[0] == '"' and val[val.len-1] == '"') {
            return .{ .string = val[1..val.len-1] };
        }
        if (std.mem.eql(u8, val, "true")) return .{ .boolean = true };
        if (std.mem.eql(u8, val, "false")) return .{ .boolean = false };
        if (std.fmt.parseInt(i64, val, 10)) |i| {
            return .{ .integer = i };
        } else |_| {}
        if (std.fmt.parseFloat(f64, val)) |f| {
            return .{ .float = f };
        } else |_| {}
        return .{ .string = val };
    }
};

pub fn loads(allocator: std.mem.Allocator, s: []const u8) !std.StringHashMap(TOMLValue) {
    const parser = TOMLParser.init(allocator);
    return parser.parse(s);
}

test "toml_string" {
    var result = try loads(std.testing.allocator, "name = \"value\"");
    defer result.deinit();
    if (result.get("name")) |v| {
        try std.testing.expectEqualStrings("value", v.string);
    }
}

test "toml_integer" {
    var result = try loads(std.testing.allocator, "count = 42");
    defer result.deinit();
    if (result.get("count")) |v| {
        try std.testing.expectEqual(@as(i64, 42), v.integer);
    }
}

test "toml_boolean" {
    var result = try loads(std.testing.allocator, "enabled = true");
    defer result.deinit();
    if (result.get("enabled")) |v| {
        try std.testing.expect(v.boolean);
    }
}

test "toml_comment" {
    var result = try loads(std.testing.allocator, "# comment\nkey = \"val\"");
    defer result.deinit();
    try std.testing.expect(result.contains("key"));
}
