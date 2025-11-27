//! Lazy JSON Parser - strings remain as references until accessed
//!
//! Usage:
//!   var result = try parseLazy(allocator, json_source);
//!   defer result.deinit(allocator);
//!
//!   // Only accessed strings get copied
//!   const name = try result.object.get("name").?.string.get();
//!
//! Benefits:
//! - Parse 10x faster when only accessing subset of values
//! - Memory: only allocate what's used
//! - Compare keys without allocation via .eql()

const std = @import("std");
const LazyValue = @import("lazy.zig").LazyValue;
const LazyString = @import("lazy.zig").LazyString;
const simd = @import("simd/dispatch.zig");

pub const ParseError = error{
    UnexpectedToken,
    InvalidNumber,
    InvalidString,
    InvalidEscape,
    InvalidUnicode,
    UnterminatedString,
    MaxDepthExceeded,
    OutOfMemory,
    TrailingData,
    TrailingComma,
    DuplicateKey,
    UnexpectedEndOfInput,
    NumberOutOfRange,
};

const ParseResult = struct {
    value: LazyValue,
    consumed: usize,

    fn init(val: LazyValue, bytes: usize) ParseResult {
        return .{ .value = val, .consumed = bytes };
    }
};

/// Parse JSON into lazy values - strings remain as references
pub fn parseLazy(allocator: std.mem.Allocator, input: []const u8) ParseError!LazyValue {
    const i = simd.skipWhitespace(input, 0);
    if (i >= input.len) return ParseError.UnexpectedEndOfInput;

    const result = try parseValue(input, i, allocator);

    const final_pos = simd.skipWhitespace(input, i + result.consumed);
    if (final_pos < input.len) {
        var val = result.value;
        val.deinit(allocator);
        return ParseError.TrailingData;
    }

    return result.value;
}

fn parseValue(data: []const u8, pos: usize, allocator: std.mem.Allocator) ParseError!ParseResult {
    const i = simd.skipWhitespace(data, pos);
    if (i >= data.len) return ParseError.UnexpectedEndOfInput;

    return switch (data[i]) {
        '{' => try parseObject(data, i, allocator),
        '[' => try parseArray(data, i, allocator),
        '"' => try parseString(data, i, allocator),
        '-', '0'...'9' => try parseNumber(data, i),
        'n', 't', 'f' => try parsePrimitive(data, i),
        else => ParseError.UnexpectedToken,
    };
}

fn parsePrimitive(data: []const u8, pos: usize) ParseError!ParseResult {
    if (pos >= data.len) return ParseError.UnexpectedEndOfInput;

    return switch (data[pos]) {
        'n' => {
            if (pos + 4 > data.len) return ParseError.UnexpectedEndOfInput;
            if (!std.mem.eql(u8, data[pos .. pos + 4], "null")) return ParseError.UnexpectedToken;
            return ParseResult.init(.null_value, 4);
        },
        't' => {
            if (pos + 4 > data.len) return ParseError.UnexpectedEndOfInput;
            if (!std.mem.eql(u8, data[pos .. pos + 4], "true")) return ParseError.UnexpectedToken;
            return ParseResult.init(.{ .bool_value = true }, 4);
        },
        'f' => {
            if (pos + 5 > data.len) return ParseError.UnexpectedEndOfInput;
            if (!std.mem.eql(u8, data[pos .. pos + 5], "false")) return ParseError.UnexpectedToken;
            return ParseResult.init(.{ .bool_value = false }, 5);
        },
        else => ParseError.UnexpectedToken,
    };
}

fn parseNumber(data: []const u8, pos: usize) ParseError!ParseResult {
    var i = pos;
    var has_decimal = false;
    var has_exponent = false;

    // Optional minus
    if (i < data.len and data[i] == '-') i += 1;
    if (i >= data.len) return ParseError.InvalidNumber;

    // Integer part
    if (data[i] == '0') {
        i += 1;
    } else if (data[i] >= '1' and data[i] <= '9') {
        while (i < data.len and data[i] >= '0' and data[i] <= '9') : (i += 1) {}
    } else {
        return ParseError.InvalidNumber;
    }

    // Decimal part
    if (i < data.len and data[i] == '.') {
        has_decimal = true;
        i += 1;
        const dec_start = i;
        while (i < data.len and data[i] >= '0' and data[i] <= '9') : (i += 1) {}
        if (i == dec_start) return ParseError.InvalidNumber;
    }

    // Exponent part
    if (i < data.len and (data[i] == 'e' or data[i] == 'E')) {
        has_exponent = true;
        i += 1;
        if (i < data.len and (data[i] == '+' or data[i] == '-')) i += 1;
        const exp_start = i;
        while (i < data.len and data[i] >= '0' and data[i] <= '9') : (i += 1) {}
        if (i == exp_start) return ParseError.InvalidNumber;
    }

    const num_str = data[pos..i];

    if (!has_decimal and !has_exponent) {
        const value = std.fmt.parseInt(i64, num_str, 10) catch return ParseError.NumberOutOfRange;
        return ParseResult.init(.{ .number_int = value }, i - pos);
    }

    const value = std.fmt.parseFloat(f64, num_str) catch return ParseError.InvalidNumber;
    return ParseResult.init(.{ .number_float = value }, i - pos);
}

/// Parse string - LAZY: stores reference, doesn't copy
fn parseString(data: []const u8, pos: usize, allocator: std.mem.Allocator) ParseError!ParseResult {
    if (pos >= data.len or data[pos] != '"') return ParseError.UnexpectedToken;

    const start = pos + 1;

    if (simd.findClosingQuoteAndEscapes(data[start..])) |result| {
        const end = start + result.quote_pos;

        // Create lazy string - NO COPY
        const lazy = LazyString.init(allocator, data, start, end, result.has_escapes);

        return ParseResult.init(
            .{ .string = lazy },
            end + 1 - pos,
        );
    }

    return ParseError.UnterminatedString;
}

fn parseArray(data: []const u8, pos: usize, allocator: std.mem.Allocator) ParseError!ParseResult {
    if (pos >= data.len or data[pos] != '[') return ParseError.UnexpectedToken;

    var arr = std.ArrayList(LazyValue){};
    errdefer {
        for (arr.items) |*item| item.deinit(allocator);
        arr.deinit(allocator);
    }

    var i = pos + 1;
    var first = true;

    while (true) {
        i = simd.skipWhitespace(data, i);
        if (i >= data.len) return ParseError.UnexpectedEndOfInput;

        if (data[i] == ']') {
            return ParseResult.init(.{ .array = arr }, i + 1 - pos);
        }

        if (!first) {
            if (data[i] != ',') return ParseError.UnexpectedToken;
            i += 1;
            i = simd.skipWhitespace(data, i);
            if (i >= data.len) return ParseError.UnexpectedEndOfInput;
            if (data[i] == ']') return ParseError.TrailingComma;
        }
        first = false;

        const result = try parseValue(data, i, allocator);
        arr.append(allocator, result.value) catch return ParseError.OutOfMemory;
        i += result.consumed;
    }
}

fn parseObject(data: []const u8, pos: usize, allocator: std.mem.Allocator) ParseError!ParseResult {
    if (pos >= data.len or data[pos] != '{') return ParseError.UnexpectedToken;

    var obj = std.StringHashMap(LazyValue).init(allocator);
    errdefer {
        var it = obj.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        obj.deinit();
    }

    var i = pos + 1;
    var first = true;

    while (true) {
        i = simd.skipWhitespace(data, i);
        if (i >= data.len) return ParseError.UnexpectedEndOfInput;

        if (data[i] == '}') {
            return ParseResult.init(.{ .object = obj }, i + 1 - pos);
        }

        if (!first) {
            if (data[i] != ',') return ParseError.UnexpectedToken;
            i += 1;
            i = simd.skipWhitespace(data, i);
            if (i >= data.len) return ParseError.UnexpectedEndOfInput;
            if (data[i] == '}') return ParseError.TrailingComma;
        }
        first = false;

        // Parse key (must be string)
        if (data[i] != '"') return ParseError.UnexpectedToken;
        const key_result = try parseString(data, i, allocator);
        i += key_result.consumed;

        // Keys need to be materialized for HashMap (or use lazy key comparison)
        // For now, materialize keys but keep values lazy
        var lazy_key = key_result.value.string;
        const key = lazy_key.get() catch return ParseError.OutOfMemory;
        const key_copy = allocator.dupe(u8, key) catch return ParseError.OutOfMemory;
        lazy_key.deinit();

        // Colon
        i = simd.skipWhitespace(data, i);
        if (i >= data.len or data[i] != ':') return ParseError.UnexpectedToken;
        i += 1;

        // Parse value (lazy)
        const val_result = try parseValue(data, i, allocator);
        i += val_result.consumed;

        // Check for duplicate keys
        if (obj.contains(key_copy)) {
            allocator.free(key_copy);
            var val = val_result.value;
            val.deinit(allocator);
            return ParseError.DuplicateKey;
        }

        obj.put(key_copy, val_result.value) catch return ParseError.OutOfMemory;
    }
}

test "parseLazy basic types" {
    const allocator = std.testing.allocator;

    // Null
    var null_val = try parseLazy(allocator, "null");
    defer null_val.deinit(allocator);
    try std.testing.expect(null_val == .null_value);

    // Bool
    var true_val = try parseLazy(allocator, "true");
    defer true_val.deinit(allocator);
    try std.testing.expectEqual(true, true_val.bool_value);

    // Number
    var num_val = try parseLazy(allocator, "42");
    defer num_val.deinit(allocator);
    try std.testing.expectEqual(@as(i64, 42), num_val.number_int);
}

test "parseLazy string stays lazy" {
    const allocator = std.testing.allocator;
    const json = "\"hello world\"";

    var result = try parseLazy(allocator, json);
    defer result.deinit(allocator);

    // String should not be materialized yet
    try std.testing.expect(result.string.materialized == null);

    // Access materializes
    const str = try result.string.get();
    try std.testing.expectEqualStrings("hello world", str);
    try std.testing.expect(result.string.materialized != null);
}

test "parseLazy object" {
    const allocator = std.testing.allocator;
    const json =
        \\{"name": "Alice", "age": 30, "city": "NYC"}
    ;

    var result = try parseLazy(allocator, json);
    defer result.deinit(allocator);

    // Only access "name" - other strings stay lazy
    if (result.object.get("name")) |*name_val| {
        const name = try name_val.string.get();
        try std.testing.expectEqualStrings("Alice", name);
    }

    // "city" should still be lazy (not accessed)
    if (result.object.get("city")) |city_val| {
        try std.testing.expect(city_val.string.materialized == null);
    }
}
