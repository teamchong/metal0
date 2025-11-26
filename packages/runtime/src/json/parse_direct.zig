/// Direct JSON parser - parses JSON directly to PyObject (no intermediate JsonValue)
/// This eliminates double allocations and conversions for maximum performance
const std = @import("std");
const runtime = @import("../runtime.zig");
const simd = @import("simd/dispatch.zig");
const JsonError = @import("errors.zig").JsonError;
const ParseResult = @import("errors.zig").ParseResult;

/// Use SIMD whitespace skipping for better performance
inline fn skipWhitespace(data: []const u8, pos: usize) usize {
    return simd.skipWhitespace(data, pos);
}

const primitives = @import("parse_direct/primitives.zig");
const number = @import("parse_direct/number.zig");
const string = @import("parse_direct/string.zig");
const array = @import("parse_direct/array.zig");
const object = @import("parse_direct/object.zig");

/// Main entry point: parse JSON string directly to PyObject
pub fn parse(data: []const u8, allocator: std.mem.Allocator) JsonError!*runtime.PyObject {
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
