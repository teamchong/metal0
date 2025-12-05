/// glob - Unix style pathname pattern expansion
/// Supports *, ?, [seq], [!seq] patterns
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Match a pattern against a string
/// Supports: * (any chars), ? (single char), [abc] (char class), [!abc] (negated)
pub fn fnmatch(pattern: []const u8, name: []const u8) bool {
    var pi: usize = 0;
    var ni: usize = 0;

    // For * backtracking
    var star_pi: ?usize = null;
    var star_ni: usize = 0;

    while (ni < name.len or pi < pattern.len) {
        if (pi < pattern.len) {
            const pc = pattern[pi];

            switch (pc) {
                '*' => {
                    // Match zero or more characters
                    star_pi = pi;
                    star_ni = ni;
                    pi += 1;
                    continue;
                },
                '?' => {
                    // Match exactly one character
                    if (ni < name.len) {
                        pi += 1;
                        ni += 1;
                        continue;
                    }
                },
                '[' => {
                    // Character class
                    if (ni < name.len) {
                        if (matchCharClass(pattern[pi..], name[ni])) |advance| {
                            pi += advance;
                            ni += 1;
                            continue;
                        }
                    }
                },
                else => {
                    // Literal character
                    if (ni < name.len and name[ni] == pc) {
                        pi += 1;
                        ni += 1;
                        continue;
                    }
                },
            }
        }

        // No match - try backtracking to last *
        if (star_pi) |sp| {
            pi = sp + 1;
            star_ni += 1;
            ni = star_ni;
            if (ni <= name.len) continue;
        }

        return false;
    }

    return true;
}

/// Match a character class like [abc] or [!abc] or [a-z]
/// Returns number of pattern chars consumed, or null if no match
fn matchCharClass(pattern: []const u8, char: u8) ?usize {
    if (pattern.len < 2 or pattern[0] != '[') return null;

    var i: usize = 1;
    var negate = false;

    if (i < pattern.len and (pattern[i] == '!' or pattern[i] == '^')) {
        negate = true;
        i += 1;
    }

    var matched = false;
    var prev_char: ?u8 = null;

    while (i < pattern.len and pattern[i] != ']') {
        if (pattern[i] == '-' and prev_char != null and i + 1 < pattern.len and pattern[i + 1] != ']') {
            // Range like a-z
            const range_end = pattern[i + 1];
            if (char >= prev_char.? and char <= range_end) {
                matched = true;
            }
            i += 2;
            prev_char = null;
        } else {
            if (char == pattern[i]) {
                matched = true;
            }
            prev_char = pattern[i];
            i += 1;
        }
    }

    if (i < pattern.len and pattern[i] == ']') {
        const result = if (negate) !matched else matched;
        return if (result) i + 1 else null;
    }

    return null;
}

/// Expand glob pattern and return matching paths
pub fn glob(allocator: Allocator, pattern: []const u8) !std.ArrayList([]const u8) {
    var results = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (results.items) |item| allocator.free(item);
        results.deinit();
    }

    // Split pattern into directory and file parts
    const sep = std.fs.path.sep;
    if (std.mem.lastIndexOfScalar(u8, pattern, sep)) |last_sep| {
        const dir_pattern = pattern[0..last_sep];
        const file_pattern = pattern[last_sep + 1 ..];

        // Check if directory part has wildcards
        if (hasWildcard(dir_pattern)) {
            // Recursively glob the directory part first
            var dir_matches = try glob(allocator, dir_pattern);
            defer {
                for (dir_matches.items) |item| allocator.free(item);
                dir_matches.deinit();
            }

            for (dir_matches.items) |dir_path| {
                try globInDir(allocator, dir_path, file_pattern, &results);
            }
        } else {
            // Directory is literal, just glob the file pattern
            try globInDir(allocator, dir_pattern, file_pattern, &results);
        }
    } else {
        // No directory separator - glob in current directory
        try globInDir(allocator, ".", pattern, &results);
    }

    return results;
}

/// Check if pattern contains wildcard characters
fn hasWildcard(pattern: []const u8) bool {
    for (pattern) |c| {
        if (c == '*' or c == '?' or c == '[') return true;
    }
    return false;
}

/// Glob for files matching pattern in a specific directory
fn globInDir(
    allocator: Allocator,
    dir_path: []const u8,
    pattern: []const u8,
    results: *std.ArrayList([]const u8),
) !void {
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return;
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (fnmatch(pattern, entry.name)) {
            const full_path = try std.fs.path.join(allocator, &.{ dir_path, entry.name });
            try results.append(full_path);
        }
    }
}

/// Recursive glob with ** support
pub fn iglob(allocator: Allocator, pattern: []const u8) !std.ArrayList([]const u8) {
    // For now, same as glob - ** support would require more complex handling
    return glob(allocator, pattern);
}

/// Escape special characters in a pathname
pub fn escape(allocator: Allocator, pathname: []const u8) ![]const u8 {
    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    for (pathname) |c| {
        if (c == '*' or c == '?' or c == '[') {
            try result.append(allocator, '[');
            try result.append(allocator, c);
            try result.append(allocator, ']');
        } else {
            try result.append(allocator, c);
        }
    }

    return try result.toOwnedSlice(allocator);
}

/// Check if path has any magic glob characters
pub fn has_magic(pattern: []const u8) bool {
    return hasWildcard(pattern);
}

// ============================================================================
// Tests
// ============================================================================

test "fnmatch basic" {
    const testing = std.testing;

    // Literal match
    try testing.expect(fnmatch("foo", "foo"));
    try testing.expect(!fnmatch("foo", "bar"));

    // * wildcard
    try testing.expect(fnmatch("*.txt", "test.txt"));
    try testing.expect(fnmatch("*.txt", ".txt"));
    try testing.expect(!fnmatch("*.txt", "test.py"));
    try testing.expect(fnmatch("test*", "test.txt"));
    try testing.expect(fnmatch("*est*", "test.txt"));

    // ? wildcard
    try testing.expect(fnmatch("?.txt", "a.txt"));
    try testing.expect(!fnmatch("?.txt", "ab.txt"));
    try testing.expect(fnmatch("test.???", "test.txt"));
}

test "fnmatch character class" {
    const testing = std.testing;

    // Character class
    try testing.expect(fnmatch("[abc].txt", "a.txt"));
    try testing.expect(fnmatch("[abc].txt", "b.txt"));
    try testing.expect(!fnmatch("[abc].txt", "d.txt"));

    // Negated class
    try testing.expect(fnmatch("[!abc].txt", "d.txt"));
    try testing.expect(!fnmatch("[!abc].txt", "a.txt"));

    // Range
    try testing.expect(fnmatch("[a-z].txt", "m.txt"));
    try testing.expect(!fnmatch("[a-z].txt", "M.txt"));
}

test "escape" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const escaped = try escape(allocator, "test*.txt");
    defer allocator.free(escaped);
    try testing.expectEqualStrings("test[*].txt", escaped);
}

test "has_magic" {
    const testing = std.testing;

    try testing.expect(has_magic("*.txt"));
    try testing.expect(has_magic("test?.py"));
    try testing.expect(has_magic("[abc].txt"));
    try testing.expect(!has_magic("test.txt"));
}
