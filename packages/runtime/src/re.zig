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
    defer {
        runtime.decref(pattern_obj);
    }

    try std.testing.expect(pattern_obj.ref_count == 1);
}

test "re.search finds match" {
    const allocator = std.testing.allocator;

    const result = try search(allocator, "world", "hello world");
    try std.testing.expect(result != null);

    defer {
        if (result) |obj| runtime.decref(obj);
    }
}

test "re.match requires start match" {
    const allocator = std.testing.allocator;

    // Should match
    const result1 = try match(allocator, "hello", "hello world");
    try std.testing.expect(result1 != null);
    defer if (result1) |obj| runtime.decref(obj);

    // Should NOT match (doesn't start with "world")
    const result2 = try match(allocator, "world", "hello world");
    try std.testing.expect(result2 == null);
}
