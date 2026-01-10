//! zipfile._path.glob - Glob matching for zipfile paths
//! Reference: cpython/Lib/zipfile/_path/glob.py (internal)
//!
//! Glob pattern matching utilities for zip file contents.

const std = @import("std");

/// Glob pattern parts
pub const PatternPart = union(enum) {
    literal: []const u8,
    wildcard, // *
    recursive, // **
    question, // ?
    charset: []const u8, // [abc]
    negated_charset: []const u8, // [!abc]
};

/// Parsed glob pattern
pub const Pattern = struct {
    const Self = @This();

    parts: std.ArrayList(PatternPart),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .parts = std.ArrayList(PatternPart).init(allocator) };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.parts.deinit(allocator);
    }
};

/// Parse a glob pattern
pub fn parse(allocator: std.mem.Allocator, pattern: []const u8) !Pattern {
    var result = Pattern.init(allocator);
    errdefer result.deinit(allocator);

    var i: usize = 0;
    var literal_start: usize = 0;

    while (i < pattern.len) {
        const c = pattern[i];

        switch (c) {
            '*' => {
                // Save preceding literal
                if (i > literal_start) {
                    try result.parts.append(allocator, .{ .literal = pattern[literal_start..i] });
                }

                // Check for **
                if (i + 1 < pattern.len and pattern[i + 1] == '*') {
                    try result.parts.append(allocator, .recursive);
                    i += 2;
                } else {
                    try result.parts.append(allocator, .wildcard);
                    i += 1;
                }
                literal_start = i;
            },
            '?' => {
                if (i > literal_start) {
                    try result.parts.append(allocator, .{ .literal = pattern[literal_start..i] });
                }
                try result.parts.append(allocator, .question);
                i += 1;
                literal_start = i;
            },
            '[' => {
                if (i > literal_start) {
                    try result.parts.append(allocator, .{ .literal = pattern[literal_start..i] });
                }

                // Find closing bracket
                const start = i + 1;
                const negated = start < pattern.len and pattern[start] == '!';
                const char_start = if (negated) start + 1 else start;

                var j = char_start;
                while (j < pattern.len and pattern[j] != ']') : (j += 1) {}

                if (j < pattern.len) {
                    const chars = pattern[char_start..j];
                    if (negated) {
                        try result.parts.append(allocator, .{ .negated_charset = chars });
                    } else {
                        try result.parts.append(allocator, .{ .charset = chars });
                    }
                    i = j + 1;
                } else {
                    // Unterminated bracket, treat as literal
                    i += 1;
                }
                literal_start = i;
            },
            else => i += 1,
        }
    }

    // Add trailing literal
    if (i > literal_start) {
        try result.parts.append(allocator, .{ .literal = pattern[literal_start..i] });
    }

    return result;
}

/// Match a path against a parsed pattern
pub fn matchPath(pattern: *const Pattern, path: []const u8) bool {
    return matchParts(pattern.parts.items, path, 0);
}

fn matchParts(parts: []const PatternPart, path: []const u8, path_pos: usize) bool {
    if (parts.len == 0) {
        return path_pos >= path.len;
    }

    const part = parts[0];
    const remaining_parts = parts[1..];

    switch (part) {
        .literal => |lit| {
            if (path_pos + lit.len > path.len) return false;
            if (!std.mem.eql(u8, path[path_pos .. path_pos + lit.len], lit)) return false;
            return matchParts(remaining_parts, path, path_pos + lit.len);
        },
        .wildcard => {
            // Match zero or more characters (not including /)
            var i = path_pos;
            while (i <= path.len) : (i += 1) {
                if (i > path_pos and i <= path.len and path[i - 1] == '/') break;
                if (matchParts(remaining_parts, path, i)) return true;
            }
            return false;
        },
        .recursive => {
            // Match zero or more path components
            var i = path_pos;
            while (i <= path.len) : (i += 1) {
                if (matchParts(remaining_parts, path, i)) return true;
            }
            return false;
        },
        .question => {
            if (path_pos >= path.len) return false;
            if (path[path_pos] == '/') return false;
            return matchParts(remaining_parts, path, path_pos + 1);
        },
        .charset => |chars| {
            if (path_pos >= path.len) return false;
            const c = path[path_pos];
            if (std.mem.indexOf(u8, chars, &[_]u8{c}) == null) return false;
            return matchParts(remaining_parts, path, path_pos + 1);
        },
        .negated_charset => |chars| {
            if (path_pos >= path.len) return false;
            const c = path[path_pos];
            if (std.mem.indexOf(u8, chars, &[_]u8{c}) != null) return false;
            return matchParts(remaining_parts, path, path_pos + 1);
        },
    }
}

/// Simple glob match (without full parsing)
pub fn match(pattern_str: []const u8, path: []const u8) bool {
    var pi: usize = 0;
    var si: usize = 0;

    var star_pi: ?usize = null;
    var star_si: ?usize = null;

    while (si < path.len) {
        if (pi < pattern_str.len and (pattern_str[pi] == path[si] or pattern_str[pi] == '?')) {
            pi += 1;
            si += 1;
        } else if (pi < pattern_str.len and pattern_str[pi] == '*') {
            star_pi = pi;
            star_si = si;
            pi += 1;
        } else if (star_pi != null) {
            pi = star_pi.? + 1;
            star_si.? += 1;
            si = star_si.?;
        } else {
            return false;
        }
    }

    while (pi < pattern_str.len and pattern_str[pi] == '*') {
        pi += 1;
    }

    return pi >= pattern_str.len;
}

// ============================================================================
// Tests
// ============================================================================

test "match simple" {
    try std.testing.expect(match("*.txt", "file.txt"));
    try std.testing.expect(match("file.*", "file.txt"));
    try std.testing.expect(match("*", "anything"));
    try std.testing.expect(!match("*.txt", "file.py"));
}

test "match question" {
    try std.testing.expect(match("file?.txt", "file1.txt"));
    try std.testing.expect(!match("file?.txt", "file12.txt"));
}

test "parse pattern" {
    const allocator = std.testing.allocator;
    var pattern = try parse(allocator, "*.txt");
    defer pattern.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), pattern.parts.items.len);
    try std.testing.expectEqual(PatternPart.wildcard, pattern.parts.items[0]);
}

test "matchPath" {
    const allocator = std.testing.allocator;
    var pattern = try parse(allocator, "dir/*.txt");
    defer pattern.deinit(allocator);

    try std.testing.expect(matchPath(&pattern, "dir/file.txt"));
    try std.testing.expect(!matchPath(&pattern, "other/file.txt"));
}
