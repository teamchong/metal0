//! SQLite3 database dump functionality
//!
//! Mirrors: CPython Lib/sqlite3/dump.py

const std = @import("std");
const dbapi2 = @import("dbapi2.zig");

/// Iterate SQL dump - returns SQL statements to recreate database
pub fn iterdump(connection: *dbapi2.Connection) !std.ArrayList([]const u8) {
    var result = std.ArrayList([]const u8).init(connection.allocator);

    // Get all table names from sqlite_master
    var cur = try connection.cursor();
    defer cur.deinit();

    try cur.execute("SELECT sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY type DESC, name", null);

    for (cur.rows.items) |row| {
        if (row.len > 0) {
            if (row[0]) |sql| {
                try result.append(try connection.allocator.dupe(u8, sql));
            }
        }
    }

    return result;
}
