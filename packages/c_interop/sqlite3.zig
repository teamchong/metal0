/// SQLite3 Database Interface
/// Python-compatible API for sqlite3 module
const std = @import("std");

const c = @cImport({
    @cInclude("sqlite3.h");
});

/// Row - a single database row with column values
pub const Row = struct {
    values: [][]const u8,
    column_names: [][]const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Row) void {
        for (self.values) |v| {
            self.allocator.free(v);
        }
        self.allocator.free(self.values);
        for (self.column_names) |n| {
            self.allocator.free(n);
        }
        self.allocator.free(self.column_names);
    }

    /// Get value by column index
    pub fn get(self: *const Row, index: usize) ?[]const u8 {
        if (index >= self.values.len) return null;
        return self.values[index];
    }

    /// Get value by column name
    pub fn getByName(self: *const Row, name: []const u8) ?[]const u8 {
        for (self.column_names, 0..) |col_name, i| {
            if (std.mem.eql(u8, col_name, name)) {
                return self.values[i];
            }
        }
        return null;
    }

    /// Format row as tuple string for Python compatibility
    pub fn format(self: *const Row, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.writeByte('(');
        for (self.values, 0..) |v, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("'{s}'", .{v});
        }
        try writer.writeByte(')');
    }

    /// Print row in Python tuple format
    pub fn print(self: *const Row) void {
        std.debug.print("(", .{});
        for (self.values, 0..) |v, i| {
            if (i > 0) std.debug.print(", ", .{});
            std.debug.print("'{s}'", .{v});
        }
        std.debug.print(")", .{});
    }
};

/// Cursor - executes queries and fetches results
pub const Cursor = struct {
    conn: *Connection,
    stmt: ?*c.sqlite3_stmt,
    allocator: std.mem.Allocator,
    description: ?[][]const u8,
    rowcount: i64,
    lastrowid: i64,

    pub fn init(conn: *Connection, allocator: std.mem.Allocator) Cursor {
        return Cursor{
            .conn = conn,
            .stmt = null,
            .allocator = allocator,
            .description = null,
            .rowcount = -1,
            .lastrowid = 0,
        };
    }

    pub fn deinit(self: *Cursor) void {
        if (self.stmt) |stmt| {
            _ = c.sqlite3_finalize(stmt);
        }
        if (self.description) |desc| {
            for (desc) |col| {
                self.allocator.free(col);
            }
            self.allocator.free(desc);
        }
    }

    /// Execute a SQL statement
    pub fn execute(self: *Cursor, sql: []const u8) !void {
        // Finalize any existing statement
        if (self.stmt) |stmt| {
            _ = c.sqlite3_finalize(stmt);
            self.stmt = null;
        }

        // Clear description
        if (self.description) |desc| {
            for (desc) |col| {
                self.allocator.free(col);
            }
            self.allocator.free(desc);
            self.description = null;
        }

        // Prepare the statement
        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(
            self.conn.db,
            sql.ptr,
            @intCast(sql.len),
            &stmt,
            null,
        );
        if (rc != c.SQLITE_OK) {
            return error.PrepareFailed;
        }

        self.stmt = stmt;

        // Get column info for description
        const col_count = c.sqlite3_column_count(stmt);
        if (col_count > 0) {
            const desc = try self.allocator.alloc([]const u8, @intCast(col_count));
            var i: c_int = 0;
            while (i < col_count) : (i += 1) {
                const name = c.sqlite3_column_name(stmt, i);
                if (name) |n| {
                    desc[@intCast(i)] = try self.allocator.dupe(u8, std.mem.span(n));
                } else {
                    desc[@intCast(i)] = try self.allocator.dupe(u8, "");
                }
            }
            self.description = desc;
        }

        // For non-SELECT statements, step immediately
        if (col_count == 0) {
            const step_rc = c.sqlite3_step(stmt.?);
            if (step_rc != c.SQLITE_DONE and step_rc != c.SQLITE_ROW) {
                return error.ExecuteFailed;
            }
            self.rowcount = c.sqlite3_changes(self.conn.db);
            self.lastrowid = c.sqlite3_last_insert_rowid(self.conn.db);
        }
    }

    /// Execute with parameters (? placeholders)
    pub fn executeWithParams(self: *Cursor, sql: []const u8, params: []const []const u8) !void {
        try self.execute(sql);

        if (self.stmt) |stmt| {
            // Bind parameters
            for (params, 0..) |param, i| {
                const idx: c_int = @intCast(i + 1); // SQLite params are 1-indexed
                const rc = c.sqlite3_bind_text(
                    stmt,
                    idx,
                    param.ptr,
                    @intCast(param.len),
                    c.SQLITE_TRANSIENT,
                );
                if (rc != c.SQLITE_OK) {
                    return error.BindFailed;
                }
            }
        }
    }

    /// Execute many statements with different parameter sets
    pub fn executemany(self: *Cursor, sql: []const u8, params_list: []const []const []const u8) !void {
        for (params_list) |params| {
            try self.executeWithParams(sql, params);
            // Step for each execution
            if (self.stmt) |stmt| {
                const rc = c.sqlite3_step(stmt);
                if (rc != c.SQLITE_DONE and rc != c.SQLITE_ROW) {
                    return error.ExecuteFailed;
                }
                _ = c.sqlite3_reset(stmt);
            }
        }
    }

    /// Fetch one row
    pub fn fetchone(self: *Cursor) !?Row {
        const stmt = self.stmt orelse return null;

        const rc = c.sqlite3_step(stmt);
        if (rc == c.SQLITE_DONE) {
            return null;
        }
        if (rc != c.SQLITE_ROW) {
            return error.FetchFailed;
        }

        const col_count: usize = @intCast(c.sqlite3_column_count(stmt));
        const values = try self.allocator.alloc([]const u8, col_count);
        errdefer self.allocator.free(values);

        var i: c_int = 0;
        while (i < col_count) : (i += 1) {
            const text = c.sqlite3_column_text(stmt, i);
            if (text) |t| {
                const len: usize = @intCast(c.sqlite3_column_bytes(stmt, i));
                values[@intCast(i)] = try self.allocator.dupe(u8, t[0..len]);
            } else {
                values[@intCast(i)] = try self.allocator.dupe(u8, "");
            }
        }

        // Copy column names
        const names = try self.allocator.alloc([]const u8, col_count);
        if (self.description) |desc| {
            for (desc, 0..) |name, idx| {
                names[idx] = try self.allocator.dupe(u8, name);
            }
        }

        return Row{
            .values = values,
            .column_names = names,
            .allocator = self.allocator,
        };
    }

    /// Fetch all remaining rows
    pub fn fetchall(self: *Cursor) ![]Row {
        var rows = std.ArrayList(Row){};
        errdefer {
            for (rows.items) |*row| {
                row.deinit();
            }
            rows.deinit(self.allocator);
        }

        while (try self.fetchone()) |row| {
            try rows.append(self.allocator, row);
        }

        return try rows.toOwnedSlice(self.allocator);
    }

    /// Fetch n rows
    pub fn fetchmany(self: *Cursor, size: usize) ![]Row {
        var rows = std.ArrayList(Row){};
        errdefer {
            for (rows.items) |*row| {
                row.deinit();
            }
            rows.deinit(self.allocator);
        }

        var count: usize = 0;
        while (count < size) : (count += 1) {
            const row = try self.fetchone() orelse break;
            try rows.append(self.allocator, row);
        }

        return try rows.toOwnedSlice(self.allocator);
    }

    /// Close the cursor
    pub fn close(self: *Cursor) void {
        self.deinit();
    }
};

/// Connection - database connection object
pub const Connection = struct {
    db: ?*c.sqlite3,
    allocator: std.mem.Allocator,
    isolation_level: ?[]const u8,
    in_transaction: bool,

    pub fn init(path: []const u8, allocator: std.mem.Allocator) !Connection {
        var db: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open(path.ptr, &db);
        if (rc != c.SQLITE_OK) {
            return error.OpenFailed;
        }
        return Connection{
            .db = db,
            .allocator = allocator,
            .isolation_level = null,
            .in_transaction = false,
        };
    }

    /// Create a cursor
    pub fn cursor(self: *const Connection) Cursor {
        return Cursor.init(@constCast(self), self.allocator);
    }

    /// Execute SQL directly (convenience method)
    pub fn execute(self: *Connection, sql: []const u8) !Cursor {
        var cur = self.cursor();
        try cur.execute(sql);
        return cur;
    }

    /// Commit the current transaction
    pub fn commit(self: *Connection) !void {
        if (self.in_transaction) {
            var errmsg: ?[*:0]u8 = null;
            const rc = c.sqlite3_exec(self.db, "COMMIT", null, null, &errmsg);
            if (rc != c.SQLITE_OK) {
                return error.CommitFailed;
            }
            self.in_transaction = false;
        }
    }

    /// Rollback the current transaction
    pub fn rollback(self: *Connection) !void {
        if (self.in_transaction) {
            var errmsg: ?[*:0]u8 = null;
            const rc = c.sqlite3_exec(self.db, "ROLLBACK", null, null, &errmsg);
            if (rc != c.SQLITE_OK) {
                return error.RollbackFailed;
            }
            self.in_transaction = false;
        }
    }

    /// Begin a transaction
    pub fn begin(self: *Connection) !void {
        if (!self.in_transaction) {
            var errmsg: ?[*:0]u8 = null;
            const rc = c.sqlite3_exec(self.db, "BEGIN", null, null, &errmsg);
            if (rc != c.SQLITE_OK) {
                return error.BeginFailed;
            }
            self.in_transaction = true;
        }
    }

    /// Close the connection
    pub fn close(self: *Connection) void {
        if (self.db) |db| {
            _ = c.sqlite3_close(db);
            self.db = null;
        }
    }

    /// Get total changes
    pub fn total_changes(self: *Connection) i32 {
        return c.sqlite3_total_changes(self.db);
    }

    /// Create a function (simplified)
    pub fn create_function(self: *Connection, name: []const u8, nargs: c_int, func: anytype) !void {
        _ = func;
        _ = nargs;
        _ = name;
        _ = self;
        // TODO: Implement create_function properly
        return error.NotImplemented;
    }
};

/// Python-compatible API: connect() returns a Connection
pub fn connect(path: []const u8) !Connection {
    return Connection.init(path, std.heap.c_allocator);
}

/// Connect with allocator
pub fn connectWithAllocator(path: []const u8, allocator: std.mem.Allocator) !Connection {
    return Connection.init(path, allocator);
}

/// In-memory database
pub fn connectMemory() !Connection {
    return connect(":memory:");
}

// Constants for compatibility
pub const PARSE_DECLTYPES = 1;
pub const PARSE_COLNAMES = 2;
pub const SQLITE_OK = c.SQLITE_OK;
pub const SQLITE_ERROR = c.SQLITE_ERROR;
pub const SQLITE_BUSY = c.SQLITE_BUSY;
pub const SQLITE_LOCKED = c.SQLITE_LOCKED;

/// Get SQLite version
pub fn sqlite_version() []const u8 {
    return std.mem.span(c.sqlite3_libversion());
}

/// Get SQLite version number
pub fn sqlite_version_info() struct { major: u32, minor: u32, patch: u32 } {
    const ver = c.sqlite3_libversion_number();
    return .{
        .major = @intCast(@divTrunc(ver, 1000000)),
        .minor = @intCast(@mod(@divTrunc(ver, 1000), 1000)),
        .patch = @intCast(@mod(ver, 1000)),
    };
}
