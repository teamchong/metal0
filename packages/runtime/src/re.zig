/// Python 're' module - regex support
/// Wraps the pyregex package for Python compatibility
const std = @import("std");
const runtime = @import("runtime.zig");

// Import the regex engine via build.zig module
const regex_impl = @import("regex");

pub const Regex = regex_impl.Regex;
pub const Match = regex_impl.Match;
pub const Span = regex_impl.Span;

/// Python-compatible compile() function
/// Usage: pattern = re.compile(r"hello")
pub fn compile(allocator: std.mem.Allocator, pattern: []const u8) !*runtime.PyObject {
    // Compile the regex
    const regex = try Regex.compile(allocator, pattern);

    // Wrap in PyObject
    // For now, we'll store it as an opaque pointer
    // TODO: Add proper PyRegex type to PyObject.TypeId
    const obj = try allocator.create(runtime.PyObject);
    obj.* = .{
        .ref_count = 1,
        .type_id = .none, // TODO: Add .regex type
        .data = @ptrCast(@constCast(&regex)),
    };

    return obj;
}

/// Create a None PyObject
fn createNone(allocator: std.mem.Allocator) !*runtime.PyObject {
    const obj = try allocator.create(runtime.PyObject);
    obj.* = .{
        .ref_count = 1,
        .type_id = .none,
        .data = undefined,
    };
    return obj;
}

/// Python re flags (subset - ignoring flags for now in basic implementation)
pub const IGNORECASE: i64 = 2;
pub const MULTILINE: i64 = 8;
pub const DOTALL: i64 = 16;
pub const VERBOSE: i64 = 64;

/// Python-compatible search() function - 2 arg version
/// Usage: match = re.search(r"hello", "hello world")
/// Returns PyString with matched text, or None if no match
pub fn search(allocator: std.mem.Allocator, pattern: anytype, text: anytype) !*runtime.PyObject {
    return searchImpl(allocator, pattern, text, 0);
}

/// search with flags - called when 3 args provided
fn searchImpl(allocator: std.mem.Allocator, pattern: anytype, text: anytype, flags: anytype) !*runtime.PyObject {
    _ = flags; // TODO: implement flag support
    const pattern_str = if (@TypeOf(pattern) == []const u8) pattern else @as([]const u8, pattern);
    const text_str = if (@TypeOf(text) == []const u8) text else @as([]const u8, text);

    var regex = try Regex.compile(allocator, pattern_str);
    defer regex.deinit();

    const match_opt = try regex.find(text_str);
    if (match_opt == null) return try createNone(allocator);

    var m = match_opt.?;
    defer m.deinit(allocator);

    // Wrap match in PyObject
    // For now, return the matched string as PyString
    const matched_text = text_str[m.span.start..m.span.end];
    return try runtime.PyString.create(allocator, matched_text);
}

/// Python-compatible match() function - 2 arg version
/// Usage: match = re.match(r"hello", "hello world")
/// Returns PyString with matched text, or None if no match
pub fn match(allocator: std.mem.Allocator, pattern: anytype, text: anytype) !*runtime.PyObject {
    return matchImpl(allocator, pattern, text, 0);
}

/// match with flags - called when 3 args provided
fn matchImpl(allocator: std.mem.Allocator, pattern: anytype, text: anytype, flags: anytype) !*runtime.PyObject {
    _ = flags; // TODO: implement flag support
    const pattern_str = if (@TypeOf(pattern) == []const u8) pattern else @as([]const u8, pattern);
    const text_str = if (@TypeOf(text) == []const u8) text else @as([]const u8, text);

    var regex = try Regex.compile(allocator, pattern_str);
    defer regex.deinit();

    const match_opt = try regex.find(text_str);
    if (match_opt == null) return try createNone(allocator);

    var m = match_opt.?;
    defer m.deinit(allocator);

    // match() only succeeds if pattern matches at start
    if (m.span.start != 0) return try createNone(allocator);

    const matched_text = text_str[m.span.start..m.span.end];
    return try runtime.PyString.create(allocator, matched_text);
}

test "re.compile basic" {
    const allocator = std.testing.allocator;

    const pattern_obj = try compile(allocator, "hello");
    defer runtime.decref(pattern_obj, allocator);

    try std.testing.expect(pattern_obj.ref_count == 1);
}

test "re.search finds match" {
    const allocator = std.testing.allocator;

    const result = try search(allocator, "world", "hello world");
    try std.testing.expect(result != null);
    defer if (result) |obj| runtime.decref(obj, allocator);
}

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

test "re.match requires start match" {
    const allocator = std.testing.allocator;

    // Should match
    const result1 = try match(allocator, "hello", "hello world");
    try std.testing.expect(result1 != null);
    defer if (result1) |obj| runtime.decref(obj, allocator);

    // Should NOT match (doesn't start with "world")
    const result2 = try match(allocator, "world", "hello world");
    try std.testing.expect(result2 == null);
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
