/// Match operations for 're' module: search, match, fullmatch
const std = @import("std");
const runtime = @import("../../runtime.zig");
const types = @import("types.zig");
const pattern = @import("pattern.zig");

pub const PyMatch = types.PyMatch;
pub const Regex = types.Regex;
pub const IGNORECASE = pattern.IGNORECASE;

/// Python-compatible search() function - 2 arg version
/// Usage: match = re.search(r"hello", "hello world")
/// Returns PyMatch object (with is_match=false if no match)
pub fn search(allocator: std.mem.Allocator, pat: anytype, text: anytype) !*PyMatch {
    return searchImpl(allocator, pat, text, 0);
}

/// search with flags - called when 3 args provided
fn searchImpl(allocator: std.mem.Allocator, pat: anytype, text: anytype, flags: anytype) !*PyMatch {
    const pattern_str = if (@TypeOf(pat) == []const u8) pat else @as([]const u8, pat);
    const text_str = if (@TypeOf(text) == []const u8) text else @as([]const u8, text);
    const flags_val: i64 = if (@TypeOf(flags) == i64) flags else @as(i64, @intCast(flags));

    // Apply flags to pattern
    var actual_pattern: []const u8 = pattern_str;
    var owned_pattern: ?[]u8 = null;
    defer if (owned_pattern) |p| allocator.free(p);

    if (flags_val & IGNORECASE != 0) {
        owned_pattern = try std.fmt.allocPrint(allocator, "(?i){s}", .{pattern_str});
        actual_pattern = owned_pattern.?;
    }

    var regex = try Regex.compile(allocator, actual_pattern);
    defer regex.deinit();

    const match_opt = try regex.find(text_str);
    if (match_opt == null) return try PyMatch.createNone(allocator);

    var m = match_opt.?;
    defer m.deinit(allocator);

    // Return PyMatch object
    return try PyMatch.create(allocator, text_str, m);
}

/// Python-compatible match() function - 2 arg version
/// Usage: match = re.match(r"hello", "hello world")
/// Returns PyMatch object (with is_match=false if no match)
pub fn match(allocator: std.mem.Allocator, pat: anytype, text: anytype) !*PyMatch {
    return matchImpl(allocator, pat, text, 0);
}

/// match with flags - called when 3 args provided
fn matchImpl(allocator: std.mem.Allocator, pat: anytype, text: anytype, flags: anytype) !*PyMatch {
    const pattern_str = if (@TypeOf(pat) == []const u8) pat else @as([]const u8, pat);
    const text_str = if (@TypeOf(text) == []const u8) text else @as([]const u8, text);
    const flags_val: i64 = if (@TypeOf(flags) == i64) flags else @as(i64, @intCast(flags));

    // Apply flags to pattern - add ^ anchor for match() behavior
    var actual_pattern: []const u8 = pattern_str;
    var owned_pattern: ?[]u8 = null;
    defer if (owned_pattern) |p| allocator.free(p);

    if (flags_val & IGNORECASE != 0) {
        owned_pattern = try std.fmt.allocPrint(allocator, "(?i)^{s}", .{pattern_str});
        actual_pattern = owned_pattern.?;
    } else {
        // Add ^ anchor to make match() only match at start
        owned_pattern = try std.fmt.allocPrint(allocator, "^{s}", .{pattern_str});
        actual_pattern = owned_pattern.?;
    }

    var regex = try Regex.compile(allocator, actual_pattern);
    defer regex.deinit();

    const match_opt = try regex.find(text_str);
    if (match_opt == null) return try PyMatch.createNone(allocator);

    var m = match_opt.?;
    defer m.deinit(allocator);

    return try PyMatch.create(allocator, text_str, m);
}

/// Python-compatible fullmatch() function
/// Usage: match = re.fullmatch(r"hello", "hello")
/// Returns PyString with matched text only if entire string matches, or None
pub fn fullmatch(allocator: std.mem.Allocator, pat: anytype, text: anytype) !*runtime.PyObject {
    const pattern_str = if (@TypeOf(pat) == []const u8) pat else @as([]const u8, pat);
    const text_str = if (@TypeOf(text) == []const u8) text else @as([]const u8, text);

    var regex = try Regex.compile(allocator, pattern_str);
    defer regex.deinit();

    const match_opt = try regex.find(text_str);
    if (match_opt == null) return try pattern.createNone(allocator);

    var m = match_opt.?;
    defer m.deinit(allocator);

    // fullmatch requires entire string to match
    if (m.span.start != 0 or m.span.end != text_str.len) return try pattern.createNone(allocator);

    const matched_text = text_str[m.span.start..m.span.end];
    return try runtime.PyString.create(allocator, matched_text);
}

test "re.search finds match" {
    const allocator = std.testing.allocator;

    const result = try search(allocator, "world", "hello world");
    try std.testing.expect(result != null);
    defer runtime.decref(result, allocator);
}

test "re.match requires start match" {
    const allocator = std.testing.allocator;

    // Should match
    const result1 = try match(allocator, "hello", "hello world");
    try std.testing.expect(result1 != null);
    defer runtime.decref(result1, allocator);

    // Should NOT match (doesn't start with "world")
    const result2 = try match(allocator, "world", "hello world");
    try std.testing.expect(result2 == null);
}
