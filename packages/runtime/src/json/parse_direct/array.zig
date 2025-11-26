/// Parse JSON arrays directly to PyList (zero extra allocations)
const std = @import("std");
const runtime = @import("runtime.zig");
const skipWhitespace = @import("../value.zig").skipWhitespace;
const JsonError = @import("../errors.zig").JsonError;
const ParseResult = @import("../errors.zig").ParseResult;

// Forward declaration - will be set by parse_direct.zig
var parseValueFn: ?*const fn ([]const u8, usize, std.mem.Allocator) JsonError!ParseResult(*runtime.PyObject) = null;

pub fn setParseValueFn(func: *const fn ([]const u8, usize, std.mem.Allocator) JsonError!ParseResult(*runtime.PyObject)) void {
    parseValueFn = func;
}

/// Parse JSON array directly to PyList: [ value, value, ... ]
pub fn parseArray(data: []const u8, pos: usize, allocator: std.mem.Allocator) JsonError!ParseResult(*runtime.PyObject) {
    if (pos >= data.len or data[pos] != '[') return JsonError.UnexpectedToken;

    // Create PyList
    const list = try runtime.PyList.create(allocator);
    errdefer runtime.decref(list, allocator);

    const list_data: *runtime.PyList = @ptrCast(@alignCast(list.data));

    var i = skipWhitespace(data, pos + 1);

    // Check for empty array
    if (i < data.len and data[i] == ']') {
        return ParseResult(*runtime.PyObject).init(
            list,
            i + 1 - pos,
        );
    }

    // Parse elements
    while (true) {
        // Parse value
        const parse_fn = parseValueFn orelse return JsonError.UnexpectedToken;
        const value_result = try parse_fn(data, i, allocator);
        try list_data.items.append(allocator, value_result.value);
        i += value_result.consumed;

        // Skip whitespace
        i = skipWhitespace(data, i);
        if (i >= data.len) return JsonError.UnexpectedEndOfInput;

        const c = data[i];
        if (c == ']') {
            // End of array
            return ParseResult(*runtime.PyObject).init(
                list,
                i + 1 - pos,
            );
        } else if (c == ',') {
            // More elements
            i = skipWhitespace(data, i + 1);

            // Check for trailing comma
            if (i < data.len and data[i] == ']') {
                return JsonError.TrailingComma;
            }
        } else {
            return JsonError.UnexpectedToken;
        }
    }
}
