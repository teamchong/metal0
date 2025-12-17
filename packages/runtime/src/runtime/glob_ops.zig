/// Glob pattern matching for Python glob module
/// Extracted from runtime.zig to reduce file size
const std = @import("std");

/// Match a glob pattern against a filename (Python glob semantics)
/// Supports: * (any chars), ? (single char), [abc] (char class), [!abc] (negated)
pub fn globMatch(pattern: []const u8, name: []const u8) bool {
    var pi: usize = 0;
    var ni: usize = 0;
    var star_p: ?usize = null;
    var star_n: ?usize = null;

    while (ni < name.len or pi < pattern.len) {
        if (pi < pattern.len) {
            const pc = pattern[pi];
            if (pc == '*') {
                // * matches any sequence
                star_p = pi;
                star_n = ni;
                pi += 1;
                continue;
            } else if (pc == '?') {
                // ? matches any single char
                if (ni < name.len) {
                    pi += 1;
                    ni += 1;
                    continue;
                }
            } else if (pc == '[') {
                // Character class
                if (ni < name.len) {
                    if (matchCharClass(pattern[pi..], name[ni])) |skip| {
                        pi += skip;
                        ni += 1;
                        continue;
                    }
                }
            } else {
                // Literal match
                if (ni < name.len and pc == name[ni]) {
                    pi += 1;
                    ni += 1;
                    continue;
                }
            }
        }
        // No match - backtrack to last * if possible
        if (star_p) |sp| {
            pi = sp + 1;
            star_n.? += 1;
            ni = star_n.?;
            if (ni > name.len) return false;
        } else {
            return false;
        }
    }
    return true;
}

/// Match character class [abc] or [!abc], returns chars to skip in pattern or null
pub fn matchCharClass(pattern: []const u8, c: u8) ?usize {
    if (pattern.len < 2 or pattern[0] != '[') return null;
    var i: usize = 1;
    const negate = if (i < pattern.len and (pattern[i] == '!' or pattern[i] == '^')) blk: {
        i += 1;
        break :blk true;
    } else false;

    var matched = false;
    while (i < pattern.len and pattern[i] != ']') : (i += 1) {
        // Check for range [a-z]
        if (i + 2 < pattern.len and pattern[i + 1] == '-' and pattern[i + 2] != ']') {
            if (c >= pattern[i] and c <= pattern[i + 2]) matched = true;
            i += 2;
        } else {
            if (c == pattern[i]) matched = true;
        }
    }
    if (i >= pattern.len) return null; // No closing ]
    return if ((matched and !negate) or (!matched and negate)) i + 1 else null;
}

/// Recursively collect files matching glob pattern
pub fn rglobCollect(allocator: std.mem.Allocator, base_path: []const u8, pattern: []const u8, entries: *std.ArrayList([]const u8)) void {
    var dir = std.fs.cwd().openDir(base_path, .{ .iterate = true }) catch return;
    defer dir.close();

    var it = dir.iterate();
    while (it.next() catch null) |entry| {
        const full_path = std.fs.path.join(allocator, &.{ base_path, entry.name }) catch unreachable;

        if (globMatch(pattern, entry.name)) {
            entries.append(allocator, full_path) catch unreachable;
        }

        // Recurse into directories
        if (entry.kind == .directory) {
            rglobCollect(allocator, full_path, pattern, entries);
        }
    }
}
