//! SQLite3 Blob class for incremental I/O
//!
//! Mirrors: CPython Lib/sqlite3/dbapi2.py (Blob class)

const std = @import("std");
const errors = @import("errors.zig");

// Forward declaration
const Connection = @import("dbapi2.zig").Connection;

const c = @cImport({
    @cInclude("vendor/sqlite3/sqlite3.h");
});

// ============================================================================
// Blob
// ============================================================================

/// Blob object for incremental I/O
pub const Blob = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    connection: *Connection,
    blob: ?*c.sqlite3_blob,
    size: usize,
    position: usize,
    readonly: bool,

    pub fn init(allocator: std.mem.Allocator, connection: *Connection, table: []const u8, column: []const u8, row: i64, readonly: bool) !Self {
        const db = connection.db orelse return error.DatabaseError;

        const table_z = try allocator.dupeZ(u8, table);
        defer allocator.free(table_z);
        const column_z = try allocator.dupeZ(u8, column);
        defer allocator.free(column_z);

        var blob: ?*c.sqlite3_blob = null;
        const flags: c_int = if (readonly) 0 else 1;
        const rc = c.sqlite3_blob_open(db, "main", table_z.ptr, column_z.ptr, row, flags, &blob);
        if (rc != c.SQLITE_OK) return error.DatabaseError;

        const size: usize = @intCast(c.sqlite3_blob_bytes(blob));

        return .{
            .allocator = allocator,
            .connection = connection,
            .blob = blob,
            .size = size,
            .position = 0,
            .readonly = readonly,
        };
    }

    pub fn read(self: *Self, length: ?usize) ![]u8 {
        const blob = self.blob orelse return error.DatabaseError;
        const len = @min(length orelse (self.size - self.position), self.size - self.position);
        if (len == 0) return &[_]u8{};

        var buf = try self.allocator.alloc(u8, len);
        const rc = c.sqlite3_blob_read(blob, buf.ptr, @intCast(len), @intCast(self.position));
        if (rc != c.SQLITE_OK) {
            self.allocator.free(buf);
            return error.DatabaseError;
        }
        self.position += len;
        return buf;
    }

    pub fn write(self: *Self, data: []const u8) !void {
        if (self.readonly) return error.DatabaseError;
        const blob = self.blob orelse return error.DatabaseError;

        const rc = c.sqlite3_blob_write(blob, data.ptr, @intCast(data.len), @intCast(self.position));
        if (rc != c.SQLITE_OK) return error.DatabaseError;
        self.position += data.len;
    }

    pub fn seek(self: *Self, offset: i64, whence: i32) void {
        switch (whence) {
            0 => self.position = @intCast(offset), // SEEK_SET
            1 => self.position = @intCast(@as(i64, @intCast(self.position)) + offset), // SEEK_CUR
            2 => self.position = @intCast(@as(i64, @intCast(self.size)) + offset), // SEEK_END
            else => {},
        }
    }

    pub fn tell(self: *Self) usize {
        return self.position;
    }

    pub fn len(self: *Self) usize {
        return self.size;
    }

    pub fn close(self: *Self) void {
        if (self.blob) |blob| {
            _ = c.sqlite3_blob_close(blob);
            self.blob = null;
        }
    }
};
