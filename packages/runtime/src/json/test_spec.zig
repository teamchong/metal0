// JSON RFC 8259 Specification Compliance Tests
const std = @import("std");
const testing = std.testing;
const json = @import("value.zig");
const parse = @import("parse.zig");

test "parse all escape sequences" {
    const allocator = testing.allocator;

    // Test all basic escape sequences
    const cases = [_]struct { input: []const u8, expected: []const u8 }{
        .{ .input = "\"\\\"\"", .expected = "\"" }, // \"
        .{ .input = "\"\\\\\"", .expected = "\\" }, // \\
        .{ .input = "\"\\/\"", .expected = "/" },   // \/
        .{ .input = "\"\\b\"", .expected = "\x08" }, // \b (backspace)
        .{ .input = "\"\\f\"", .expected = "\x0C" }, // \f (form feed)
        .{ .input = "\"\\n\"", .expected = "\n" },  // \n
        .{ .input = "\"\\r\"", .expected = "\r" },  // \r
        .{ .input = "\"\\t\"", .expected = "\t" },  // \t
    };

    for (cases) |case| {
        var parsed = try parse.parse(case.input, allocator);
        defer parsed.deinit();

        try testing.expectEqualStrings(case.expected, parsed.string);
    }
}

test "parse unicode escapes" {
    const allocator = testing.allocator;

    const cases = [_]struct { input: []const u8, expected: []const u8 }{
        // Basic unicode
        .{ .input = "\"\\u0041\"", .expected = "A" },
        .{ .input = "\"\\u0061\"", .expected = "a" },
        .{ .input = "\"\\u00E9\"", .expected = "é" },

        // Surrogate pairs (UTF-16 encoding for characters > U+FFFF)
        .{ .input = "\"\\uD83D\\uDE00\"", .expected = "😀" }, // Grinning face emoji
    };

    for (cases) |case| {
        var parsed = try parse.parse(case.input, allocator);
        defer parsed.deinit();

        try testing.expectEqualStrings(case.expected, parsed.string);
    }
}

test "parse scientific notation numbers" {
    const allocator = testing.allocator;

    const cases = [_]struct { input: []const u8, expected: f64 }{
        // Positive exponent
        .{ .input = "1e10", .expected = 1e10 },
        .{ .input = "1E10", .expected = 1e10 },
        .{ .input = "1e+10", .expected = 1e10 },
        .{ .input = "2.5e10", .expected = 2.5e10 },

        // Negative exponent
        .{ .input = "1e-10", .expected = 1e-10 },
        .{ .input = "1.5e-3", .expected = 1.5e-3 },
        .{ .input = "2.5E+20", .expected = 2.5e20 },

        // Edge cases
        .{ .input = "1e308", .expected = 1e308 },   // Near max double
        .{ .input = "1e-308", .expected = 1e-308 }, // Near min double
    };

    for (cases) |case| {
        var parsed = try parse.parse(case.input, allocator);
        defer parsed.deinit();

        const actual = switch (parsed) {
            .float => |f| f,
            .int => |i| @as(f64, @floatFromInt(i)),
            else => unreachable,
        };

        try testing.expectApproxEqAbs(case.expected, actual, 1e-10);
    }
}

test "parse all number formats" {
    const allocator = testing.allocator;

    const int_cases = [_]struct { input: []const u8, expected: i64 }{
        .{ .input = "0", .expected = 0 },
        .{ .input = "123", .expected = 123 },
        .{ .input = "-123", .expected = -123 },
        .{ .input = "2147483647", .expected = 2147483647 },  // Max i32
        .{ .input = "-2147483648", .expected = -2147483648 }, // Min i32
    };

    for (int_cases) |case| {
        var parsed = try parse.parse(case.input, allocator);
        defer parsed.deinit();

        try testing.expectEqual(case.expected, parsed.int);
    }

    const float_cases = [_]struct { input: []const u8, expected: f64 }{
        .{ .input = "0.0", .expected = 0.0 },
        .{ .input = "3.14", .expected = 3.14 },
        .{ .input = "-3.14", .expected = -3.14 },
        .{ .input = "0.123456789", .expected = 0.123456789 },
    };

    for (float_cases) |case| {
        var parsed = try parse.parse(case.input, allocator);
        defer parsed.deinit();

        try testing.expectApproxEqAbs(case.expected, parsed.float, 1e-10);
    }
}

test "parse nested structures" {
    const allocator = testing.allocator;

    const input =
        \\{"user": {"name": "John", "age": 30}, "items": [1, 2, 3]}
    ;

    var parsed = try parse.parse(input, allocator);
    defer parsed.deinit();

    try testing.expect(parsed == .object);
    try testing.expect(parsed.object.get("user") != null);
    try testing.expect(parsed.object.get("items") != null);
}

test "reject invalid JSON" {
    const allocator = testing.allocator;

    const invalid_cases = [_][]const u8{
        "\"unclosed string",
        "{\"key\": }",          // Missing value
        "[1, 2, ]",            // Trailing comma
        "{'key': 'value'}",    // Single quotes
        "{key: \"value\"}",    // Unquoted key
        "\"bad\\escape\"",     // Invalid escape
        "\"\x00\"",            // Unescaped control char
    };

    for (invalid_cases) |case| {
        const result = parse.parse(case, allocator);
        try testing.expectError(error.JsonError, result);
    }
}
