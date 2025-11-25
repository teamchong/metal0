/// Python 're' module - regex support
/// Wraps the pyregex package for Python compatibility
const std = @import("std");
const runtime = @import("runtime.zig");

// Import the regex engine
// When copied to .build/, the path is ./regex/src/pyregex/regex.zig
const regex_impl = @import("regex/src/pyregex/regex.zig");

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

/// Python-compatible search() function
/// Usage: match = re.search(r"hello", "hello world")
pub fn search(allocator: std.mem.Allocator, pattern: []const u8, text: []const u8) !?*runtime.PyObject {
    var regex = try Regex.compile(allocator, pattern);
    defer regex.deinit();

    const match_opt = try regex.find(text);
    if (match_opt == null) return null;

    var m = match_opt.?;
    defer m.deinit(allocator);

    // Wrap match in PyObject
    // For now, return the matched string as PyString
    const matched_text = text[m.span.start..m.span.end];
    return try runtime.PyString.create(allocator, matched_text);
}

/// Python-compatible match() function
/// Usage: match = re.match(r"hello", "hello world")
pub fn match(allocator: std.mem.Allocator, pattern: []const u8, text: []const u8) !?*runtime.PyObject {
    var regex = try Regex.compile(allocator, pattern);
    defer regex.deinit();

    const match_opt = try regex.find(text);
    if (match_opt == null) return null;

    var m = match_opt.?;
    defer m.deinit(allocator);

    // match() only succeeds if pattern matches at start
    if (m.span.start != 0) return null;

    const matched_text = text[m.span.start..m.span.end];
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
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

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
            try result.appendSlice(text[pos .. pos + m.span.start]);

            // Append replacement
            try result.appendSlice(replacement);

            // Move past the match
            const match_end = pos + m.span.end;
            if (match_end == pos) {
                // Zero-length match - advance by 1 to avoid infinite loop
                if (pos < text.len) {
                    try result.append(text[pos]);
                }
                pos += 1;
            } else {
                pos = match_end;
            }
        } else {
            // No more matches - append rest of text
            try result.appendSlice(text[pos..]);
            break;
        }
    }

    // Create owned string (ArrayList.toOwnedSlice gives us ownership)
    const owned = try result.toOwnedSlice();
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
    var list = try runtime.PyList.create(allocator);

    for (matches.items) |matched_text| {
        const str_obj = try runtime.PyString.create(allocator, matched_text);
        try list.append(str_obj);
    }

    return list.toPyObject();
}

test "re.findall basic" {
    const allocator = std.testing.allocator;

    const result = try findall(allocator, "\\d+", "abc123def456ghi789");
    defer runtime.decref(result, allocator);

    // Verify it's a list with 3 items
    const list = runtime.PyList.fromPyObject(result);
    try std.testing.expect(list != null);
    try std.testing.expectEqual(@as(usize, 3), list.?.len());
}

test "re.findall no matches" {
    const allocator = std.testing.allocator;

    const result = try findall(allocator, "\\d+", "abcdefghi");
    defer runtime.decref(result, allocator);

    // Verify it's an empty list
    const list = runtime.PyList.fromPyObject(result);
    try std.testing.expect(list != null);
    try std.testing.expectEqual(@as(usize, 0), list.?.len());
}
