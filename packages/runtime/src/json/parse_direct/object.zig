/// Parse JSON objects directly to PyDict (zero extra allocations)
const std = @import("std");
const runtime = @import("runtime.zig");
const skipWhitespace = @import("../value.zig").skipWhitespace;
const JsonError = @import("../errors.zig").JsonError;
const ParseResult = @import("../errors.zig").ParseResult;
const parseStringRaw = @import("string_raw.zig").parseStringRaw;

// Forward declaration - will be set by parse_direct.zig
var parseValueFn: ?*const fn ([]const u8, usize, std.mem.Allocator) JsonError!ParseResult(*runtime.PyObject) = null;

pub fn setParseValueFn(func: *const fn ([]const u8, usize, std.mem.Allocator) JsonError!ParseResult(*runtime.PyObject)) void {
    parseValueFn = func;
}

/// Parse JSON object directly to PyDict: { "key": value, "key2": value2, ... }
pub fn parseObject(data: []const u8, pos: usize, allocator: std.mem.Allocator) JsonError!ParseResult(*runtime.PyObject) {
    if (pos >= data.len or data[pos] != '{') return JsonError.UnexpectedToken;

    // Create PyDict
    const dict = try runtime.PyDict.create(allocator);
    errdefer runtime.decref(dict, allocator);

    var i = skipWhitespace(data, pos + 1);

    // Check for empty object
    if (i < data.len and data[i] == '}') {
        return ParseResult(*runtime.PyObject).init(
            dict,
            i + 1 - pos,
        );
    }

    // Parse key-value pairs
    while (true) {
        // Parse key (must be string) - parse as raw string, no PyObject wrapper!
        if (i >= data.len or data[i] != '"') return JsonError.UnexpectedToken;

        const key_result = try parseStringRaw(data, i, allocator);
        const owned_key = key_result.value; // Already allocated, we own it
        errdefer allocator.free(owned_key); // Free on error
        i += key_result.consumed;

        // Skip whitespace and expect colon
        i = skipWhitespace(data, i);
        if (i >= data.len or data[i] != ':') return JsonError.UnexpectedToken;
        i = skipWhitespace(data, i + 1);

        // Parse value
        const parse_fn = parseValueFn orelse return JsonError.UnexpectedToken;
        const value_result = try parse_fn(data, i, allocator);
        i += value_result.consumed;

        // PyDict.setOwned takes ownership of BOTH key and value (zero-copy!)
        try runtime.PyDict.setOwned(dict, owned_key, value_result.value);

        // Skip whitespace
        i = skipWhitespace(data, i);
        if (i >= data.len) return JsonError.UnexpectedEndOfInput;

        const c = data[i];
        if (c == '}') {
            // End of object
            return ParseResult(*runtime.PyObject).init(
                dict,
                i + 1 - pos,
            );
        } else if (c == ',') {
            // More pairs
            i = skipWhitespace(data, i + 1);

            // Check for trailing comma
            if (i < data.len and data[i] == '}') {
                return JsonError.TrailingComma;
            }
        } else {
            return JsonError.UnexpectedToken;
        }
    }
}
