//! CSV writer implementations
//!
//! Provides Writer and DictWriter classes for writing CSV data.
//!
//! Mirrors: CPython Lib/csv.py

const std = @import("std");
const types = @import("types.zig");
const Dialect = types.Dialect;
const QUOTE_MINIMAL = types.QUOTE_MINIMAL;
const QUOTE_ALL = types.QUOTE_ALL;
const QUOTE_NONE = types.QUOTE_NONE;

// ============================================================================
// Writer - CSV writer
// ============================================================================

/// CSV writer
pub const Writer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    dialect: Dialect,

    pub fn init(allocator: std.mem.Allocator, dialect: Dialect) Self {
        return .{
            .allocator = allocator,
            .buffer = .{},
            .dialect = dialect,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
    }

    /// Write a row
    pub fn writerow(self: *Self, row: []const []const u8) !void {
        for (row, 0..) |field, i| {
            if (i > 0) {
                try self.buffer.append(self.allocator, self.dialect.delimiter);
            }
            try self.writeField(field);
        }
        try self.buffer.appendSlice(self.allocator, self.dialect.lineterminator);
    }

    /// Write multiple rows
    pub fn writerows(self: *Self, rows: []const []const []const u8) !void {
        for (rows) |row| {
            try self.writerow(row);
        }
    }

    fn writeField(self: *Self, field: []const u8) !void {
        const needs_quoting = self.needsQuoting(field);

        if (needs_quoting or self.dialect.quoting == QUOTE_ALL) {
            try self.buffer.append(self.allocator, self.dialect.quotechar);
            for (field) |c| {
                if (c == self.dialect.quotechar) {
                    if (self.dialect.doublequote) {
                        try self.buffer.append(self.allocator, self.dialect.quotechar);
                        try self.buffer.append(self.allocator, self.dialect.quotechar);
                    } else if (self.dialect.escapechar) |esc| {
                        try self.buffer.append(self.allocator, esc);
                        try self.buffer.append(self.allocator, c);
                    }
                } else {
                    try self.buffer.append(self.allocator, c);
                }
            }
            try self.buffer.append(self.allocator, self.dialect.quotechar);
        } else {
            try self.buffer.appendSlice(self.allocator, field);
        }
    }

    fn needsQuoting(self: *Self, field: []const u8) bool {
        if (self.dialect.quoting == QUOTE_NONE) return false;

        for (field) |c| {
            if (c == self.dialect.delimiter or
                c == self.dialect.quotechar or
                c == '\r' or c == '\n')
            {
                return true;
            }
        }
        return false;
    }

    /// Get the CSV output
    pub fn getOutput(self: *Self) []const u8 {
        return self.buffer.items;
    }

    /// Get output as owned slice
    pub fn toOwnedSlice(self: *Self) ![]u8 {
        return self.buffer.toOwnedSlice(self.allocator);
    }
};

// ============================================================================
// DictWriter - CSV writer with dictionary rows
// ============================================================================

/// CSV writer that accepts dictionary-like input
pub const DictWriter = struct {
    const Self = @This();

    writer: Writer,
    fieldnames: []const []const u8,
    restval: []const u8,
    extrasaction: ExtrasAction,

    pub const ExtrasAction = enum {
        raise,
        ignore,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        fieldnames: []const []const u8,
        dialect: Dialect,
    ) Self {
        return .{
            .writer = Writer.init(allocator, dialect),
            .fieldnames = fieldnames,
            .restval = "",
            .extrasaction = .raise,
        };
    }

    pub fn deinit(self: *Self) void {
        self.writer.deinit();
    }

    /// Write the header row
    pub fn writeheader(self: *Self) !void {
        try self.writer.writerow(self.fieldnames);
    }

    /// Write a row from parallel key/value arrays
    pub fn writerow(self: *Self, keys: []const []const u8, values: []const []const u8) !void {
        var row = try self.writer.allocator.alloc([]const u8, self.fieldnames.len);
        defer self.writer.allocator.free(row);

        // Initialize with restval
        for (row) |*field| {
            field.* = self.restval;
        }

        // Fill in values
        for (keys, values) |key, value| {
            for (self.fieldnames, 0..) |fname, i| {
                if (std.mem.eql(u8, key, fname)) {
                    row[i] = value;
                    break;
                }
            }
        }

        try self.writer.writerow(row);
    }

    /// Get the CSV output
    pub fn getOutput(self: *Self) []const u8 {
        return self.writer.getOutput();
    }
};

// ============================================================================
// Convenience Functions
// ============================================================================

/// Create a writer for CSV output
pub fn writer(allocator: std.mem.Allocator) Writer {
    return Writer.init(allocator, Dialect.excel);
}

/// Create a DictWriter
pub fn dictWriter(
    allocator: std.mem.Allocator,
    fieldnames: []const []const u8,
) DictWriter {
    return DictWriter.init(allocator, fieldnames, Dialect.excel);
}

// ============================================================================
// Tests
// ============================================================================

test "Writer basic" {
    const allocator = std.testing.allocator;

    var w = Writer.init(allocator, Dialect.excel);
    defer w.deinit();

    try w.writerow(&[_][]const u8{ "a", "b", "c" });
    try w.writerow(&[_][]const u8{ "1", "2", "3" });

    const output = w.getOutput();
    try std.testing.expectEqualStrings("a,b,c\r\n1,2,3\r\n", output);
}

test "Writer quoted" {
    const allocator = std.testing.allocator;

    var w = Writer.init(allocator, Dialect.excel);
    defer w.deinit();

    try w.writerow(&[_][]const u8{ "hello, world", "normal" });

    const output = w.getOutput();
    try std.testing.expectEqualStrings("\"hello, world\",normal\r\n", output);
}
