/// String operations for 're' module: sub, subn, findall, split, finditer
const std = @import("std");
const runtime = @import("../../runtime.zig");
const types = @import("types.zig");

pub const Regex = types.Regex;

/// Python-compatible sub() function
/// Usage: result = re.sub(r'\d+', 'NUM', 'abc123def456')
pub fn sub(allocator: std.mem.Allocator, pattern: []const u8, replacement: []const u8, text: []const u8) !*runtime.PyObject {
    var regex = try Regex.compile(allocator, pattern);
    defer regex.deinit();

    // Build result by iterating through matches
    var result = std.ArrayList(u8){};
    defer result.deinit(allocator);

    var pos: usize = 0;
    while (pos < text.len) {
        // Find next match starting from current position
        const match_opt = try regex.find(text[pos..]);

        if (match_opt) |m| {
            defer {
                var match_copy = m;
                match_copy.deinit(allocator);
            }

            // Append text before match
            try result.appendSlice(allocator, text[pos .. pos + m.span.start]);

            // Append replacement
            try result.appendSlice(allocator, replacement);

            // Move past the match
            const match_end = pos + m.span.end;
            if (match_end == pos) {
                // Zero-length match - advance by 1 to avoid infinite loop
                if (pos < text.len) {
                    try result.append(allocator, text[pos]);
                }
                pos += 1;
            } else {
                pos = match_end;
            }
        } else {
            // No more matches - append rest of text
            try result.appendSlice(allocator, text[pos..]);
            break;
        }
    }

    // Create owned string (ArrayList.toOwnedSlice gives us ownership)
    const owned = try result.toOwnedSlice(allocator);
    return try runtime.PyString.createOwned(allocator, owned);
}

/// Python-compatible subn() function
/// Usage: result, count = re.subn(r'\d+', 'NUM', 'abc123def456')
/// Returns tuple of (result_string, replacement_count)
pub fn subn(allocator: std.mem.Allocator, pattern: []const u8, replacement: []const u8, text: []const u8) !*runtime.PyObject {
    var regex = try Regex.compile(allocator, pattern);
    defer regex.deinit();

    var result = std.ArrayList(u8){};
    defer result.deinit(allocator);

    var count: i64 = 0;
    var pos: usize = 0;
    while (pos < text.len) {
        const match_opt = try regex.find(text[pos..]);

        if (match_opt) |m| {
            defer {
                var match_copy = m;
                match_copy.deinit(allocator);
            }

            try result.appendSlice(allocator, text[pos .. pos + m.span.start]);
            try result.appendSlice(allocator, replacement);
            count += 1;

            const match_end = pos + m.span.end;
            if (match_end == pos) {
                if (pos < text.len) {
                    try result.append(allocator, text[pos]);
                }
                pos += 1;
            } else {
                pos = match_end;
            }
        } else {
            try result.appendSlice(allocator, text[pos..]);
            break;
        }
    }

    const owned = try result.toOwnedSlice(allocator);
    const str_obj = try runtime.PyString.createOwned(allocator, owned);

    // Create tuple (string, count)
    const tuple = try runtime.PyTuple.create(allocator, 2);
    runtime.PyTuple.setItem(tuple, 0, str_obj);
    const count_obj = try runtime.PyInt.create(allocator, count);
    runtime.PyTuple.setItem(tuple, 1, count_obj);

    return tuple;
}

/// Python-compatible findall() function
/// Usage: matches = re.findall(r"\d+", "abc123def456")
/// Returns a PyList of matched strings
pub fn findall(allocator: std.mem.Allocator, pattern: []const u8, text: []const u8) !*runtime.PyObject {
    var regex = try Regex.compile(allocator, pattern);
    defer regex.deinit();

    var matches = try regex.findAll(text);
    defer {
        for (matches.items) |item| {
            allocator.free(item);
        }
        matches.deinit(allocator);
    }

    // Create a PyList to hold the results
    const list = try runtime.PyList.create(allocator);

    for (matches.items) |matched_text| {
        const str_obj = try runtime.PyString.create(allocator, matched_text);
        try runtime.PyList.append(list, str_obj);
    }

    return list;
}

/// Python-compatible finditer() function
/// Usage: for match in re.finditer(r"\d+", "abc123def456"): ...
/// Returns a PyList of match objects (simplified as strings for now)
pub fn finditer(allocator: std.mem.Allocator, pattern: []const u8, text: []const u8) !*runtime.PyObject {
    // For simplicity, finditer returns same as findall (list of strings)
    // A full implementation would return Match objects
    return findall(allocator, pattern, text);
}

/// Python-compatible split() function
/// Usage: parts = re.split(r"\s+", "hello world  foo  bar")
/// Returns a PyList of strings split by the pattern
pub fn split(allocator: std.mem.Allocator, pattern: []const u8, text: []const u8) !*runtime.PyObject {
    var regex = try Regex.compile(allocator, pattern);
    defer regex.deinit();

    // Create a PyList to hold the results
    const list = try runtime.PyList.create(allocator);
    errdefer runtime.decref(list, allocator);

    var pos: usize = 0;
    while (pos <= text.len) {
        // Find next match starting from current position
        const match_opt = try regex.find(text[pos..]);

        if (match_opt) |m| {
            defer {
                var match_copy = m;
                match_copy.deinit(allocator);
            }

            // Add text before match as a segment
            const segment = text[pos .. pos + m.span.start];
            const str_obj = try runtime.PyString.create(allocator, segment);
            try runtime.PyList.append(list, str_obj);

            // Move past the match
            const match_end = pos + m.span.end;
            if (match_end == pos) {
                // Zero-length match - advance by 1 to avoid infinite loop
                pos += 1;
            } else {
                pos = match_end;
            }
        } else {
            // No more matches - add rest of text as final segment
            const segment = text[pos..];
            const str_obj = try runtime.PyString.create(allocator, segment);
            try runtime.PyList.append(list, str_obj);
            break;
        }
    }

    return list;
}

test "re.sub replaces all matches" {
    const allocator = std.testing.allocator;

    const result = try sub(allocator, "\\d+", "NUM", "abc123def456");
    defer runtime.decref(result, allocator);

    const value = runtime.PyString.getValue(result);
    try std.testing.expectEqualStrings("abcNUMdefNUM", value);
}

test "re.sub no matches" {
    const allocator = std.testing.allocator;

    const result = try sub(allocator, "\\d+", "NUM", "abcdef");
    defer runtime.decref(result, allocator);

    const value = runtime.PyString.getValue(result);
    try std.testing.expectEqualStrings("abcdef", value);
}

test "re.findall basic" {
    const allocator = std.testing.allocator;

    const result = try findall(allocator, "\\d+", "abc123def456ghi789");
    defer runtime.decref(result, allocator);

    // Verify it's a list with 3 items
    try std.testing.expect(result.type_id == .list);
    try std.testing.expectEqual(@as(usize, 3), runtime.PyList.len(result));
}

test "re.findall no matches" {
    const allocator = std.testing.allocator;

    const result = try findall(allocator, "\\d+", "abcdefghi");
    defer runtime.decref(result, allocator);

    // Verify it's an empty list
    try std.testing.expect(result.type_id == .list);
    try std.testing.expectEqual(@as(usize, 0), runtime.PyList.len(result));
}

test "re.split basic" {
    const allocator = std.testing.allocator;

    const result = try split(allocator, "\\s+", "hello world foo bar");
    defer runtime.decref(result, allocator);

    // Verify it's a list with 4 items
    try std.testing.expect(result.type_id == .list);
    try std.testing.expectEqual(@as(usize, 4), runtime.PyList.len(result));
}

test "re.split no matches" {
    const allocator = std.testing.allocator;

    const result = try split(allocator, "\\d+", "hello world");
    defer runtime.decref(result, allocator);

    // Should return original string as single element
    try std.testing.expect(result.type_id == .list);
    try std.testing.expectEqual(@as(usize, 1), runtime.PyList.len(result));
}
