//! Differ - compare sequences of lines of text
//!
//! Produces human-readable diffs with +/- prefixes

const std = @import("std");
const sequence_matcher = @import("sequence_matcher.zig");
const SequenceMatcher = sequence_matcher.SequenceMatcher;

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
        var result: std.ArrayList([]u8) = .{};
        errdefer {
            for (result.items) |item| {
                self.allocator.free(item);
            }
            result.deinit(self.allocator);
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
                        try result.append(self.allocator, output);
                    }
                    // Insert from b
                    for (b[op.j1..op.j2]) |line| {
                        const output = try std.fmt.allocPrint(self.allocator, "+ {s}", .{line});
                        try result.append(self.allocator, output);
                    }
                },
                .delete => {
                    for (a[op.i1..op.i2]) |line| {
                        const output = try std.fmt.allocPrint(self.allocator, "- {s}", .{line});
                        try result.append(self.allocator, output);
                    }
                },
                .insert => {
                    for (b[op.j1..op.j2]) |line| {
                        const output = try std.fmt.allocPrint(self.allocator, "+ {s}", .{line});
                        try result.append(self.allocator, output);
                    }
                },
                .equal => {
                    for (a[op.i1..op.i2]) |line| {
                        const output = try std.fmt.allocPrint(self.allocator, "  {s}", .{line});
                        try result.append(self.allocator, output);
                    }
                },
            }
        }

        return result.toOwnedSlice(self.allocator);
    }
};
