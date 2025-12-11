//! CSV format detection
//!
//! Provides Sniffer class for detecting CSV dialect from sample data.
//!
//! Mirrors: CPython Lib/csv.py

const std = @import("std");
const types = @import("types.zig");
const Dialect = types.Dialect;

// ============================================================================
// Sniffer - Detect CSV format
// ============================================================================

/// Sniff the dialect of a CSV sample
pub const Sniffer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    delimiters: []const u8,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .delimiters = ",\t;:|",
        };
    }

    /// Detect the delimiter used in the sample
    pub fn sniff(self: *Self, sample: []const u8) !Dialect {
        var dialect = Dialect{};

        // Count occurrences of each potential delimiter
        var best_count: usize = 0;
        var best_delim: u8 = ',';

        for (self.delimiters) |delim| {
            var count: usize = 0;
            for (sample) |c| {
                if (c == delim) count += 1;
            }
            if (count > best_count) {
                best_count = count;
                best_delim = delim;
            }
        }

        dialect.delimiter = best_delim;
        return dialect;
    }

    /// Check if a sample has a header
    pub fn hasHeader(self: *Self, sample: []const u8) bool {
        _ = self;
        // Simple heuristic: first line has different pattern than rest
        var lines = std.mem.splitSequence(u8, sample, "\n");
        const first_line = lines.next() orelse return false;
        const second_line = lines.next() orelse return false;

        // Check if first line looks like headers (no numbers)
        var first_has_numbers = false;
        var second_has_numbers = false;

        for (first_line) |c| {
            if (c >= '0' and c <= '9') {
                first_has_numbers = true;
                break;
            }
        }

        for (second_line) |c| {
            if (c >= '0' and c <= '9') {
                second_has_numbers = true;
                break;
            }
        }

        // Header likely if first line has no numbers but second does
        return !first_has_numbers and second_has_numbers;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Sniffer" {
    const allocator = std.testing.allocator;

    var s = Sniffer.init(allocator);

    const tab_data = "a\tb\tc\n1\t2\t3";
    const dialect = try s.sniff(tab_data);
    try std.testing.expectEqual(@as(u8, '\t'), dialect.delimiter);
}
