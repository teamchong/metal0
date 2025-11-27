/// Direct JSON parser - parses JSON directly to PyObject (no intermediate JsonValue)
/// This eliminates double allocations and conversions for maximum performance
/// Supports lazy mode: strings borrow from source (zero-copy) when no escapes
const std = @import("std");
const runtime = @import("../runtime.zig");
const simd = @import("json_simd");
const JsonError = @import("errors.zig").JsonError;
const ParseResult = @import("errors.zig").ParseResult;

/// Thread-local source reference for lazy parsing
/// When set, strings without escapes will borrow from this source
threadlocal var lazy_source: ?*runtime.PyObject = null;

/// Use SIMD whitespace skipping for better performance
inline fn skipWhitespace(data: []const u8, pos: usize) usize {
    return simd.skipWhitespace(data, pos);
}

const primitives = @import("parse_direct/primitives.zig");
const number = @import("parse_direct/number.zig");
const string = @import("parse_direct/string.zig");
const array = @import("parse_direct/array.zig");
const object = @import("parse_direct/object.zig");

/// Get current lazy source (for string.zig to use)
pub fn getLazySource() ?*runtime.PyObject {
    return lazy_source;
}

/// Main entry point: parse JSON string directly to PyObject (eager - copies all strings)
pub fn parse(data: []const u8, allocator: std.mem.Allocator) JsonError!*runtime.PyObject {
    return parseWithSource(data, allocator, null);
}

/// Parse JSON with optional source reference for lazy strings
/// If source is non-null, strings without escapes will borrow from it (zero-copy)
pub fn parseWithSource(data: []const u8, allocator: std.mem.Allocator, source: ?*runtime.PyObject) JsonError!*runtime.PyObject {
    // Set up lazy source for string parsing
    lazy_source = source;
    defer lazy_source = null;
    // Set up circular dependencies
    array.setParseValueFn(&parseValue);
    object.setParseValueFn(&parseValue);

    const i = skipWhitespace(data, 0);
    if (i >= data.len) return JsonError.UnexpectedEndOfInput;

    const result = try parseValue(data, i, allocator);

    // Check for trailing content
    const final_pos = skipWhitespace(data, i + result.consumed);
    if (final_pos < data.len) {
        // Clean up on error
        runtime.decref(result.value, allocator);
        return JsonError.UnexpectedToken;
    }

    return result.value;
}

/// Parse any JSON value based on first non-whitespace character
pub fn parseValue(data: []const u8, pos: usize, allocator: std.mem.Allocator) JsonError!ParseResult(*runtime.PyObject) {
    const i = skipWhitespace(data, pos);
    if (i >= data.len) return JsonError.UnexpectedEndOfInput;

    const c = data[i];
    return switch (c) {
        '{' => try object.parseObject(data, i, allocator),
        '[' => try array.parseArray(data, i, allocator),
        '"' => try string.parseString(data, i, allocator),
        '-', '0'...'9' => try number.parseNumber(data, i, allocator),
        'n', 't', 'f' => try primitives.parsePrimitive(data, i, allocator),
        else => JsonError.UnexpectedToken,
    };
}
