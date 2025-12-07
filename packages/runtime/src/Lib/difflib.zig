//! CPython source: Lib/difflib.py
//!
//! Provides classes and functions for comparing sequences.
//!
//! Mirrors: CPython Lib/difflib.py

const std = @import("std");

// ============================================================================
// Match
// ============================================================================

/// Represents a matching block
pub const Match = struct {
    a: usize, // Start in sequence a
    b: usize, // Start in sequence b
    size: usize, // Size of the match
};

// ============================================================================
// SequenceMatcher
// ============================================================================

/// Compare sequences of any type
pub fn SequenceMatcher(comptime T: type) type {
    return struct {
        const Self = @This();

        a: []const T,
        b: []const T,
        auto_junk: bool,
        allocator: std.mem.Allocator,
        matching_blocks: ?[]Match,
        opcodes: ?[]Opcode,

        pub const Opcode = struct {
            tag: Tag,
            i1: usize,
            i2: usize,
            j1: usize,
            j2: usize,

            pub const Tag = enum {
                replace,
                delete,
                insert,
                equal,
            };
        };

        pub fn init(allocator: std.mem.Allocator, a: []const T, b: []const T) Self {
            return .{
                .a = a,
                .b = b,
                .auto_junk = true,
                .allocator = allocator,
                .matching_blocks = null,
                .opcodes = null,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.matching_blocks) |blocks| {
                self.allocator.free(blocks);
            }
            if (self.opcodes) |ops| {
                self.allocator.free(ops);
            }
        }

        /// Set the sequences to compare
        pub fn setSeqs(self: *Self, a: []const T, b: []const T) void {
            self.a = a;
            self.b = b;
            if (self.matching_blocks) |blocks| {
                self.allocator.free(blocks);
                self.matching_blocks = null;
            }
            if (self.opcodes) |ops| {
                self.allocator.free(ops);
                self.opcodes = null;
            }
        }

        /// Set sequence a
        pub fn setSeq1(self: *Self, a: []const T) void {
            self.a = a;
            if (self.matching_blocks) |blocks| {
                self.allocator.free(blocks);
                self.matching_blocks = null;
            }
        }

        /// Set sequence b
        pub fn setSeq2(self: *Self, b: []const T) void {
            self.b = b;
            if (self.matching_blocks) |blocks| {
                self.allocator.free(blocks);
                self.matching_blocks = null;
            }
        }

        /// Find longest matching block in a[alo:ahi] and b[blo:bhi]
        pub fn findLongestMatch(self: *Self, alo: usize, ahi: usize, blo: usize, bhi: usize) Match {
            var best_i = alo;
            var best_j = blo;
            var best_size: usize = 0;

            // Simple O(n*m) algorithm
            var i = alo;
            while (i < ahi) : (i += 1) {
                var j = blo;
                while (j < bhi) : (j += 1) {
                    if (self.elemEql(self.a[i], self.b[j])) {
                        var k: usize = 1;
                        while (i + k < ahi and j + k < bhi and
                            self.elemEql(self.a[i + k], self.b[j + k]))
                        {
                            k += 1;
                        }
                        if (k > best_size) {
                            best_i = i;
                            best_j = j;
                            best_size = k;
                        }
                    }
                }
            }

            return Match{ .a = best_i, .b = best_j, .size = best_size };
        }

        fn elemEql(self: *Self, a: T, b: T) bool {
            _ = self;
            if (T == u8) {
                return a == b;
            } else if (T == []const u8) {
                return std.mem.eql(u8, a, b);
            } else {
                return a == b;
            }
        }

        /// Get matching blocks
        pub fn getMatchingBlocks(self: *Self) ![]Match {
            if (self.matching_blocks) |blocks| {
                return blocks;
            }

            var blocks = std.ArrayList(Match).init(self.allocator);
            errdefer blocks.deinit();

            try self.helper(&blocks, 0, self.a.len, 0, self.b.len);

            // Add sentinel
            try blocks.append(Match{ .a = self.a.len, .b = self.b.len, .size = 0 });

            self.matching_blocks = try blocks.toOwnedSlice();
            return self.matching_blocks.?;
        }

        fn helper(self: *Self, blocks: *std.ArrayList(Match), alo: usize, ahi: usize, blo: usize, bhi: usize) !void {
            const match = self.findLongestMatch(alo, ahi, blo, bhi);
            if (match.size > 0) {
                if (alo < match.a and blo < match.b) {
                    try self.helper(blocks, alo, match.a, blo, match.b);
                }
                try blocks.append(match);
                if (match.a + match.size < ahi and match.b + match.size < bhi) {
                    try self.helper(blocks, match.a + match.size, ahi, match.b + match.size, bhi);
                }
            }
        }

        /// Get opcodes describing how to turn a into b
        pub fn getOpcodes(self: *Self) ![]Opcode {
            if (self.opcodes) |ops| {
                return ops;
            }

            var ops = std.ArrayList(Opcode).init(self.allocator);
            errdefer ops.deinit();

            var i: usize = 0;
            var j: usize = 0;

            const blocks = try self.getMatchingBlocks();
            for (blocks) |block| {
                if (i < block.a and j < block.b) {
                    try ops.append(.{
                        .tag = .replace,
                        .i1 = i,
                        .i2 = block.a,
                        .j1 = j,
                        .j2 = block.b,
                    });
                } else if (i < block.a) {
                    try ops.append(.{
                        .tag = .delete,
                        .i1 = i,
                        .i2 = block.a,
                        .j1 = j,
                        .j2 = j,
                    });
                } else if (j < block.b) {
                    try ops.append(.{
                        .tag = .insert,
                        .i1 = i,
                        .i2 = i,
                        .j1 = j,
                        .j2 = block.b,
                    });
                }
                i = block.a + block.size;
                j = block.b + block.size;
                if (block.size > 0) {
                    try ops.append(.{
                        .tag = .equal,
                        .i1 = block.a,
                        .i2 = i,
                        .j1 = block.b,
                        .j2 = j,
                    });
                }
            }

            self.opcodes = try ops.toOwnedSlice();
            return self.opcodes.?;
        }

        /// Compute similarity ratio
        pub fn ratio(self: *Self) !f64 {
            const blocks = try self.getMatchingBlocks();
            var matches: usize = 0;
            for (blocks) |block| {
                matches += block.size;
            }

            const total = self.a.len + self.b.len;
            if (total == 0) return 1.0;

            return @as(f64, @floatFromInt(2 * matches)) / @as(f64, @floatFromInt(total));
        }

        /// Quick ratio (upper bound)
        pub fn quickRatio(self: *Self) f64 {
            _ = self;
            return 1.0; // Simplified
        }

        /// Very quick ratio (upper bound)
        pub fn realQuickRatio(self: *Self) f64 {
            const la = self.a.len;
            const lb = self.b.len;
            if (la + lb == 0) return 1.0;
            return @as(f64, @floatFromInt(2 * @min(la, lb))) / @as(f64, @floatFromInt(la + lb));
        }
    };
}

// ============================================================================
// Differ
// ============================================================================

/// Compare sequences of lines of text
pub const Differ = struct {
    const Self = @This();

    linejunk: ?*const fn ([]const u8) bool,
    charjunk: ?*const fn (u8) bool,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .linejunk = null,
            .charjunk = null,
            .allocator = allocator,
        };
    }

    /// Compare two sequences of lines
    pub fn compare(self: *Self, a: []const []const u8, b: []const []const u8) ![][]u8 {
        var result = std.ArrayList([]u8).init(self.allocator);
        errdefer {
            for (result.items) |item| {
                self.allocator.free(item);
            }
            result.deinit();
        }

        var sm = SequenceMatcher([]const u8).init(self.allocator, a, b);
        defer sm.deinit();

        const opcodes = try sm.getOpcodes();
        for (opcodes) |op| {
            switch (op.tag) {
                .replace => {
                    // Delete from a
                    for (a[op.i1..op.i2]) |line| {
                        const output = try std.fmt.allocPrint(self.allocator, "- {s}", .{line});
                        try result.append(output);
                    }
                    // Insert from b
                    for (b[op.j1..op.j2]) |line| {
                        const output = try std.fmt.allocPrint(self.allocator, "+ {s}", .{line});
                        try result.append(output);
                    }
                },
                .delete => {
                    for (a[op.i1..op.i2]) |line| {
                        const output = try std.fmt.allocPrint(self.allocator, "- {s}", .{line});
                        try result.append(output);
                    }
                },
                .insert => {
                    for (b[op.j1..op.j2]) |line| {
                        const output = try std.fmt.allocPrint(self.allocator, "+ {s}", .{line});
                        try result.append(output);
                    }
                },
                .equal => {
                    for (a[op.i1..op.i2]) |line| {
                        const output = try std.fmt.allocPrint(self.allocator, "  {s}", .{line});
                        try result.append(output);
                    }
                },
            }
        }

        return result.toOwnedSlice();
    }
};

// ============================================================================
// Module Functions
// ============================================================================

/// Get close matches from a word list
pub fn getCloseMatches(allocator: std.mem.Allocator, word: []const u8, possibilities: []const []const u8, n: usize, cutoff: f64) ![][]const u8 {
    var results = std.ArrayList(struct { score: f64, word: []const u8 }).init(allocator);
    defer results.deinit();

    for (possibilities) |p| {
        var sm = SequenceMatcher(u8).init(allocator, word, p);
        defer sm.deinit();
        const score = try sm.ratio();
        if (score >= cutoff) {
            try results.append(.{ .score = score, .word = p });
        }
    }

    // Sort by score descending
    std.mem.sort(@TypeOf(results.items[0]), results.items, {}, struct {
        fn lessThan(_: void, a: anytype, b: anytype) bool {
            return a.score > b.score;
        }
    }.lessThan);

    // Take top n
    var output = std.ArrayList([]const u8).init(allocator);
    errdefer output.deinit();

    const limit = @min(n, results.items.len);
    for (results.items[0..limit]) |item| {
        try output.append(item.word);
    }

    return output.toOwnedSlice();
}

/// Generate unified diff
pub fn unifiedDiff(allocator: std.mem.Allocator, a: []const []const u8, b: []const []const u8, fromfile: []const u8, tofile: []const u8, fromfiledate: []const u8, tofiledate: []const u8, n: usize) ![][]u8 {
    var result = std.ArrayList([]u8).init(allocator);
    errdefer {
        for (result.items) |item| {
            allocator.free(item);
        }
        result.deinit();
    }

    // Header
    try result.append(try std.fmt.allocPrint(allocator, "--- {s}\t{s}", .{ fromfile, fromfiledate }));
    try result.append(try std.fmt.allocPrint(allocator, "+++ {s}\t{s}", .{ tofile, tofiledate }));

    var sm = SequenceMatcher([]const u8).init(allocator, a, b);
    defer sm.deinit();

    const opcodes = try sm.getOpcodes();
    for (opcodes) |op| {
        _ = n;
        switch (op.tag) {
            .replace, .delete, .insert => {
                // Output hunk header
                try result.append(try std.fmt.allocPrint(allocator, "@@ -{d},{d} +{d},{d} @@", .{
                    op.i1 + 1,
                    op.i2 - op.i1,
                    op.j1 + 1,
                    op.j2 - op.j1,
                }));

                if (op.tag == .replace or op.tag == .delete) {
                    for (a[op.i1..op.i2]) |line| {
                        try result.append(try std.fmt.allocPrint(allocator, "-{s}", .{line}));
                    }
                }
                if (op.tag == .replace or op.tag == .insert) {
                    for (b[op.j1..op.j2]) |line| {
                        try result.append(try std.fmt.allocPrint(allocator, "+{s}", .{line}));
                    }
                }
            },
            .equal => {
                for (a[op.i1..op.i2]) |line| {
                    try result.append(try std.fmt.allocPrint(allocator, " {s}", .{line}));
                }
            },
        }
    }

    return result.toOwnedSlice();
}

/// Generate context diff
pub fn contextDiff(allocator: std.mem.Allocator, a: []const []const u8, b: []const []const u8, fromfile: []const u8, tofile: []const u8, fromfiledate: []const u8, tofiledate: []const u8, n: usize) ![][]u8 {
    _ = n;

    var result = std.ArrayList([]u8).init(allocator);
    errdefer {
        for (result.items) |item| {
            allocator.free(item);
        }
        result.deinit();
    }

    // Header
    try result.append(try std.fmt.allocPrint(allocator, "*** {s}\t{s}", .{ fromfile, fromfiledate }));
    try result.append(try std.fmt.allocPrint(allocator, "--- {s}\t{s}", .{ tofile, tofiledate }));

    var sm = SequenceMatcher([]const u8).init(allocator, a, b);
    defer sm.deinit();

    const opcodes = try sm.getOpcodes();
    for (opcodes) |op| {
        switch (op.tag) {
            .replace, .delete => {
                try result.append(try std.fmt.allocPrint(allocator, "*** {d},{d} ****", .{ op.i1 + 1, op.i2 }));
                for (a[op.i1..op.i2]) |line| {
                    try result.append(try std.fmt.allocPrint(allocator, "! {s}", .{line}));
                }
            },
            .insert => {
                try result.append(try std.fmt.allocPrint(allocator, "--- {d},{d} ----", .{ op.j1 + 1, op.j2 }));
                for (b[op.j1..op.j2]) |line| {
                    try result.append(try std.fmt.allocPrint(allocator, "+ {s}", .{line}));
                }
            },
            .equal => {},
        }
    }

    return result.toOwnedSlice();
}

/// Generate ndiff (like diff -Dpython)
pub fn ndiff(allocator: std.mem.Allocator, a: []const []const u8, b: []const []const u8) ![][]u8 {
    var differ = Differ.init(allocator);
    return differ.compare(a, b);
}

/// Restore original sequences from ndiff output
pub fn restore(allocator: std.mem.Allocator, delta: []const []const u8, which: u8) ![][]u8 {
    var result = std.ArrayList([]u8).init(allocator);
    errdefer result.deinit();

    for (delta) |line| {
        if (line.len < 2) continue;

        const tag = line[0];
        const rest = line[2..];

        if (which == 1) {
            if (tag == ' ' or tag == '-') {
                try result.append(try allocator.dupe(u8, rest));
            }
        } else {
            if (tag == ' ' or tag == '+') {
                try result.append(try allocator.dupe(u8, rest));
            }
        }
    }

    return result.toOwnedSlice();
}

// ============================================================================
// HtmlDiff
// ============================================================================

/// Generate side-by-side HTML diff
pub const HtmlDiff = struct {
    const Self = @This();

    tabsize: usize,
    wrapcolumn: ?usize,
    linejunk: ?*const fn ([]const u8) bool,
    charjunk: ?*const fn (u8) bool,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .tabsize = 8,
            .wrapcolumn = null,
            .linejunk = null,
            .charjunk = null,
            .allocator = allocator,
        };
    }

    pub fn makeFile(self: *Self, fromlines: []const []const u8, tolines: []const []const u8, fromdesc: []const u8, todesc: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        try result.appendSlice(
            \\<!DOCTYPE html>
            \\<html>
            \\<head>
            \\<style>
            \\.diff_header { background-color: #e0e0e0; }
            \\.diff_next { background-color: #c0c0c0; }
            \\.diff_add { background-color: #aaffaa; }
            \\.diff_chg { background-color: #ffff77; }
            \\.diff_sub { background-color: #ffaaaa; }
            \\</style>
            \\</head>
            \\<body>
            \\
        );

        const table = try self.makeTable(fromlines, tolines, fromdesc, todesc);
        defer self.allocator.free(table);
        try result.appendSlice(table);

        try result.appendSlice(
            \\</body>
            \\</html>
        );

        return result.toOwnedSlice();
    }

    pub fn makeTable(self: *Self, fromlines: []const []const u8, tolines: []const []const u8, fromdesc: []const u8, todesc: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        try result.appendSlice("<table>\n<tr><th>");
        try result.appendSlice(fromdesc);
        try result.appendSlice("</th><th>");
        try result.appendSlice(todesc);
        try result.appendSlice("</th></tr>\n");

        var sm = SequenceMatcher([]const u8).init(self.allocator, fromlines, tolines);
        defer sm.deinit();

        const opcodes = try sm.getOpcodes();
        for (opcodes) |op| {
            const maxlines = @max(op.i2 - op.i1, op.j2 - op.j1);
            var i: usize = 0;
            while (i < maxlines) : (i += 1) {
                try result.appendSlice("<tr>");

                // From column
                if (op.i1 + i < op.i2) {
                    const class = switch (op.tag) {
                        .replace => "diff_chg",
                        .delete => "diff_sub",
                        else => "",
                    };
                    try result.appendSlice("<td class=\"");
                    try result.appendSlice(class);
                    try result.appendSlice("\">");
                    try result.appendSlice(fromlines[op.i1 + i]);
                    try result.appendSlice("</td>");
                } else {
                    try result.appendSlice("<td></td>");
                }

                // To column
                if (op.j1 + i < op.j2) {
                    const class = switch (op.tag) {
                        .replace => "diff_chg",
                        .insert => "diff_add",
                        else => "",
                    };
                    try result.appendSlice("<td class=\"");
                    try result.appendSlice(class);
                    try result.appendSlice("\">");
                    try result.appendSlice(tolines[op.j1 + i]);
                    try result.appendSlice("</td>");
                } else {
                    try result.appendSlice("<td></td>");
                }

                try result.appendSlice("</tr>\n");
            }
        }

        try result.appendSlice("</table>\n");

        return result.toOwnedSlice();
    }
};

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
    var differ = Differ.init(allocator);

    const a = [_][]const u8{ "one", "two", "three" };
    const b = [_][]const u8{ "one", "tree", "four" };

    const result = try differ.compare(&a, &b);
    defer {
        for (result) |line| {
            allocator.free(line);
        }
        allocator.free(result);
    }

    try std.testing.expect(result.len > 0);
}
