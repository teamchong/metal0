//! CPython source: Lib/csv.py
//!
//! Provides classes for reading and writing tabular data in CSV format.
//!
//! Mirrors: CPython Lib/csv.py

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

/// Quote style constants
pub const QUOTE_MINIMAL = 0;
pub const QUOTE_ALL = 1;
pub const QUOTE_NONNUMERIC = 2;
pub const QUOTE_NONE = 3;
pub const QUOTE_STRINGS = 4;
pub const QUOTE_NOTNULL = 5;

// ============================================================================
// Dialect - CSV format parameters
// ============================================================================

/// Describes the format of a CSV file
pub const Dialect = struct {
    delimiter: u8 = ',',
    quotechar: u8 = '"',
    escapechar: ?u8 = null,
    doublequote: bool = true,
    skipinitialspace: bool = false,
    lineterminator: []const u8 = "\r\n",
    quoting: i32 = QUOTE_MINIMAL,
    strict: bool = false,

    /// Excel dialect
    pub const excel = Dialect{};

    /// Excel with tab delimiter
    pub const excel_tab = Dialect{ .delimiter = '\t' };

    /// Unix dialect (LF line terminator)
    pub const unix_dialect = Dialect{
        .lineterminator = "\n",
        .quoting = QUOTE_ALL,
    };
};

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
            .buffer = std.ArrayList(u8).init(allocator),
            .dialect = dialect,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
    }

    /// Write a row
    pub fn writerow(self: *Self, row: []const []const u8) !void {
        for (row, 0..) |field, i| {
            if (i > 0) {
                try self.buffer.append(self.dialect.delimiter);
            }
            try self.writeField(field);
        }
        try self.buffer.appendSlice(self.dialect.lineterminator);
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
            try self.buffer.append(self.dialect.quotechar);
            for (field) |c| {
                if (c == self.dialect.quotechar) {
                    if (self.dialect.doublequote) {
                        try self.buffer.append(self.dialect.quotechar);
                        try self.buffer.append(self.dialect.quotechar);
                    } else if (self.dialect.escapechar) |esc| {
                        try self.buffer.append(esc);
                        try self.buffer.append(c);
                    }
                } else {
                    try self.buffer.append(c);
                }
            }
            try self.buffer.append(self.dialect.quotechar);
        } else {
            try self.buffer.appendSlice(field);
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
        return self.buffer.toOwnedSlice();
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
// Convenience Functions
// ============================================================================

/// Create a reader for CSV data
pub fn reader(allocator: std.mem.Allocator, data: []const u8) Reader {
    return Reader.init(allocator, data, Dialect.excel);
}

/// Create a writer for CSV output
pub fn writer(allocator: std.mem.Allocator) Writer {
    return Writer.init(allocator, Dialect.excel);
}

/// Create a DictReader
pub fn dictReader(
    allocator: std.mem.Allocator,
    data: []const u8,
    fieldnames: ?[][]const u8,
) DictReader {
    return DictReader.init(allocator, data, Dialect.excel, fieldnames);
}

/// Create a DictWriter
pub fn dictWriter(
    allocator: std.mem.Allocator,
    fieldnames: []const []const u8,
) DictWriter {
    return DictWriter.init(allocator, fieldnames, Dialect.excel);
}

/// Register a dialect (simplified - stores in a map)
var dialects: ?std.StringHashMap(Dialect) = null;

pub fn registerDialect(name: []const u8, dialect: Dialect, allocator: std.mem.Allocator) !void {
    if (dialects == null) {
        dialects = std.StringHashMap(Dialect).init(allocator);
    }
    try dialects.?.put(name, dialect);
}

pub fn getDialect(name: []const u8) ?Dialect {
    if (dialects) |d| {
        return d.get(name);
    }
    // Built-in dialects
    if (std.mem.eql(u8, name, "excel")) return Dialect.excel;
    if (std.mem.eql(u8, name, "excel-tab")) return Dialect.excel_tab;
    if (std.mem.eql(u8, name, "unix")) return Dialect.unix_dialect;
    return null;
}

pub fn unregisterDialect(name: []const u8) void {
    if (dialects) |*d| {
        _ = d.remove(name);
    }
}

pub fn listDialects() []const []const u8 {
    return &[_][]const u8{ "excel", "excel-tab", "unix" };
}

// ============================================================================
// Error types
// ============================================================================

pub const Error = error{
    CsvError,
    InvalidDialect,
    FieldTooLarge,
    UnterminatedQuote,
};

// ============================================================================
// Field size limit
// ============================================================================

var field_size_limit: usize = 128 * 1024; // 128KB default

pub fn getFieldSizeLimit() usize {
    return field_size_limit;
}

pub fn setFieldSizeLimit(new_limit: usize) usize {
    const old = field_size_limit;
    field_size_limit = new_limit;
    return old;
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

test "Sniffer" {
    const allocator = std.testing.allocator;

    var s = Sniffer.init(allocator);

    const tab_data = "a\tb\tc\n1\t2\t3";
    const dialect = try s.sniff(tab_data);
    try std.testing.expectEqual(@as(u8, '\t'), dialect.delimiter);
}

test "Dialect constants" {
    try std.testing.expectEqual(@as(u8, ','), Dialect.excel.delimiter);
    try std.testing.expectEqual(@as(u8, '\t'), Dialect.excel_tab.delimiter);
    try std.testing.expectEqualStrings("\n", Dialect.unix_dialect.lineterminator);
}

test "constants" {
    try std.testing.expectEqual(@as(i32, 0), QUOTE_MINIMAL);
    try std.testing.expectEqual(@as(i32, 1), QUOTE_ALL);
    try std.testing.expectEqual(@as(i32, 3), QUOTE_NONE);
}
