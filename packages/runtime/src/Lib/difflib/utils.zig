//! Utility functions for difflib module
//!
//! Provides get_close_matches, unified_diff, context_diff, ndiff, restore

const std = @import("std");
const sequence_matcher = @import("sequence_matcher.zig");
const SequenceMatcher = sequence_matcher.SequenceMatcher;
const differ = @import("differ.zig");
const Differ = differ.Differ;

// ============================================================================
// Module Functions
// ============================================================================

/// Get close matches from a word list
pub fn getCloseMatches(allocator: std.mem.Allocator, word: []const u8, possibilities: []const []const u8, n: usize, cutoff: f64) ![][]const u8 {
    var results: std.ArrayList(struct { score: f64, word: []const u8 }) = .{};
    defer results.deinit(allocator);

    for (possibilities) |p| {
        var sm = SequenceMatcher(u8).init(allocator, word, p);
        defer sm.deinit();
        const score = try sm.ratio();
        if (score >= cutoff) {
            try results.append(allocator, .{ .score = score, .word = p });
        }
    }

    // Sort by score descending
    std.mem.sort(@TypeOf(results.items[0]), results.items, {}, struct {
        fn lessThan(_: void, a: anytype, b: anytype) bool {
            return a.score > b.score;
        }
    }.lessThan);

    // Take top n
    var output: std.ArrayList([]const u8) = .{};
    errdefer output.deinit(allocator);

    const limit = @min(n, results.items.len);
    for (results.items[0..limit]) |item| {
        try output.append(allocator, item.word);
    }

    return output.toOwnedSlice(allocator);
}

/// Generate unified diff
pub fn unifiedDiff(allocator: std.mem.Allocator, a: []const []const u8, b: []const []const u8, fromfile: []const u8, tofile: []const u8, fromfiledate: []const u8, tofiledate: []const u8, n: usize) ![][]u8 {
    var result: std.ArrayList([]u8) = .{};
    errdefer {
        for (result.items) |item| {
            allocator.free(item);
        }
        result.deinit(allocator);
    }

    // Header
    try result.append(allocator, try std.fmt.allocPrint(allocator, "--- {s}\t{s}", .{ fromfile, fromfiledate }));
    try result.append(allocator, try std.fmt.allocPrint(allocator, "+++ {s}\t{s}", .{ tofile, tofiledate }));

    var sm = SequenceMatcher([]const u8).init(allocator, a, b);
    defer sm.deinit();

    const opcodes = try sm.getOpcodes();
    for (opcodes) |op| {
        _ = n;
        switch (op.tag) {
            .replace, .delete, .insert => {
                // Output hunk header
                try result.append(allocator, try std.fmt.allocPrint(allocator, "@@ -{d},{d} +{d},{d} @@", .{
                    op.i1 + 1,
                    op.i2 - op.i1,
                    op.j1 + 1,
                    op.j2 - op.j1,
                }));

                if (op.tag == .replace or op.tag == .delete) {
                    for (a[op.i1..op.i2]) |line| {
                        try result.append(allocator, try std.fmt.allocPrint(allocator, "-{s}", .{line}));
                    }
                }
                if (op.tag == .replace or op.tag == .insert) {
                    for (b[op.j1..op.j2]) |line| {
                        try result.append(allocator, try std.fmt.allocPrint(allocator, "+{s}", .{line}));
                    }
                }
            },
            .equal => {
                for (a[op.i1..op.i2]) |line| {
                    try result.append(allocator, try std.fmt.allocPrint(allocator, " {s}", .{line}));
                }
            },
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Generate context diff
pub fn contextDiff(allocator: std.mem.Allocator, a: []const []const u8, b: []const []const u8, fromfile: []const u8, tofile: []const u8, fromfiledate: []const u8, tofiledate: []const u8, n: usize) ![][]u8 {
    _ = n;

    var result: std.ArrayList([]u8) = .{};
    errdefer {
        for (result.items) |item| {
            allocator.free(item);
        }
        result.deinit(allocator);
    }

    // Header
    try result.append(allocator, try std.fmt.allocPrint(allocator, "*** {s}\t{s}", .{ fromfile, fromfiledate }));
    try result.append(allocator, try std.fmt.allocPrint(allocator, "--- {s}\t{s}", .{ tofile, tofiledate }));

    var sm = SequenceMatcher([]const u8).init(allocator, a, b);
    defer sm.deinit();

    const opcodes = try sm.getOpcodes();
    for (opcodes) |op| {
        switch (op.tag) {
            .replace, .delete => {
                try result.append(allocator, try std.fmt.allocPrint(allocator, "*** {d},{d} ****", .{ op.i1 + 1, op.i2 }));
                for (a[op.i1..op.i2]) |line| {
                    try result.append(allocator, try std.fmt.allocPrint(allocator, "! {s}", .{line}));
                }
            },
            .insert => {
                try result.append(allocator, try std.fmt.allocPrint(allocator, "--- {d},{d} ----", .{ op.j1 + 1, op.j2 }));
                for (b[op.j1..op.j2]) |line| {
                    try result.append(allocator, try std.fmt.allocPrint(allocator, "+ {s}", .{line}));
                }
            },
            .equal => {},
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Generate ndiff (like diff -Dpython)
pub fn ndiff(allocator: std.mem.Allocator, a: []const []const u8, b: []const []const u8) ![][]u8 {
    var d = Differ.init(allocator);
    return d.compare(a, b);
}

/// Restore original sequences from ndiff output
pub fn restore(allocator: std.mem.Allocator, delta: []const []const u8, which: u8) ![][]u8 {
    var result: std.ArrayList([]u8) = .{};
    errdefer result.deinit(allocator);

    for (delta) |line| {
        if (line.len < 2) continue;

        const tag = line[0];
        const rest = line[2..];

        if (which == 1) {
            if (tag == ' ' or tag == '-') {
                try result.append(allocator, try allocator.dupe(u8, rest));
            }
        } else {
            if (tag == ' ' or tag == '+') {
                try result.append(allocator, try allocator.dupe(u8, rest));
            }
        }
    }

    return result.toOwnedSlice(allocator);
}
