//! Python 'sqlite3' module - SQLite database interface
//!
//! Provides a Python DB-API 2.0 interface to SQLite databases.
//!
//! Mirrors: CPython Lib/sqlite3/

const std = @import("std");

// ============================================================================
// Module-level Constants
// ============================================================================

/// SQLite version
pub const sqlite_version = "3.45.0";
pub const sqlite_version_info = .{ 3, 45, 0 };

/// API level
pub const apilevel = "2.0";

/// Thread safety level
pub const threadsafety = 1;

/// Parameter style
pub const paramstyle = "qmark";

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
    total_changes: i64,
    check_same_thread: bool,

    pub const RowFactory = *const fn (cursor: *Cursor, row: []?[]const u8) anytype;

    pub fn init(allocator: std.mem.Allocator, database: []const u8, options: ConnectionOptions) !Self {
        return .{
            .allocator = allocator,
            .database = try allocator.dupe(u8, database),
            .isolation_level = options.isolation_level,
            .in_transaction = false,
            .row_factory = null,
            .text_factory = null,
            .total_changes = 0,
            .check_same_thread = options.check_same_thread,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.database);
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
        _ = self;
        // Would close SQLite connection
    }

    /// Create a user-defined function
    pub fn createFunction(
        self: *Self,
        name: []const u8,
        narg: i32,
        func: *const fn (context: anytype, args: []anytype) anytype,
        deterministic: bool,
    ) !void {
        _ = self;
        _ = name;
        _ = narg;
        _ = func;
        _ = deterministic;
        // Would register function with SQLite
    }

    /// Create a user-defined aggregate
    pub fn createAggregate(
        self: *Self,
        name: []const u8,
        narg: i32,
        aggregate_class: anytype,
    ) !void {
        _ = self;
        _ = name;
        _ = narg;
        _ = aggregate_class;
        // Would register aggregate with SQLite
    }

    /// Create a collation
    pub fn createCollation(
        self: *Self,
        name: []const u8,
        callable: *const fn (a: []const u8, b: []const u8) i32,
    ) !void {
        _ = self;
        _ = name;
        _ = callable;
        // Would register collation with SQLite
    }

    /// Set progress handler
    pub fn setProgressHandler(self: *Self, handler: ?*const fn () bool, n: i32) void {
        _ = self;
        _ = handler;
        _ = n;
        // Would set progress handler
    }

    /// Set trace callback
    pub fn setTraceCallback(self: *Self, callback: ?*const fn (statement: []const u8) void) void {
        _ = self;
        _ = callback;
        // Would set trace callback
    }

    /// Enable load extension
    pub fn enableLoadExtension(self: *Self, enabled: bool) void {
        _ = self;
        _ = enabled;
        // Would enable/disable extension loading
    }

    /// Load extension
    pub fn loadExtension(self: *Self, path: []const u8, entrypoint: ?[]const u8) !void {
        _ = self;
        _ = path;
        _ = entrypoint;
        // Would load extension
    }

    /// Interrupt running query
    pub fn interrupt(self: *Self) void {
        _ = self;
        // Would interrupt SQLite
    }

    /// Set authorizer callback
    pub fn setAuthorizer(self: *Self, callback: ?*const fn (action: i32, arg1: ?[]const u8, arg2: ?[]const u8, dbname: ?[]const u8, trigger: ?[]const u8) i32) void {
        _ = self;
        _ = callback;
        // Would set authorizer
    }

    /// Get database autocommit mode
    pub fn getAutocommit(self: *Self) bool {
        return !self.in_transaction;
    }

    /// Backup database
    pub fn backup(self: *Self, target: *Connection, pages: i32, progress: ?*const fn (status: i32, remaining: i32, total: i32) void, sleep: f64) !void {
        _ = self;
        _ = target;
        _ = pages;
        _ = progress;
        _ = sleep;
        // Would backup database
    }

    /// Get table names
    pub fn iterdump(self: *Self) ![][]const u8 {
        _ = self;
        // Would iterate SQL dump
        return &[_][]const u8{};
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
    description: ?[]const ColumnDescription,
    rowcount: i64,
    lastrowid: ?i64,
    arraysize: usize,
    rows: std.ArrayList(Row),
    current_row: usize,

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
        };
    }

    pub fn deinit(self: *Self) void {
        self.rows.deinit();
    }

    /// Execute a SQL statement
    pub fn execute(self: *Self, sql: []const u8, parameters: ?[]const ?[]const u8) !void {
        _ = parameters;
        self.rows.clearRetainingCapacity();
        self.current_row = 0;
        self.rowcount = 0;

        // Would execute SQL via SQLite
        // Parse SQL to determine statement type
        const trimmed = std.mem.trim(u8, sql, " \t\n\r");
        _ = trimmed;

        // Set description for SELECT statements
        // Would set based on actual result columns
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

/// Register an adapter
pub fn registerAdapter(comptime T: type, adapter: *const fn (value: T) []const u8) void {
    _ = adapter;
    // Would register type adapter
}

/// Register a converter
pub fn registerConverter(typename: []const u8, converter: *const fn (value: []const u8) anytype) void {
    _ = typename;
    _ = converter;
    // Would register type converter
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

/// Enable shared cache
pub fn enableSharedCache(enable: bool) !void {
    _ = enable;
    // Would enable/disable shared cache
}

// ============================================================================
// Type Detection
// ============================================================================

pub const PARSE_DECLTYPES = 1;
pub const PARSE_COLNAMES = 2;

// ============================================================================
// Exceptions
// ============================================================================

pub const Error = error{
    Warning,
    InterfaceError,
    DatabaseError,
    DataError,
    OperationalError,
    IntegrityError,
    InternalError,
    ProgrammingError,
    NotSupportedError,
};

pub const Warning = Error.Warning;
pub const InterfaceError = Error.InterfaceError;
pub const DatabaseError = Error.DatabaseError;
pub const DataError = Error.DataError;
pub const OperationalError = Error.OperationalError;
pub const IntegrityError = Error.IntegrityError;
pub const InternalError = Error.InternalError;
pub const ProgrammingError = Error.ProgrammingError;
pub const NotSupportedError = Error.NotSupportedError;

// ============================================================================
// Adapters
// ============================================================================

pub const adapters = struct {
    /// Adapt a date struct to ISO format (YYYY-MM-DD)
    /// Input: struct with year, month, day fields
    pub fn adaptDate(allocator: std.mem.Allocator, date: anytype) ![]u8 {
        return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{
            date.year,
            date.month,
            date.day,
        });
    }

    /// Adapt a datetime struct to ISO format (YYYY-MM-DD HH:MM:SS)
    /// Input: struct with year, month, day, hour, minute, second fields
    pub fn adaptDatetime(allocator: std.mem.Allocator, datetime: anytype) ![]u8 {
        return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{
            datetime.year,
            datetime.month,
            datetime.day,
            datetime.hour,
            datetime.minute,
            datetime.second,
        });
    }
};

// ============================================================================
// Converters
// ============================================================================

pub const converters = struct {
    /// Convert ISO date string to date
    pub fn convertDate(allocator: std.mem.Allocator, s: []const u8) !struct { year: i32, month: u8, day: u8 } {
        _ = allocator;
        // Parse YYYY-MM-DD
        var parts = std.mem.splitScalar(u8, s, '-');
        const year_str = parts.next() orelse return error.DataError;
        const month_str = parts.next() orelse return error.DataError;
        const day_str = parts.next() orelse return error.DataError;

        return .{
            .year = try std.fmt.parseInt(i32, year_str, 10),
            .month = try std.fmt.parseInt(u8, month_str, 10),
            .day = try std.fmt.parseInt(u8, day_str, 10),
        };
    }

    /// Convert ISO timestamp string to datetime
    pub fn convertTimestamp(allocator: std.mem.Allocator, s: []const u8) !struct {
        year: i32,
        month: u8,
        day: u8,
        hour: u8,
        minute: u8,
        second: u8,
    } {
        _ = allocator;
        // Parse YYYY-MM-DD HH:MM:SS
        var date_time = std.mem.splitScalar(u8, s, ' ');
        const date_str = date_time.next() orelse return error.DataError;
        const time_str = date_time.next() orelse return error.DataError;

        var date_parts = std.mem.splitScalar(u8, date_str, '-');
        var time_parts = std.mem.splitScalar(u8, time_str, ':');

        return .{
            .year = try std.fmt.parseInt(i32, date_parts.next() orelse return error.DataError, 10),
            .month = try std.fmt.parseInt(u8, date_parts.next() orelse return error.DataError, 10),
            .day = try std.fmt.parseInt(u8, date_parts.next() orelse return error.DataError, 10),
            .hour = try std.fmt.parseInt(u8, time_parts.next() orelse return error.DataError, 10),
            .minute = try std.fmt.parseInt(u8, time_parts.next() orelse return error.DataError, 10),
            .second = try std.fmt.parseInt(u8, time_parts.next() orelse return error.DataError, 10),
        };
    }
};

// ============================================================================
// PrepareProtocol
// ============================================================================

pub const PrepareProtocol = struct {
    /// Protocol for preparing values for SQLite
    /// Converts Zig types to SQLite-compatible string representations
    pub fn prepare(allocator: std.mem.Allocator, value: anytype) ![]u8 {
        const T = @TypeOf(value);
        return switch (@typeInfo(T)) {
            .Int, .ComptimeInt => std.fmt.allocPrint(allocator, "{d}", .{value}),
            .Float, .ComptimeFloat => std.fmt.allocPrint(allocator, "{d}", .{value}),
            .Bool => if (value) allocator.dupe(u8, "1") else allocator.dupe(u8, "0"),
            .Pointer => |ptr| {
                if (ptr.size == .Slice and ptr.child == u8) {
                    // String - escape single quotes
                    var result = std.ArrayList(u8).init(allocator);
                    try result.append('\'');
                    for (value) |c| {
                        if (c == '\'') try result.append('\''); // Escape with double quote
                        try result.append(c);
                    }
                    try result.append('\'');
                    return result.toOwnedSlice();
                }
                return error.UnsupportedType;
            },
            .Optional => if (value) |v| prepare(allocator, v) else allocator.dupe(u8, "NULL"),
            else => error.UnsupportedType,
        };
    }
};

// ============================================================================
// Blob
// ============================================================================

/// Blob object for incremental I/O
pub const Blob = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    connection: *Connection,
    data: []u8,
    position: usize,

    pub fn init(allocator: std.mem.Allocator, connection: *Connection, table: []const u8, column: []const u8, row: i64, readonly: bool) !Self {
        _ = table;
        _ = column;
        _ = row;
        _ = readonly;
        return .{
            .allocator = allocator,
            .connection = connection,
            .data = &[_]u8{},
            .position = 0,
        };
    }

    pub fn read(self: *Self, length: ?usize) []const u8 {
        const len = length orelse (self.data.len - self.position);
        const end = @min(self.position + len, self.data.len);
        const result = self.data[self.position..end];
        self.position = end;
        return result;
    }

    pub fn write(self: *Self, data: []const u8) !void {
        _ = self;
        _ = data;
        // Would write to blob
    }

    pub fn seek(self: *Self, offset: i64, whence: i32) void {
        switch (whence) {
            0 => self.position = @intCast(offset), // SEEK_SET
            1 => self.position = @intCast(@as(i64, @intCast(self.position)) + offset), // SEEK_CUR
            2 => self.position = @intCast(@as(i64, @intCast(self.data.len)) + offset), // SEEK_END
            else => {},
        }
    }

    pub fn tell(self: *Self) usize {
        return self.position;
    }

    pub fn close(self: *Self) void {
        _ = self;
        // Would close blob
    }
};

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
