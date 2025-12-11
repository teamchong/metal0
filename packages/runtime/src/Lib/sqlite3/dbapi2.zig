//! SQLite3 DB-API 2.0 interface
//!
//! Mirrors: CPython Lib/sqlite3/dbapi2.py

const std = @import("std");
const errors = @import("errors.zig");

const c = @cImport({
    @cInclude("vendor/sqlite3/sqlite3.h");
});

// ============================================================================
// Connection
// ============================================================================

/// Database connection object
pub const Connection = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    database: []const u8,
    isolation_level: ?[]const u8,
    in_transaction: bool,
    row_factory: ?RowFactory,
    text_factory: ?*const fn ([]const u8) []const u8,
    check_same_thread: bool,
    /// SQLite3 database handle
    db: ?*c.sqlite3,

    pub const RowFactory = *const fn (cursor: *Cursor, row: []?[]const u8) anytype;

    pub fn init(allocator: std.mem.Allocator, database: []const u8, options: ConnectionOptions) !Self {
        var db: ?*c.sqlite3 = null;
        const db_path = try allocator.dupeZ(u8, database);
        defer allocator.free(db_path);

        const rc = c.sqlite3_open(db_path.ptr, &db);
        if (rc != c.SQLITE_OK) {
            if (db) |d| {
                _ = c.sqlite3_close(d);
            }
            return error.DatabaseError;
        }

        // Set busy timeout
        _ = c.sqlite3_busy_timeout(db, @intFromFloat(options.timeout * 1000));

        return .{
            .allocator = allocator,
            .database = try allocator.dupe(u8, database),
            .isolation_level = options.isolation_level,
            .in_transaction = false,
            .row_factory = null,
            .text_factory = null,
            .check_same_thread = options.check_same_thread,
            .db = db,
        };
    }

    pub fn deinit(self: *Self) void {
        self.close() catch {};
        self.allocator.free(self.database);
    }

    /// Get total changes from SQLite
    pub fn total_changes(self: *Self) i64 {
        if (self.db) |db| {
            return c.sqlite3_total_changes(db);
        }
        return 0;
    }

    /// Create a cursor
    pub fn cursor(self: *Self) !Cursor {
        return Cursor.init(self.allocator, self);
    }

    /// Execute SQL directly
    pub fn execute(self: *Self, sql: []const u8, parameters: ?[]const ?[]const u8) !Cursor {
        var cur = try self.cursor();
        try cur.execute(sql, parameters);
        return cur;
    }

    /// Execute multiple SQL statements
    pub fn executemany(self: *Self, sql: []const u8, seq_of_parameters: []const []const ?[]const u8) !Cursor {
        var cur = try self.cursor();
        try cur.executemany(sql, seq_of_parameters);
        return cur;
    }

    /// Execute a script of SQL statements
    pub fn executescript(self: *Self, sql_script: []const u8) !Cursor {
        var cur = try self.cursor();
        try cur.executescript(sql_script);
        return cur;
    }

    /// Commit transaction
    pub fn commit(self: *Self) !void {
        if (self.in_transaction) {
            self.in_transaction = false;
        }
    }

    /// Rollback transaction
    pub fn rollback(self: *Self) !void {
        if (self.in_transaction) {
            self.in_transaction = false;
        }
    }

    /// Close connection
    pub fn close(self: *Self) !void {
        if (self.db) |db| {
            const rc = c.sqlite3_close(db);
            if (rc != c.SQLITE_OK) {
                return error.DatabaseError;
            }
            self.db = null;
        }
    }

    /// Create a user-defined function
    pub fn createFunction(
        self: *Self,
        name: []const u8,
        narg: i32,
        func: ?*const fn (?*c.sqlite3_context, c_int, [*c]?*c.sqlite3_value) callconv(.C) void,
        deterministic: bool,
    ) !void {
        const db = self.db orelse return error.DatabaseError;
        const name_z = try self.allocator.dupeZ(u8, name);
        defer self.allocator.free(name_z);

        var flags: c_int = c.SQLITE_UTF8;
        if (deterministic) flags |= c.SQLITE_DETERMINISTIC;

        const rc = c.sqlite3_create_function(db, name_z.ptr, narg, flags, null, func, null, null);
        if (rc != c.SQLITE_OK) return error.DatabaseError;
    }

    /// Create a user-defined aggregate
    pub fn createAggregate(
        self: *Self,
        name: []const u8,
        narg: i32,
        step_func: ?*const fn (?*c.sqlite3_context, c_int, [*c]?*c.sqlite3_value) callconv(.C) void,
        final_func: ?*const fn (?*c.sqlite3_context) callconv(.C) void,
    ) !void {
        const db = self.db orelse return error.DatabaseError;
        const name_z = try self.allocator.dupeZ(u8, name);
        defer self.allocator.free(name_z);

        const rc = c.sqlite3_create_function(db, name_z.ptr, narg, c.SQLITE_UTF8, null, null, step_func, final_func);
        if (rc != c.SQLITE_OK) return error.DatabaseError;
    }

    /// Create a collation
    pub fn createCollation(
        self: *Self,
        name: []const u8,
        callable: ?*const fn (?*anyopaque, c_int, ?*const anyopaque, c_int, ?*const anyopaque) callconv(.C) c_int,
    ) !void {
        const db = self.db orelse return error.DatabaseError;
        const name_z = try self.allocator.dupeZ(u8, name);
        defer self.allocator.free(name_z);

        const rc = c.sqlite3_create_collation(db, name_z.ptr, c.SQLITE_UTF8, null, callable);
        if (rc != c.SQLITE_OK) return error.DatabaseError;
    }

    /// Set progress handler
    pub fn setProgressHandler(self: *Self, handler: ?*const fn (?*anyopaque) callconv(.C) c_int, n: i32) void {
        const db = self.db orelse return;
        _ = c.sqlite3_progress_handler(db, n, handler, null);
    }

    /// Set trace callback
    pub fn setTraceCallback(self: *Self, callback: ?*const fn (?*anyopaque, [*c]const u8) callconv(.C) void) void {
        const db = self.db orelse return;
        _ = c.sqlite3_trace(db, callback, null);
    }

    /// Enable load extension
    pub fn enableLoadExtension(self: *Self, enabled: bool) void {
        const db = self.db orelse return;
        _ = c.sqlite3_enable_load_extension(db, if (enabled) 1 else 0);
    }

    /// Load extension
    pub fn loadExtension(self: *Self, path: []const u8, entrypoint: ?[]const u8) !void {
        const db = self.db orelse return error.DatabaseError;
        const path_z = try self.allocator.dupeZ(u8, path);
        defer self.allocator.free(path_z);

        var entry_z: ?[*:0]u8 = null;
        if (entrypoint) |ep| {
            entry_z = (try self.allocator.dupeZ(u8, ep)).ptr;
        }
        defer if (entry_z) |e| self.allocator.free(std.mem.sliceTo(e, 0));

        var errmsg: [*c]u8 = null;
        const rc = c.sqlite3_load_extension(db, path_z.ptr, entry_z, &errmsg);
        if (rc != c.SQLITE_OK) {
            if (errmsg) |_| {
                c.sqlite3_free(errmsg);
            }
            return error.DatabaseError;
        }
    }

    /// Interrupt running query
    pub fn interrupt(self: *Self) void {
        if (self.db) |db| {
            c.sqlite3_interrupt(db);
        }
    }

    /// Set authorizer callback
    pub fn setAuthorizer(self: *Self, callback: ?*const fn (?*anyopaque, c_int, [*c]const u8, [*c]const u8, [*c]const u8, [*c]const u8) callconv(.C) c_int) void {
        const db = self.db orelse return;
        _ = c.sqlite3_set_authorizer(db, callback, null);
    }

    /// Get database autocommit mode
    pub fn getAutocommit(self: *Self) bool {
        return !self.in_transaction;
    }

    /// Backup database
    pub fn backup(self: *Self, target: *Connection, pages: i32, progress: ?*const fn (status: i32, remaining: i32, total: i32) void, sleep_ms: f64) !void {
        const src_db = self.db orelse return error.DatabaseError;
        const dst_db = target.db orelse return error.DatabaseError;

        const pBackup = c.sqlite3_backup_init(dst_db, "main", src_db, "main");
        if (pBackup == null) return error.DatabaseError;

        var rc: c_int = c.SQLITE_OK;
        while (rc == c.SQLITE_OK or rc == c.SQLITE_BUSY or rc == c.SQLITE_LOCKED) {
            rc = c.sqlite3_backup_step(pBackup, pages);
            if (progress) |p| {
                const remaining = c.sqlite3_backup_remaining(pBackup);
                const total = c.sqlite3_backup_pagecount(pBackup);
                p(rc, remaining, total);
            }
            if (rc == c.SQLITE_BUSY or rc == c.SQLITE_LOCKED) {
                std.time.sleep(@intFromFloat(sleep_ms * std.time.ns_per_ms));
            }
        }

        _ = c.sqlite3_backup_finish(pBackup);
        if (rc != c.SQLITE_DONE) return error.DatabaseError;
    }
};

pub const ConnectionOptions = struct {
    timeout: f64 = 5.0,
    detect_types: i32 = 0,
    isolation_level: ?[]const u8 = "DEFERRED",
    check_same_thread: bool = true,
    factory: ?*const fn (allocator: std.mem.Allocator, database: []const u8) Connection = null,
    cached_statements: i32 = 128,
    uri: bool = false,
};

// ============================================================================
// Cursor
// ============================================================================

/// Database cursor object
pub const Cursor = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    connection: *Connection,
    description: ?[]ColumnDescription,
    rowcount: i64,
    lastrowid: ?i64,
    arraysize: usize,
    rows: std.ArrayList(Row),
    current_row: usize,
    /// Current prepared statement
    stmt: ?*c.sqlite3_stmt,

    pub const ColumnDescription = struct {
        name: []const u8,
        type_code: ?[]const u8,
        display_size: ?i32,
        internal_size: ?i32,
        precision: ?i32,
        scale: ?i32,
        null_ok: ?bool,
    };

    pub const Row = []?[]const u8;

    pub fn init(allocator: std.mem.Allocator, connection: *Connection) Self {
        return .{
            .allocator = allocator,
            .connection = connection,
            .description = null,
            .rowcount = -1,
            .lastrowid = null,
            .arraysize = 1,
            .rows = std.ArrayList(Row).init(allocator),
            .current_row = 0,
            .stmt = null,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.stmt) |stmt| {
            _ = c.sqlite3_finalize(stmt);
        }
        self.rows.deinit();
        if (self.description) |desc| {
            self.allocator.free(desc);
        }
    }

    /// Execute a SQL statement
    pub fn execute(self: *Self, sql: []const u8, parameters: ?[]const ?[]const u8) !void {
        const db = self.connection.db orelse return error.DatabaseError;

        // Finalize previous statement
        if (self.stmt) |stmt| {
            _ = c.sqlite3_finalize(stmt);
            self.stmt = null;
        }

        self.rows.clearRetainingCapacity();
        self.current_row = 0;

        // Prepare statement
        const sql_z = try self.allocator.dupeZ(u8, sql);
        defer self.allocator.free(sql_z);

        var stmt: ?*c.sqlite3_stmt = null;
        var rc = c.sqlite3_prepare_v2(db, sql_z.ptr, @intCast(sql_z.len), &stmt, null);
        if (rc != c.SQLITE_OK) {
            return error.DatabaseError;
        }
        self.stmt = stmt;

        // Bind parameters
        if (parameters) |params| {
            for (params, 1..) |param, i| {
                if (param) |p| {
                    const p_z = try self.allocator.dupeZ(u8, p);
                    defer self.allocator.free(p_z);
                    rc = c.sqlite3_bind_text(stmt, @intCast(i), p_z.ptr, @intCast(p.len), c.SQLITE_TRANSIENT);
                } else {
                    rc = c.sqlite3_bind_null(stmt, @intCast(i));
                }
                if (rc != c.SQLITE_OK) {
                    return error.DatabaseError;
                }
            }
        }

        // Get column count and build description
        const col_count = c.sqlite3_column_count(stmt);
        if (col_count > 0) {
            var desc = try self.allocator.alloc(ColumnDescription, @intCast(col_count));
            for (0..@intCast(col_count)) |i| {
                const name_ptr = c.sqlite3_column_name(stmt, @intCast(i));
                desc[i] = .{
                    .name = if (name_ptr) |p| std.mem.sliceTo(p, 0) else "",
                    .type_code = null,
                    .display_size = null,
                    .internal_size = null,
                    .precision = null,
                    .scale = null,
                    .null_ok = null,
                };
            }
            if (self.description) |old_desc| {
                self.allocator.free(old_desc);
            }
            self.description = desc;
        }

        // Execute and fetch rows
        self.rowcount = 0;
        while (true) {
            rc = c.sqlite3_step(stmt);
            if (rc == c.SQLITE_ROW) {
                // Fetch row data
                var row = try self.allocator.alloc(?[]const u8, @intCast(col_count));
                for (0..@intCast(col_count)) |i| {
                    const col_type = c.sqlite3_column_type(stmt, @intCast(i));
                    if (col_type == c.SQLITE_NULL) {
                        row[i] = null;
                    } else {
                        const text = c.sqlite3_column_text(stmt, @intCast(i));
                        const len = c.sqlite3_column_bytes(stmt, @intCast(i));
                        if (text) |t| {
                            row[i] = try self.allocator.dupe(u8, t[0..@intCast(len)]);
                        } else {
                            row[i] = null;
                        }
                    }
                }
                try self.rows.append(row);
            } else if (rc == c.SQLITE_DONE) {
                break;
            } else {
                return error.DatabaseError;
            }
        }

        // Get rowcount for non-SELECT statements
        self.rowcount = c.sqlite3_changes(db);
        self.lastrowid = c.sqlite3_last_insert_rowid(db);
    }

    /// Execute SQL with multiple parameter sets
    pub fn executemany(self: *Self, sql: []const u8, seq_of_parameters: []const []const ?[]const u8) !void {
        for (seq_of_parameters) |params| {
            try self.execute(sql, params);
        }
    }

    /// Execute a script of SQL statements
    pub fn executescript(self: *Self, sql_script: []const u8) !void {
        // Split by semicolons and execute each
        var statements = std.mem.splitScalar(u8, sql_script, ';');
        while (statements.next()) |stmt| {
            const trimmed = std.mem.trim(u8, stmt, " \t\n\r");
            if (trimmed.len > 0) {
                try self.execute(trimmed, null);
            }
        }
    }

    /// Fetch one row
    pub fn fetchone(self: *Self) ?Row {
        if (self.current_row < self.rows.items.len) {
            const row = self.rows.items[self.current_row];
            self.current_row += 1;
            return row;
        }
        return null;
    }

    /// Fetch many rows
    pub fn fetchmany(self: *Self, size: ?usize) ![]Row {
        const n = size orelse self.arraysize;
        var result = std.ArrayList(Row).init(self.allocator);

        var count: usize = 0;
        while (count < n) : (count += 1) {
            if (self.fetchone()) |row| {
                try result.append(row);
            } else {
                break;
            }
        }

        return result.toOwnedSlice();
    }

    /// Fetch all rows
    pub fn fetchall(self: *Self) ![]Row {
        var result = std.ArrayList(Row).init(self.allocator);

        while (self.fetchone()) |row| {
            try result.append(row);
        }

        return result.toOwnedSlice();
    }

    /// Close cursor
    pub fn close(self: *Self) void {
        self.rows.clearAndFree();
    }

    /// Set input sizes (no-op for SQLite)
    pub fn setinputsizes(self: *Self, sizes: []const i32) void {
        _ = self;
        _ = sizes;
    }

    /// Set output size (no-op for SQLite)
    pub fn setoutputsize(self: *Self, size: i32, column: ?i32) void {
        _ = self;
        _ = size;
        _ = column;
    }
};

// ============================================================================
// Row Object
// ============================================================================

/// Row object with both index and name access
pub const RowObject = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    data: []?[]const u8,
    description: []const Cursor.ColumnDescription,

    pub fn init(allocator: std.mem.Allocator, data: []?[]const u8, description: []const Cursor.ColumnDescription) Self {
        return .{
            .allocator = allocator,
            .data = data,
            .description = description,
        };
    }

    /// Get by index
    pub fn get(self: *Self, index: usize) ??[]const u8 {
        if (index < self.data.len) {
            return self.data[index];
        }
        return null;
    }

    /// Get by column name
    pub fn getByName(self: *Self, name: []const u8) ??[]const u8 {
        for (self.description, 0..) |col, i| {
            if (std.mem.eql(u8, col.name, name)) {
                return self.data[i];
            }
        }
        return null;
    }

    /// Get all keys (column names)
    pub fn keys(self: *Self) ![][]const u8 {
        var result = std.ArrayList([]const u8).init(self.allocator);
        for (self.description) |col| {
            try result.append(col.name);
        }
        return result.toOwnedSlice();
    }
};

// ============================================================================
// Module Functions
// ============================================================================

/// Connect to a database
pub fn connect(allocator: std.mem.Allocator, database: []const u8, options: ConnectionOptions) !Connection {
    return Connection.init(allocator, database, options);
}

/// Complete SQL statement check
pub fn completeStatement(statement: []const u8) bool {
    // Check if statement is complete (ends with semicolon outside quotes)
    var in_string = false;
    var quote_char: u8 = 0;

    for (statement) |c| {
        if (in_string) {
            if (c == quote_char) {
                in_string = false;
            }
        } else {
            if (c == '\'' or c == '"') {
                in_string = true;
                quote_char = c;
            }
        }
    }

    if (in_string) return false;

    const trimmed = std.mem.trimRight(u8, statement, " \t\n\r");
    return trimmed.len > 0 and trimmed[trimmed.len - 1] == ';';
}

/// Enable shared cache mode
pub fn enableSharedCache(enable: bool) !void {
    const rc = c.sqlite3_enable_shared_cache(if (enable) 1 else 0);
    if (rc != c.SQLITE_OK) return error.DatabaseError;
}
