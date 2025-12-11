//! CSV type definitions and constants
//!
//! Provides Dialect configuration and quoting constants.
//!
//! Mirrors: CPython Lib/csv.py

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

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
// Dialect Registry
// ============================================================================

var dialects: ?hashmap_helper.StringHashMap(Dialect) = null;

pub fn registerDialect(name: []const u8, dialect: Dialect, allocator: std.mem.Allocator) !void {
    if (dialects == null) {
        dialects = hashmap_helper.StringHashMap(Dialect).init(allocator);
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
// Tests
// ============================================================================

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
