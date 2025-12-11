//! CPython source: Lib/configparser.py
//!
//! Tests for ConfigParser.

const std = @import("std");
const parser_mod = @import("parser.zig");
const ConfigParser = parser_mod.ConfigParser;

test "ConfigParser init" {
    const allocator = std.testing.allocator;
    var parser = ConfigParser.init(allocator, .{});
    defer parser.deinit();

    try std.testing.expect(!parser.hasSection("test"));
}

test "ConfigParser add section" {
    const allocator = std.testing.allocator;
    var parser = ConfigParser.init(allocator, .{});
    defer parser.deinit();

    try parser.addSection("test");
    try std.testing.expect(parser.hasSection("test"));
}

test "ConfigParser set and get" {
    const allocator = std.testing.allocator;
    var parser = ConfigParser.init(allocator, .{});
    defer parser.deinit();

    try parser.addSection("section1");
    try parser.set("section1", "key1", "value1");

    const value = try parser.get("section1", "key1");
    try std.testing.expectEqualStrings("value1", value);
}

test "ConfigParser read string" {
    const allocator = std.testing.allocator;
    var parser = ConfigParser.init(allocator, .{});
    defer parser.deinit();

    const content =
        \\[section1]
        \\key1 = value1
        \\key2 = value2
        \\
        \\[section2]
        \\key3 = value3
    ;

    try parser.readString(content);

    try std.testing.expect(parser.hasSection("section1"));
    try std.testing.expect(parser.hasSection("section2"));

    const value1 = try parser.get("section1", "key1");
    try std.testing.expectEqualStrings("value1", value1);
}

test "ConfigParser getInt" {
    const allocator = std.testing.allocator;
    var parser = ConfigParser.init(allocator, .{});
    defer parser.deinit();

    try parser.addSection("numbers");
    try parser.set("numbers", "count", "42");

    const count = try parser.getInt("numbers", "count");
    try std.testing.expectEqual(@as(i64, 42), count);
}

test "ConfigParser getBoolean" {
    const allocator = std.testing.allocator;
    var parser = ConfigParser.init(allocator, .{});
    defer parser.deinit();

    try parser.addSection("flags");
    try parser.set("flags", "enabled", "true");
    try parser.set("flags", "disabled", "false");

    const enabled = try parser.getBoolean("flags", "enabled");
    const disabled = try parser.getBoolean("flags", "disabled");

    try std.testing.expect(enabled);
    try std.testing.expect(!disabled);
}

test "ConfigParser remove section" {
    const allocator = std.testing.allocator;
    var parser = ConfigParser.init(allocator, .{});
    defer parser.deinit();

    try parser.addSection("temp");
    try std.testing.expect(parser.hasSection("temp"));

    const removed = parser.removeSection("temp");
    try std.testing.expect(removed);
    try std.testing.expect(!parser.hasSection("temp"));
}
