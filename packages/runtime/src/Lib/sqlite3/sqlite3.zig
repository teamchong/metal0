//! Python 'sqlite3' module - SQLite database interface
//!
//! Provides a Python DB-API 2.0 interface to SQLite databases.
//!
//! Mirrors: CPython Lib/sqlite3/__init__.py
//!
//! This is the main entry point that re-exports all submodules.

const std = @import("std");

// Re-export all submodules
pub const errors = @import("errors.zig");
pub const types = @import("types.zig");
pub const blob = @import("blob.zig");
pub const dbapi2 = @import("dbapi2.zig");
pub const dump = @import("dump.zig");

// ============================================================================
// SQLite3 C API Bindings
// ============================================================================

const c = @cImport({
    @cInclude("vendor/sqlite3/sqlite3.h");
});

// ============================================================================
// Module-level Constants
// ============================================================================

/// SQLite version (from C library)
pub const sqlite_version = c.SQLITE_VERSION;
pub const sqlite_version_info = .{ c.SQLITE_VERSION_NUMBER / 1000000, (c.SQLITE_VERSION_NUMBER / 1000) % 1000, c.SQLITE_VERSION_NUMBER % 1000 };

/// API level
pub const apilevel = "2.0";

/// Thread safety level
pub const threadsafety = 1;

/// Parameter style
pub const paramstyle = "qmark";

// ============================================================================
// Type Detection Constants
// ============================================================================

pub const PARSE_DECLTYPES = types.PARSE_DECLTYPES;
pub const PARSE_COLNAMES = types.PARSE_COLNAMES;

// ============================================================================
// Re-export Core Types
// ============================================================================

pub const Connection = dbapi2.Connection;
pub const ConnectionOptions = dbapi2.ConnectionOptions;
pub const Cursor = dbapi2.Cursor;
pub const RowObject = dbapi2.RowObject;
pub const Blob = blob.Blob;

// ============================================================================
// Re-export Errors
// ============================================================================

pub const Error = errors.Error;
pub const Warning = errors.Warning;
pub const InterfaceError = errors.InterfaceError;
pub const DatabaseError = errors.DatabaseError;
pub const DataError = errors.DataError;
pub const OperationalError = errors.OperationalError;
pub const IntegrityError = errors.IntegrityError;
pub const InternalError = errors.InternalError;
pub const ProgrammingError = errors.ProgrammingError;
pub const NotSupportedError = errors.NotSupportedError;

// ============================================================================
// Re-export Module Functions
// ============================================================================

/// Connect to a database
pub const connect = dbapi2.connect;

/// Register adapter and converter functions
pub const registerAdapter = types.registerAdapter;
pub const registerConverter = types.registerConverter;

/// Complete SQL statement check
pub const completeStatement = dbapi2.completeStatement;

/// Enable shared cache mode
pub const enableSharedCache = dbapi2.enableSharedCache;

/// Database dump functionality
pub const iterdump = dump.iterdump;

// ============================================================================
// Re-export Adapters and Converters
// ============================================================================

pub const adapters = types.adapters;
pub const converters = types.converters;
pub const PrepareProtocol = types.PrepareProtocol;

// ============================================================================
// Tests
// ============================================================================

test "Connection init" {
    const allocator = std.testing.allocator;

    var conn = try Connection.init(allocator, ":memory:", .{});
    defer conn.deinit();

    try std.testing.expectEqualStrings(":memory:", conn.database);
    try std.testing.expect(!conn.in_transaction);
}

test "Cursor init" {
    const allocator = std.testing.allocator;

    var conn = try Connection.init(allocator, ":memory:", .{});
    defer conn.deinit();

    var cur = try conn.cursor();
    defer cur.deinit();

    try std.testing.expectEqual(@as(i64, -1), cur.rowcount);
}

test "complete_statement" {
    try std.testing.expect(completeStatement("SELECT * FROM table;"));
    try std.testing.expect(!completeStatement("SELECT * FROM table"));
    try std.testing.expect(!completeStatement("SELECT 'incomplete;"));
    try std.testing.expect(completeStatement("SELECT 'string with ; inside';"));
}

test "module constants" {
    try std.testing.expectEqualStrings("2.0", apilevel);
    try std.testing.expectEqualStrings("qmark", paramstyle);
    try std.testing.expectEqual(@as(i32, 1), threadsafety);
}

test "date converter" {
    const result = try converters.convertDate(std.testing.allocator, "2024-12-06");
    try std.testing.expectEqual(@as(i32, 2024), result.year);
    try std.testing.expectEqual(@as(u8, 12), result.month);
    try std.testing.expectEqual(@as(u8, 6), result.day);
}

test "timestamp converter" {
    const result = try converters.convertTimestamp(std.testing.allocator, "2024-12-06 14:30:00");
    try std.testing.expectEqual(@as(i32, 2024), result.year);
    try std.testing.expectEqual(@as(u8, 14), result.hour);
    try std.testing.expectEqual(@as(u8, 30), result.minute);
}
