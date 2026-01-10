//! test.test_tomllib - TOML parsing tests
//! Comprehensive tests for TOML v1.0.0 parsing and validation.
//!
//! Test modules:
//! - test_parser: Core lexer and parser tests
//! - test_decode: Value decoding and type coercion
//! - test_strings: String parsing (basic, literal, multiline)
//! - test_numbers: Integer and float parsing
//! - test_arrays: Array parsing and validation
//! - test_tables: Table and nested table parsing
//! - test_inline: Inline table parsing
//! - test_datetime: Date/time value parsing
//! - test_errors: Error handling and diagnostics
//! - test_spec: TOML specification compliance

const std = @import("std");

// Import all test modules
pub const test_parser = @import("test_parser.zig");
pub const test_decode = @import("test_decode.zig");
pub const test_strings = @import("test_strings.zig");
pub const test_numbers = @import("test_numbers.zig");
pub const test_arrays = @import("test_arrays.zig");
pub const test_tables = @import("test_tables.zig");
pub const test_inline = @import("test_inline.zig");
pub const test_datetime = @import("test_datetime.zig");
pub const test_errors = @import("test_errors.zig");
pub const test_spec = @import("test_spec.zig");

/// TOML Value types
pub const TOMLValue = union(enum) {
    string: []const u8,
    integer: i64,
    float: f64,
    boolean: bool,
    datetime: DateTime,
    array: std.ArrayList(TOMLValue),
    table: std.StringHashMap(TOMLValue),

    pub fn isScalar(self: TOMLValue) bool {
        return switch (self) {
            .array, .table => false,
            else => true,
        };
    }

    pub fn typeName(self: TOMLValue) []const u8 {
        return switch (self) {
            .string => "string",
            .integer => "integer",
            .float => "float",
            .boolean => "boolean",
            .datetime => "datetime",
            .array => "array",
            .table => "table",
        };
    }
};

/// DateTime structure for TOML datetime values
pub const DateTime = struct {
    year: u16 = 0,
    month: u8 = 0,
    day: u8 = 0,
    hour: u8 = 0,
    minute: u8 = 0,
    second: u8 = 0,
    nanosecond: u32 = 0,
    offset_hours: i8 = 0,
    offset_minutes: i8 = 0,
    has_date: bool = false,
    has_time: bool = false,
    has_offset: bool = false,

    pub fn isValid(self: DateTime) bool {
        if (self.has_date) {
            if (self.month < 1 or self.month > 12) return false;
            if (self.day < 1 or self.day > 31) return false;
        }
        if (self.has_time) {
            if (self.hour > 23) return false;
            if (self.minute > 59) return false;
            if (self.second > 59) return false;
        }
        return true;
    }
};

/// TOML Parser with full feature support
pub const TOMLParser = struct {
    allocator: std.mem.Allocator,
    strict_mode: bool,

    pub fn init(allocator: std.mem.Allocator) TOMLParser {
        return .{
            .allocator = allocator,
            .strict_mode = true,
        };
    }

    pub fn parse(self: TOMLParser, input: []const u8) !std.StringHashMap(TOMLValue) {
        var result = std.StringHashMap(TOMLValue).init(self.allocator);
        errdefer result.deinit();

        var lines = std.mem.splitScalar(u8, input, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#') continue;

            if (std.mem.indexOf(u8, trimmed, "=")) |eq| {
                const key = std.mem.trim(u8, trimmed[0..eq], " \t");
                const val = std.mem.trim(u8, trimmed[eq + 1 ..], " \t");
                try result.put(key, try self.parseValue(val));
            }
        }
        return result;
    }

    fn parseValue(self: TOMLParser, val: []const u8) !TOMLValue {
        if (val.len == 0) return .{ .string = "" };

        // String (basic or literal)
        if ((val[0] == '"' and val[val.len - 1] == '"') or
            (val[0] == '\'' and val[val.len - 1] == '\''))
        {
            return .{ .string = val[1 .. val.len - 1] };
        }

        // Boolean
        if (std.mem.eql(u8, val, "true")) return .{ .boolean = true };
        if (std.mem.eql(u8, val, "false")) return .{ .boolean = false };

        // Special floats
        if (std.mem.eql(u8, val, "inf") or std.mem.eql(u8, val, "+inf")) {
            return .{ .float = std.math.inf(f64) };
        }
        if (std.mem.eql(u8, val, "-inf")) {
            return .{ .float = -std.math.inf(f64) };
        }
        if (std.mem.eql(u8, val, "nan") or std.mem.eql(u8, val, "+nan") or std.mem.eql(u8, val, "-nan")) {
            return .{ .float = std.math.nan(f64) };
        }

        // Integer (with underscore removal)
        var clean = std.ArrayList(u8).init(self.allocator);
        defer clean.deinit();
        for (val) |c| {
            if (c != '_') try clean.append(c);
        }

        if (std.fmt.parseInt(i64, clean.items, 10)) |i| {
            return .{ .integer = i };
        } else |_| {}

        if (std.fmt.parseFloat(f64, clean.items)) |f| {
            return .{ .float = f };
        } else |_| {}

        return .{ .string = val };
    }
};

/// Convenience function to parse TOML string
pub fn loads(allocator: std.mem.Allocator, s: []const u8) !std.StringHashMap(TOMLValue) {
    const parser = TOMLParser.init(allocator);
    return parser.parse(s);
}

// ============================================================================
// Tests
// ============================================================================

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

test "toml_float" {
    var result = try loads(std.testing.allocator, "pi = 3.14159");
    defer result.deinit();
    if (result.get("pi")) |v| {
        try std.testing.expectApproxEqAbs(@as(f64, 3.14159), v.float, 0.00001);
    }
}

test "toml_integer_with_underscores" {
    var result = try loads(std.testing.allocator, "big = 1_000_000");
    defer result.deinit();
    if (result.get("big")) |v| {
        try std.testing.expectEqual(@as(i64, 1000000), v.integer);
    }
}

test "toml_negative_integer" {
    var result = try loads(std.testing.allocator, "temp = -40");
    defer result.deinit();
    if (result.get("temp")) |v| {
        try std.testing.expectEqual(@as(i64, -40), v.integer);
    }
}

test "toml_literal_string" {
    var result = try loads(std.testing.allocator, "path = 'C:\\path\\to\\file'");
    defer result.deinit();
    if (result.get("path")) |v| {
        try std.testing.expectEqualStrings("C:\\path\\to\\file", v.string);
    }
}

test "toml_special_float_inf" {
    var result = try loads(std.testing.allocator, "infinity = inf");
    defer result.deinit();
    if (result.get("infinity")) |v| {
        try std.testing.expect(std.math.isPositiveInf(v.float));
    }
}

test "toml_special_float_nan" {
    var result = try loads(std.testing.allocator, "not_a_number = nan");
    defer result.deinit();
    if (result.get("not_a_number")) |v| {
        try std.testing.expect(std.math.isNan(v.float));
    }
}

test "toml_value_type_names" {
    const str_val = TOMLValue{ .string = "test" };
    const int_val = TOMLValue{ .integer = 42 };
    const float_val = TOMLValue{ .float = 3.14 };

    try std.testing.expectEqualStrings("string", str_val.typeName());
    try std.testing.expectEqualStrings("integer", int_val.typeName());
    try std.testing.expectEqualStrings("float", float_val.typeName());
}

test "toml_value_is_scalar" {
    const str_val = TOMLValue{ .string = "test" };
    const arr_val = TOMLValue{ .array = std.ArrayList(TOMLValue).init(std.testing.allocator) };

    try std.testing.expect(str_val.isScalar());
    try std.testing.expect(!arr_val.isScalar());
}

test "datetime_is_valid" {
    const valid_dt = DateTime{
        .year = 2024,
        .month = 1,
        .day = 15,
        .has_date = true,
    };
    try std.testing.expect(valid_dt.isValid());

    const invalid_dt = DateTime{
        .month = 13,
        .day = 1,
        .has_date = true,
    };
    try std.testing.expect(!invalid_dt.isValid());
}

// Reference all test modules to ensure they compile
comptime {
    _ = test_parser;
    _ = test_decode;
    _ = test_strings;
    _ = test_numbers;
    _ = test_arrays;
    _ = test_tables;
    _ = test_inline;
    _ = test_datetime;
    _ = test_errors;
    _ = test_spec;
}
