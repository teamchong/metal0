//! CPython source: Lib/configparser.py
//!
//! Get/set operations for configuration values.

const std = @import("std");

/// Get a value from a section
pub fn get(parser: anytype, section: []const u8, option: []const u8) ![]const u8 {
    if (parser.sections.get(section)) |section_map| {
        if (section_map.get(option)) |value| {
            return value;
        }
    }

    // Check defaults
    if (parser.defaults.get(option)) |value| {
        return value;
    }

    return error.NoOption;
}

/// Get a value with a fallback
pub fn getWithFallback(parser: anytype, section: []const u8, option: []const u8, fallback: []const u8) []const u8 {
    return get(parser, section, option) catch fallback;
}

/// Get an integer value
pub fn getInt(parser: anytype, section: []const u8, option: []const u8) !i64 {
    const value = try get(parser, section, option);
    return std.fmt.parseInt(i64, value, 10);
}

/// Get a float value
pub fn getFloat(parser: anytype, section: []const u8, option: []const u8) !f64 {
    const value = try get(parser, section, option);
    return std.fmt.parseFloat(f64, value);
}

/// Get a boolean value
pub fn getBoolean(parser: anytype, section: []const u8, option: []const u8) !bool {
    const value = try get(parser, section, option);
    const lower = try toLower(parser, value);
    defer parser.allocator.free(lower);

    if (std.mem.eql(u8, lower, "true") or
        std.mem.eql(u8, lower, "yes") or
        std.mem.eql(u8, lower, "on") or
        std.mem.eql(u8, lower, "1"))
    {
        return true;
    }

    if (std.mem.eql(u8, lower, "false") or
        std.mem.eql(u8, lower, "no") or
        std.mem.eql(u8, lower, "off") or
        std.mem.eql(u8, lower, "0"))
    {
        return false;
    }

    return error.InvalidBoolean;
}

fn toLower(parser: anytype, s: []const u8) ![]u8 {
    const result = try parser.allocator.alloc(u8, s.len);
    for (s, 0..) |c, i| {
        result[i] = std.ascii.toLower(c);
    }
    return result;
}

/// Set a value in a section
pub fn set(parser: anytype, section: []const u8, option: []const u8, value: []const u8) !void {
    if (!parser.sections.contains(section)) {
        return error.NoSection;
    }

    const key_dup = try parser.allocator.dupe(u8, option);
    const value_dup = try parser.allocator.dupe(u8, value);

    if (parser.sections.getPtr(section)) |section_map| {
        try section_map.put(key_dup, value_dup);
    }
}

/// Check if an option exists in a section
pub fn hasOption(parser: anytype, section: []const u8, option: []const u8) bool {
    if (parser.sections.get(section)) |section_map| {
        return section_map.contains(option);
    }
    return parser.defaults.contains(option);
}

/// Get all options in a section
pub fn getOptions(parser: anytype, section: []const u8) ![][]const u8 {
    var result: std.ArrayList([]const u8) = .{};

    // Add defaults first
    for (parser.defaults.keys()) |key| {
        try result.append(parser.allocator, key);
    }

    // Add section-specific options
    if (parser.sections.get(section)) |section_map| {
        for (section_map.keys()) |key| {
            try result.append(parser.allocator, key);
        }
    } else {
        return error.NoSection;
    }

    return result.toOwnedSlice(parser.allocator);
}

/// Get all items in a section
pub fn items(parser: anytype, section: []const u8) ![]struct { key: []const u8, value: []const u8 } {
    var result: std.ArrayList(struct { key: []const u8, value: []const u8 }) = .{};

    if (parser.sections.get(section)) |section_map| {
        var iter = section_map.iterator();
        while (iter.next()) |entry| {
            try result.append(parser.allocator, .{ .key = entry.key_ptr.*, .value = entry.value_ptr.* });
        }
    } else {
        return error.NoSection;
    }

    return result.toOwnedSlice(parser.allocator);
}

/// Remove an option from a section
pub fn removeOption(parser: anytype, section: []const u8, option: []const u8) bool {
    if (parser.sections.getPtr(section)) |section_map| {
        return section_map.remove(option);
    }
    return false;
}
