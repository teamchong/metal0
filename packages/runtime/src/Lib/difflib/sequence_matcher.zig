//! SequenceMatcher - compare pairs of sequences of any type
//!
//! Provides the core diff algorithm and similarity metrics

const std = @import("std");
const types = @import("types.zig");
const Match = types.Match;
const Opcode = types.Opcode;

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

            var blocks: std.ArrayList(Match) = .{};
            errdefer blocks.deinit(self.allocator);

            try self.helper(&blocks, 0, self.a.len, 0, self.b.len);

            // Add sentinel
            try blocks.append(self.allocator, Match{ .a = self.a.len, .b = self.b.len, .size = 0 });

            self.matching_blocks = try blocks.toOwnedSlice(self.allocator);
            return self.matching_blocks.?;
        }

        fn helper(self: *Self, blocks: *std.ArrayList(Match), alo: usize, ahi: usize, blo: usize, bhi: usize) !void {
            const match = self.findLongestMatch(alo, ahi, blo, bhi);
            if (match.size > 0) {
                if (alo < match.a and blo < match.b) {
                    try self.helper(blocks, alo, match.a, blo, match.b);
                }
                try blocks.append(self.allocator, match);
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

            var ops: std.ArrayList(Opcode) = .{};
            errdefer ops.deinit(self.allocator);

            var i: usize = 0;
            var j: usize = 0;

            const blocks = try self.getMatchingBlocks();
            for (blocks) |block| {
                if (i < block.a and j < block.b) {
                    try ops.append(self.allocator, .{
                        .tag = .replace,
                        .i1 = i,
                        .i2 = block.a,
                        .j1 = j,
                        .j2 = block.b,
                    });
                } else if (i < block.a) {
                    try ops.append(self.allocator, .{
                        .tag = .delete,
                        .i1 = i,
                        .i2 = block.a,
                        .j1 = j,
                        .j2 = j,
                    });
                } else if (j < block.b) {
                    try ops.append(self.allocator, .{
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
                    try ops.append(self.allocator, .{
                        .tag = .equal,
                        .i1 = block.a,
                        .i2 = i,
                        .j1 = block.b,
                        .j2 = j,
                    });
                }
            }

            self.opcodes = try ops.toOwnedSlice(self.allocator);
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
