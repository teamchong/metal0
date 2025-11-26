// JSON RFC 8259 Specification Compliance Tests
const std = @import("std");
const testing = std.testing;
const runtime = @import("runtime");
const parse = runtime.json.parse;
const JsonValue = runtime.json.JsonValue;

test "parse all escape sequences" {
    const allocator = testing.allocator;

    const cases = [_]struct { input: []const u8, expected: []const u8 }{
        .{ .input = "\"\\\"\"", .expected = "\"" },
        .{ .input = "\"\\\\\"", .expected = "\\" },
        .{ .input = "\"\\/\"", .expected = "/" },
        .{ .input = "\"\\b\"", .expected = "\x08" },
        .{ .input = "\"\\f\"", .expected = "\x0C" },
        .{ .input = "\"\\n\"", .expected = "\n" },
        .{ .input = "\"\\r\"", .expected = "\r" },
        .{ .input = "\"\\t\"", .expected = "\t" },
    };

    for (cases) |case| {
        var parsed = try parse.parse(case.input, allocator);
        defer parsed.deinit(allocator);
        try testing.expectEqualStrings(case.expected, parsed.string);
    }
}

test "parse scientific notation numbers" {
    const allocator = testing.allocator;

    const cases = [_]struct { input: []const u8, expected: f64 }{
        .{ .input = "1e10", .expected = 1e10 },
        .{ .input = "1E10", .expected = 1e10 },
        .{ .input = "1e+10", .expected = 1e10 },
        .{ .input = "2.5e10", .expected = 2.5e10 },
        .{ .input = "1e-10", .expected = 1e-10 },
        .{ .input = "1.5e-3", .expected = 1.5e-3 },
        .{ .input = "2.5E+20", .expected = 2.5e20 },
        .{ .input = "1e308", .expected = 1e308 },
        .{ .input = "1e-308", .expected = 1e-308 },
    };

    for (cases) |case| {
        var parsed = try parse.parse(case.input, allocator);
        defer parsed.deinit(allocator);

        const actual = switch (parsed) {
            .number_float => |f| f,
            .number_int => |i| @as(f64, @floatFromInt(i)),
            else => unreachable,
        };

        try testing.expectApproxEqAbs(case.expected, actual, 1e-10);
    }
}
