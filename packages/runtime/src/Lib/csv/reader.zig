//! CSV reader implementations
//!
//! Provides Reader and DictReader classes for reading CSV data.
//!
//! Mirrors: CPython Lib/csv.py

const std = @import("std");
const types = @import("types.zig");
const Dialect = types.Dialect;

// ============================================================================
// Reader - CSV reader
// ============================================================================

/// CSV reader that iterates over lines
pub const Reader = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    source: []const u8,
    dialect: Dialect,
    line_number: usize = 0,
    pos: usize = 0,
    field_names: ?[][]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, source: []const u8, dialect: Dialect) Self {
        return .{
            .allocator = allocator,
            .source = source,
            .dialect = dialect,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.field_names) |names| {
            self.allocator.free(names);
        }
    }

    /// Read the next row
    pub fn next(self: *Self) !?[][]const u8 {
        if (self.pos >= self.source.len) {
            return null;
        }

        var fields = std.ArrayList([]const u8).init(self.allocator);
        errdefer {
            for (fields.items) |field| {
                self.allocator.free(field);
            }
            fields.deinit();
        }

        var in_quoted = false;
        var field_start = self.pos;
        var field_buf = std.ArrayList(u8).init(self.allocator);
        defer field_buf.deinit();

        while (self.pos < self.source.len) {
            const c = self.source[self.pos];

            if (in_quoted) {
                if (c == self.dialect.quotechar) {
                    // Check for doubled quote
                    if (self.dialect.doublequote and self.pos + 1 < self.source.len and
                        self.source[self.pos + 1] == self.dialect.quotechar)
                    {
                        try field_buf.append(c);
                        self.pos += 2;
                        continue;
                    }
                    in_quoted = false;
                    self.pos += 1;
                    continue;
                }
                try field_buf.append(c);
                self.pos += 1;
            } else {
                if (c == self.dialect.quotechar) {
                    in_quoted = true;
                    self.pos += 1;
                    continue;
                }

                if (c == self.dialect.delimiter) {
                    // End of field
                    const field_copy = try self.allocator.dupe(u8, field_buf.items);
                    try fields.append(field_copy);
                    field_buf.clearRetainingCapacity();
                    field_start = self.pos + 1;
                    self.pos += 1;
                    continue;
                }

                // Check for line terminator
                if (self.isLineTerminator()) {
                    const field_copy = try self.allocator.dupe(u8, field_buf.items);
                    try fields.append(field_copy);
                    self.skipLineTerminator();
                    self.line_number += 1;
                    return try fields.toOwnedSlice();
                }

                // Skip initial space if configured
                if (self.dialect.skipinitialspace and c == ' ' and field_buf.items.len == 0) {
                    self.pos += 1;
                    continue;
                }

                try field_buf.append(c);
                self.pos += 1;
            }
        }

        // End of source - return final field if any
        if (field_buf.items.len > 0 or fields.items.len > 0) {
            const field_copy = try self.allocator.dupe(u8, field_buf.items);
            try fields.append(field_copy);
            self.line_number += 1;
            return try fields.toOwnedSlice();
        }

        return null;
    }

    fn isLineTerminator(self: *Self) bool {
        if (self.pos >= self.source.len) return false;
        const term = self.dialect.lineterminator;
        if (self.pos + term.len > self.source.len) {
            // Check for just \n or \r
            return self.source[self.pos] == '\n' or self.source[self.pos] == '\r';
        }
        return std.mem.eql(u8, self.source[self.pos .. self.pos + term.len], term);
    }

    fn skipLineTerminator(self: *Self) void {
        if (self.pos >= self.source.len) return;
        // Handle \r\n, \n, or \r
        if (self.source[self.pos] == '\r') {
            self.pos += 1;
            if (self.pos < self.source.len and self.source[self.pos] == '\n') {
                self.pos += 1;
            }
        } else if (self.source[self.pos] == '\n') {
            self.pos += 1;
        }
    }

    /// Read all rows
    pub fn readAll(self: *Self) ![][]const []const u8 {
        var rows = std.ArrayList([][]const u8).init(self.allocator);
        errdefer {
            for (rows.items) |row| {
                for (row) |field| {
                    self.allocator.free(field);
                }
                self.allocator.free(row);
            }
            rows.deinit();
        }

        while (try self.next()) |row| {
            // Cast to proper type
            const typed_row: [][]const u8 = @ptrCast(row);
            try rows.append(typed_row);
        }

        return rows.toOwnedSlice();
    }
};

// ============================================================================
// DictReader - CSV reader with dictionary rows
// ============================================================================

/// CSV reader that returns rows as key-value pairs
pub const DictReader = struct {
    const Self = @This();

    reader: Reader,
    fieldnames: ?[][]const u8 = null,
    restkey: ?[]const u8 = null,
    restval: ?[]const u8 = null,
    header_read: bool = false,

    pub fn init(
        allocator: std.mem.Allocator,
        source: []const u8,
        dialect: Dialect,
        fieldnames: ?[][]const u8,
    ) Self {
        return .{
            .reader = Reader.init(allocator, source, dialect),
            .fieldnames = fieldnames,
        };
    }

    pub fn deinit(self: *Self) void {
        self.reader.deinit();
    }

    /// Get field names (reads header if needed)
    pub fn getFieldnames(self: *Self) !?[][]const u8 {
        if (self.fieldnames != null) {
            return self.fieldnames;
        }

        if (!self.header_read) {
            self.fieldnames = try self.reader.next();
            self.header_read = true;
        }

        return self.fieldnames;
    }

    /// Read next row as dictionary (represented as parallel arrays)
    pub fn next(self: *Self) !?struct { keys: [][]const u8, values: [][]const u8 } {
        const names = try self.getFieldnames() orelse return null;

        const row = try self.reader.next() orelse return null;

        return .{ .keys = names, .values = row };
    }
};

// ============================================================================
// Convenience Functions
// ============================================================================

/// Create a reader for CSV data
pub fn reader(allocator: std.mem.Allocator, data: []const u8) Reader {
    return Reader.init(allocator, data, Dialect.excel);
}

/// Create a DictReader
pub fn dictReader(
    allocator: std.mem.Allocator,
    data: []const u8,
    fieldnames: ?[][]const u8,
) DictReader {
    return DictReader.init(allocator, data, Dialect.excel, fieldnames);
}

// ============================================================================
// Tests
// ============================================================================

test "Reader basic" {
    const allocator = std.testing.allocator;

    const csv_data = "a,b,c\n1,2,3\n4,5,6";
    var r = Reader.init(allocator, csv_data, Dialect.excel);
    defer r.deinit();

    const row1 = try r.next();
    try std.testing.expect(row1 != null);
    try std.testing.expectEqual(@as(usize, 3), row1.?.len);
    try std.testing.expectEqualStrings("a", row1.?[0]);
    try std.testing.expectEqualStrings("b", row1.?[1]);
    try std.testing.expectEqualStrings("c", row1.?[2]);

    // Free row1
    for (row1.?) |field| allocator.free(field);
    allocator.free(row1.?);

    const row2 = try r.next();
    try std.testing.expect(row2 != null);
    try std.testing.expectEqualStrings("1", row2.?[0]);
    try std.testing.expectEqualStrings("2", row2.?[1]);
    try std.testing.expectEqualStrings("3", row2.?[2]);

    for (row2.?) |field| allocator.free(field);
    allocator.free(row2.?);

    const row3 = try r.next();
    try std.testing.expect(row3 != null);
    for (row3.?) |field| allocator.free(field);
    allocator.free(row3.?);

    const row4 = try r.next();
    try std.testing.expect(row4 == null);
}

test "Reader quoted fields" {
    const allocator = std.testing.allocator;

    const csv_data = "\"hello, world\",\"with \"\"quotes\"\"\"\n";
    var r = Reader.init(allocator, csv_data, Dialect.excel);
    defer r.deinit();

    const row = try r.next();
    try std.testing.expect(row != null);
    try std.testing.expectEqual(@as(usize, 2), row.?.len);
    try std.testing.expectEqualStrings("hello, world", row.?[0]);
    try std.testing.expectEqualStrings("with \"quotes\"", row.?[1]);

    for (row.?) |field| allocator.free(field);
    allocator.free(row.?);
}
