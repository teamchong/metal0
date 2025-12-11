//! CPython source: Lib/configparser.py
//!
//! Section management operations for ConfigParser.

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

/// Check if a section exists
pub fn hasSection(parser: anytype, section: []const u8) bool {
    return parser.sections.contains(section);
}

/// Add a new section
pub fn addSection(parser: anytype, section: []const u8) !void {
    if (parser.sections.contains(section)) {
        return error.DuplicateSection;
    }
    const section_dup = try parser.allocator.dupe(u8, section);
    try parser.sections.put(section_dup, hashmap_helper.StringHashMap([]const u8).init(parser.allocator));
}

/// Remove a section
pub fn removeSection(parser: anytype, section: []const u8) bool {
    if (parser.sections.fetchSwapRemove(section)) |kv| {
        var map = kv.value;
        map.deinit();
        return true;
    }
    return false;
}

/// Get all section names
pub fn getSections(parser: anytype) ![][]const u8 {
    var result = std.ArrayList([]const u8).init(parser.allocator);
    for (parser.sections.keys()) |key| {
        try result.append(key);
    }
    return result.toOwnedSlice();
}

/// Clear all sections and options
pub fn clear(parser: anytype) void {
    var iter = parser.sections.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.deinit();
    }
    parser.sections.clearAndFree();
    parser.defaults.clearAndFree();
}
