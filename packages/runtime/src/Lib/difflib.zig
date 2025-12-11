//! CPython source: Lib/difflib.py
//!
//! Provides classes and functions for comparing sequences.
//!
//! Mirrors: CPython Lib/difflib.py

const std = @import("std");

// Re-export core types
pub const types = @import("difflib/types.zig");
pub const Match = types.Match;
pub const Opcode = types.Opcode;

// Re-export SequenceMatcher
pub const sequence_matcher = @import("difflib/sequence_matcher.zig");
pub const SequenceMatcher = sequence_matcher.SequenceMatcher;

// Re-export Differ
pub const differ = @import("difflib/differ.zig");
pub const Differ = differ.Differ;

// Re-export HtmlDiff
pub const html_diff = @import("difflib/html_diff.zig");
pub const HtmlDiff = html_diff.HtmlDiff;

// Re-export utility functions
pub const utils = @import("difflib/utils.zig");
pub const getCloseMatches = utils.getCloseMatches;
pub const unifiedDiff = utils.unifiedDiff;
pub const contextDiff = utils.contextDiff;
pub const ndiff = utils.ndiff;
pub const restore = utils.restore;

// ============================================================================
// Tests
// ============================================================================

test "SequenceMatcher ratio" {
    const allocator = std.testing.allocator;
    var sm = SequenceMatcher(u8).init(allocator, "abcd", "bcde");
    defer sm.deinit();

    const r = try sm.ratio();
    try std.testing.expect(r > 0.5);
}

test "SequenceMatcher find longest match" {
    const allocator = std.testing.allocator;
    var sm = SequenceMatcher(u8).init(allocator, "abxcd", "abcd");
    defer sm.deinit();

    const match = sm.findLongestMatch(0, 5, 0, 4);
    try std.testing.expectEqual(@as(usize, 0), match.a);
    try std.testing.expectEqual(@as(usize, 0), match.b);
    try std.testing.expectEqual(@as(usize, 2), match.size);
}

test "getCloseMatches" {
    const allocator = std.testing.allocator;
    const possibilities = [_][]const u8{ "apple", "ape", "peach" };
    const matches = try getCloseMatches(allocator, "appel", &possibilities, 2, 0.6);
    defer allocator.free(matches);

    try std.testing.expect(matches.len >= 1);
}

test "Differ" {
    const allocator = std.testing.allocator;
    var d = Differ.init(allocator);

    const a = [_][]const u8{ "one", "two", "three" };
    const b = [_][]const u8{ "one", "tree", "four" };

    const result = try d.compare(&a, &b);
    defer {
        for (result) |line| {
            allocator.free(line);
        }
        allocator.free(result);
    }

    try std.testing.expect(result.len > 0);
}
