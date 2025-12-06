//! Python 'fnmatch' module - Unix filename pattern matching
//!
//! Provides shell-style wildcards for filename matching:
//!   *       matches everything
//!   ?       matches any single character
//!   [seq]   matches any character in seq
//!   [!seq]  matches any character not in seq
//!
//! Mirrors: CPython Lib/fnmatch.py

const std = @import("std");

/// Test whether filename matches pattern
/// Pattern uses shell-style wildcards: *, ?, [seq], [!seq]
pub fn fnmatch(name: []const u8, pattern: []const u8) bool {
    return fnmatchcase(name, pattern);
}

/// Case-sensitive version of fnmatch
pub fn fnmatchcase(name: []const u8, pattern: []const u8) bool {
    return matchPattern(name, pattern);
}

/// Filter names by pattern, returning matching names
pub fn filter(allocator: std.mem.Allocator, names: []const []const u8, pattern: []const u8) ![][]const u8 {
    var result = std.ArrayList([]const u8).init(allocator);
    errdefer result.deinit();

    for (names) |name| {
        if (fnmatch(name, pattern)) {
            try result.append(name);
        }
    }

    return result.toOwnedSlice();
}

/// Translate a shell pattern to a regular expression
/// Returns a string that can be used with regex matching
pub fn translate(allocator: std.mem.Allocator, pattern: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    try result.append('^');

    var i: usize = 0;
    while (i < pattern.len) {
        const c = pattern[i];
        switch (c) {
            '*' => try result.appendSlice(".*"),
            '?' => try result.append('.'),
            '[' => {
                // Character class
                try result.append('[');
                i += 1;
                if (i < pattern.len and pattern[i] == '!') {
                    try result.append('^');
                    i += 1;
                } else if (i < pattern.len and pattern[i] == '^') {
                    try result.append('\\');
                    try result.append('^');
                    i += 1;
                }
                // Copy until ]
                while (i < pattern.len and pattern[i] != ']') {
                    if (pattern[i] == '\\') {
                        try result.append('\\');
                        try result.append('\\');
                    } else {
                        try result.append(pattern[i]);
                    }
                    i += 1;
                }
                try result.append(']');
            },
            '\\', '.', '+', '^', '$', '|', '{', '}', '(', ')' => {
                // Escape regex special chars
                try result.append('\\');
                try result.append(c);
            },
            else => try result.append(c),
        }
        i += 1;
    }

    try result.append('$');
    return result.toOwnedSlice();
}

// Internal pattern matching
fn matchPattern(name: []const u8, pattern: []const u8) bool {
    return matchPatternInternal(name, 0, pattern, 0);
}

fn matchPatternInternal(name: []const u8, name_idx: usize, pattern: []const u8, pat_idx: usize) bool {
    var ni = name_idx;
    var pi = pat_idx;

    while (pi < pattern.len) {
        const pc = pattern[pi];

        switch (pc) {
            '*' => {
                // Skip consecutive *
                while (pi < pattern.len and pattern[pi] == '*') {
                    pi += 1;
                }
                // * at end matches everything
                if (pi >= pattern.len) {
                    return true;
                }
                // Try matching * with 0, 1, 2, ... chars
                while (ni <= name.len) {
                    if (matchPatternInternal(name, ni, pattern, pi)) {
                        return true;
                    }
                    ni += 1;
                }
                return false;
            },
            '?' => {
                // Match any single character
                if (ni >= name.len) return false;
                ni += 1;
                pi += 1;
            },
            '[' => {
                // Character class
                if (ni >= name.len) return false;

                pi += 1;
                const negate = if (pi < pattern.len and pattern[pi] == '!') blk: {
                    pi += 1;
                    break :blk true;
                } else false;

                var matched = false;
                const nc = name[ni];

                // Parse character class
                while (pi < pattern.len and pattern[pi] != ']') {
                    const start = pattern[pi];
                    pi += 1;

                    if (pi + 1 < pattern.len and pattern[pi] == '-' and pattern[pi + 1] != ']') {
                        // Range: a-z
                        pi += 1;
                        const end = pattern[pi];
                        pi += 1;
                        if (nc >= start and nc <= end) {
                            matched = true;
                        }
                    } else {
                        // Single character
                        if (nc == start) {
                            matched = true;
                        }
                    }
                }

                // Skip closing ]
                if (pi < pattern.len and pattern[pi] == ']') {
                    pi += 1;
                }

                if (negate) {
                    if (matched) return false;
                } else {
                    if (!matched) return false;
                }
                ni += 1;
            },
            else => {
                // Literal character
                if (ni >= name.len or name[ni] != pc) {
                    return false;
                }
                ni += 1;
                pi += 1;
            },
        }
    }

    // Pattern consumed - name should also be consumed
    return ni >= name.len;
}

// ============================================================================
// Tests
// ============================================================================

test "fnmatch basic patterns" {
    const testing = std.testing;

    // Literal match
    try testing.expect(fnmatch("foo.txt", "foo.txt"));
    try testing.expect(!fnmatch("foo.txt", "bar.txt"));

    // * wildcard
    try testing.expect(fnmatch("foo.txt", "*.txt"));
    try testing.expect(fnmatch("foo.txt", "foo.*"));
    try testing.expect(fnmatch("foo.txt", "*"));
    try testing.expect(!fnmatch("foo.txt", "*.py"));

    // ? wildcard
    try testing.expect(fnmatch("foo.txt", "fo?.txt"));
    try testing.expect(fnmatch("abc", "???"));
    try testing.expect(!fnmatch("abcd", "???"));

    // Character classes
    try testing.expect(fnmatch("foo.txt", "[f]oo.txt"));
    try testing.expect(fnmatch("foo.txt", "[a-z]oo.txt"));
    try testing.expect(!fnmatch("foo.txt", "[A-Z]oo.txt"));

    // Negated character class
    try testing.expect(fnmatch("foo.txt", "[!a]oo.txt"));
    try testing.expect(!fnmatch("foo.txt", "[!f]oo.txt"));
}

test "fnmatch complex patterns" {
    const testing = std.testing;

    // Multiple wildcards
    try testing.expect(fnmatch("src/main.zig", "src/*.zig"));
    try testing.expect(fnmatch("test_foo_bar.py", "test_*.py"));
    try testing.expect(fnmatch("a.b.c", "*.*.*"));

    // Empty patterns/names
    try testing.expect(fnmatch("", ""));
    try testing.expect(fnmatch("", "*"));
    try testing.expect(!fnmatch("foo", ""));
}

test "filter" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const names = [_][]const u8{ "foo.txt", "bar.txt", "foo.py", "baz.txt" };
    const result = try filter(allocator, &names, "*.txt");
    defer allocator.free(result);

    try testing.expectEqual(@as(usize, 3), result.len);
}

test "translate" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const regex = try translate(allocator, "*.txt");
    defer allocator.free(regex);

    try testing.expectEqualStrings("^.*\\.txt$", regex);
}
