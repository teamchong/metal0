/// Python _string module - Low-level string formatting helpers
/// This module implements formatter_parser and formatter_field_name_split
/// as used by string.Formatter in CPython.
///
/// Ported from CPython's Objects/stringlib/unicode_format.h
const std = @import("std");

/// Result tuple from formatter_parser:
/// (literal, field_name, format_spec, conversion)
/// where field_name, format_spec, conversion can be null
/// Using a proper Zig tuple type so it matches comptime list element inference
pub const FormatterResult = struct { []const u8, ?[]const u8, ?[]const u8, ?[]const u8 };

/// Iterator for parsing Python format strings
pub const FormatterIterator = struct {
    str: []const u8,
    pos: usize,

    pub fn init(format_str: []const u8) FormatterIterator {
        return .{
            .str = format_str,
            .pos = 0,
        };
    }

    /// Returns the next tuple (literal, field_name, format_spec, conversion)
    /// Returns null when iteration is complete
    pub fn next(self: *FormatterIterator) ?FormatterResult {
        if (self.pos >= self.str.len) {
            return null;
        }

        const start = self.pos;
        var literal_end = start;
        var markup_follows = false;
        var c: u8 = 0;

        // Read literal text until we hit { or }
        while (self.pos < self.str.len) {
            c = self.str[self.pos];
            self.pos += 1;

            if (c == '{' or c == '}') {
                markup_follows = true;
                break;
            }
            literal_end = self.pos;
        }

        const at_end = self.pos >= self.str.len;

        // Handle escaped {{ or }}
        if (markup_follows and !at_end) {
            if (self.str[self.pos] == c) {
                // Escaped brace - include it in literal and skip the second one
                self.pos += 1;
                literal_end = self.pos;
                markup_follows = false;
            }
        }

        // If no markup follows, return just the literal
        if (!markup_follows or c == '}') {
            if (literal_end > start) {
                return .{ self.str[start..literal_end], null, null, null };
            }
            return null;
        }

        // Parse the field: {field_name!conversion:format_spec}
        const field_start = self.pos;
        var field_name_end = field_start;
        var format_spec_start: ?usize = null;
        var format_spec_end: ?usize = null;
        var conversion_char: ?u8 = null;
        var brace_depth: usize = 1;

        while (self.pos < self.str.len and brace_depth > 0) {
            const ch = self.str[self.pos];

            if (ch == '{') {
                brace_depth += 1;
                self.pos += 1;
            } else if (ch == '}') {
                brace_depth -= 1;
                if (brace_depth == 0) {
                    if (format_spec_start != null) {
                        format_spec_end = self.pos;
                    } else if (conversion_char == null) {
                        // Only set field_name_end if no conversion specifier already set it
                        field_name_end = self.pos;
                    }
                    self.pos += 1;
                    break;
                }
                self.pos += 1;
            } else if (ch == '!' and brace_depth == 1 and format_spec_start == null) {
                // Conversion specifier
                field_name_end = self.pos;
                self.pos += 1;
                if (self.pos < self.str.len) {
                    conversion_char = self.str[self.pos];
                    self.pos += 1;
                }
            } else if (ch == ':' and brace_depth == 1) {
                // Format spec follows
                if (format_spec_start == null) {
                    if (conversion_char == null) {
                        field_name_end = self.pos;
                    }
                    self.pos += 1;
                    format_spec_start = self.pos;
                } else {
                    self.pos += 1;
                }
            } else {
                self.pos += 1;
            }
        }

        // Build the result
        const literal = if (literal_end > start) self.str[start..literal_end] else "";

        const field_name = if (field_name_end > field_start)
            self.str[field_start..field_name_end]
        else
            "";

        const format_spec = if (format_spec_start) |fs|
            if (format_spec_end) |fe| self.str[fs..fe] else self.str[fs..fs]
        else
            "";

        const conversion: ?[]const u8 = if (conversion_char) |conv|
            switch (conv) {
                's' => @as([]const u8, "s"),
                'r' => @as([]const u8, "r"),
                'a' => @as([]const u8, "a"),
                else => null,
            }
        else
            null;

        // Return tuple matching Python's formatter_parser:
        // - literal: always a string
        // - field_name: string if we entered a format field (opened a brace), null for trailing literal
        // - format_spec: string if we entered a format field, null for trailing literal
        // - conversion: 's', 'r', 'a' if !X present, null otherwise
        // We entered a format field if brace_depth is 0 (closed) and we advanced past field_start
        const has_format_field = brace_depth == 0 and self.pos > field_start;
        return .{
            literal,
            if (has_format_field) field_name else null,
            if (has_format_field) format_spec else null,
            conversion,
        };
    }
};

/// Parse a format string and return all results as a slice
/// This is the main function called by the codegen as _string.formatter_parser
/// Only accepts string types - raises TypeError for non-strings (like Python)
pub fn formatterParser(allocator: std.mem.Allocator, format_str: anytype) ![]FormatterResult {
    const T = @TypeOf(format_str);
    const type_info = @typeInfo(T);

    // Only accept string types - reject int/float/etc. like Python does
    const str: []const u8 = switch (type_info) {
        .pointer => |ptr| blk: {
            if (ptr.child == u8 or @typeInfo(ptr.child) == .array) {
                break :blk format_str;
            }
            // Non-string pointer - raise error
            return error.TypeError;
        },
        .array => |arr| blk: {
            if (arr.child == u8) {
                break :blk &format_str;
            }
            return error.TypeError;
        },
        // Int, float, or other types should raise TypeError
        .int, .comptime_int, .float, .comptime_float => return error.TypeError,
        else => format_str,
    };
    return formatterParserImpl(allocator, str);
}

/// Internal implementation
fn formatterParserImpl(allocator: std.mem.Allocator, format_str: []const u8) ![]FormatterResult {
    var results = std.ArrayList(FormatterResult){};
    errdefer results.deinit(allocator);

    var iter = FormatterIterator.init(format_str);
    while (iter.next()) |result| {
        try results.append(allocator, result);
    }

    return results.toOwnedSlice(allocator);
}

/// Result from formatter_field_name_split: (first, rest_iterator)
/// Using tuple types so they can be converted to list via list()
pub const FieldAccessor = struct { bool, []const u8 };
pub const FieldNameSplitResult = struct { []const u8, []FieldAccessor };

/// Split a field name into its components
/// "obj.attr[key]" -> ("obj", [(true, "attr"), (false, "key")])
pub fn formatterFieldNameSplit(allocator: std.mem.Allocator, field_name_input: anytype) !FieldNameSplitResult {
    // Type validation - Python raises TypeError for non-string input
    const T = @TypeOf(field_name_input);
    const field_name: []const u8 = blk: {
        if (T == []const u8) break :blk field_name_input;
        if (T == []u8) break :blk field_name_input;
        // Check for string literal type (*const [N:0]u8)
        if (@typeInfo(T) == .pointer) {
            const ptr_info = @typeInfo(T).pointer;
            if (ptr_info.size == .one and @typeInfo(ptr_info.child) == .array) {
                const arr_info = @typeInfo(ptr_info.child).array;
                if (arr_info.child == u8) {
                    break :blk field_name_input[0..arr_info.len];
                }
            }
        }
        return error.TypeError; // Non-string input
    };

    var accessors = std.ArrayList(FieldAccessor){};
    errdefer accessors.deinit(allocator);

    if (field_name.len == 0) {
        return .{ "", try accessors.toOwnedSlice(allocator) };
    }

    // Find the first part (before any . or [)
    var first_end: usize = 0;
    while (first_end < field_name.len) {
        const c = field_name[first_end];
        if (c == '.' or c == '[') break;
        first_end += 1;
    }

    const first = field_name[0..first_end];
    var pos = first_end;

    // Parse the rest
    while (pos < field_name.len) {
        const c = field_name[pos];
        if (c == '.') {
            // Attribute access
            pos += 1;
            const attr_start = pos;
            while (pos < field_name.len and field_name[pos] != '.' and field_name[pos] != '[') {
                pos += 1;
            }
            try accessors.append(allocator, .{ true, field_name[attr_start..pos] });
        } else if (c == '[') {
            // Index access
            pos += 1;
            const key_start = pos;
            while (pos < field_name.len and field_name[pos] != ']') {
                pos += 1;
            }
            try accessors.append(allocator, .{ false, field_name[key_start..pos] });
            if (pos < field_name.len) pos += 1; // skip ]
        } else {
            pos += 1;
        }
    }

    return .{ first, try accessors.toOwnedSlice(allocator) };
}

test "formatter_parser basic" {
    const allocator = std.testing.allocator;

    const results = try formatterParser(allocator, "prefix {0} suffix");
    defer allocator.free(results);

    try std.testing.expectEqual(@as(usize, 2), results.len);
    // Tuple: (literal, field_name, format_spec, conversion)
    try std.testing.expectEqualStrings("prefix ", results[0][0]); // literal
    try std.testing.expectEqualStrings("0", results[0][1].?); // field_name
    try std.testing.expectEqualStrings(" suffix", results[1][0]); // literal
}

test "formatter_parser with conversion" {
    const allocator = std.testing.allocator;

    const results = try formatterParser(allocator, "{0!s}");
    defer allocator.free(results);

    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqualStrings("0", results[0][1].?); // field_name
    try std.testing.expectEqualStrings("s", results[0][3].?); // conversion
}

test "formatter_parser with format_spec" {
    const allocator = std.testing.allocator;

    const results = try formatterParser(allocator, "{0:^+10.3f}");
    defer allocator.free(results);

    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqualStrings("0", results[0][1].?); // field_name
    try std.testing.expectEqualStrings("^+10.3f", results[0][2].?); // format_spec
}
