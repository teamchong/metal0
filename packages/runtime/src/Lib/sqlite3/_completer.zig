//! sqlite3._completer - Tab completion for sqlite3 shell
//! Reference: cpython/Lib/sqlite3/_completer.py (internal)
//!
//! Provides tab completion for the interactive sqlite3 shell.

const std = @import("std");

/// SQL keywords for completion
pub const SQL_KEYWORDS = [_][]const u8{
    "SELECT",
    "FROM",
    "WHERE",
    "AND",
    "OR",
    "NOT",
    "IN",
    "LIKE",
    "BETWEEN",
    "IS",
    "NULL",
    "INSERT",
    "INTO",
    "VALUES",
    "UPDATE",
    "SET",
    "DELETE",
    "CREATE",
    "TABLE",
    "INDEX",
    "VIEW",
    "TRIGGER",
    "DROP",
    "ALTER",
    "ADD",
    "COLUMN",
    "PRIMARY",
    "KEY",
    "FOREIGN",
    "REFERENCES",
    "UNIQUE",
    "CHECK",
    "DEFAULT",
    "AUTOINCREMENT",
    "INTEGER",
    "TEXT",
    "REAL",
    "BLOB",
    "NUMERIC",
    "VARCHAR",
    "BOOLEAN",
    "DATE",
    "DATETIME",
    "TIMESTAMP",
    "ORDER",
    "BY",
    "ASC",
    "DESC",
    "LIMIT",
    "OFFSET",
    "GROUP",
    "HAVING",
    "JOIN",
    "LEFT",
    "RIGHT",
    "INNER",
    "OUTER",
    "CROSS",
    "ON",
    "USING",
    "UNION",
    "ALL",
    "EXCEPT",
    "INTERSECT",
    "AS",
    "DISTINCT",
    "CASE",
    "WHEN",
    "THEN",
    "ELSE",
    "END",
    "EXISTS",
    "CAST",
    "COALESCE",
    "NULLIF",
    "BEGIN",
    "COMMIT",
    "ROLLBACK",
    "TRANSACTION",
    "SAVEPOINT",
    "RELEASE",
    "PRAGMA",
    "EXPLAIN",
    "QUERY",
    "PLAN",
    "VACUUM",
    "ANALYZE",
    "REINDEX",
    "ATTACH",
    "DETACH",
    "GLOB",
    "REGEXP",
    "ESCAPE",
    "COLLATE",
    "INDEXED",
    "TEMP",
    "TEMPORARY",
    "IF",
    "REPLACE",
    "ABORT",
    "FAIL",
    "IGNORE",
    "CONFLICT",
    "INSTEAD",
    "OF",
    "FOR",
    "EACH",
    "ROW",
    "BEFORE",
    "AFTER",
    "RAISE",
};

/// Dot commands for completion
pub const DOT_COMMANDS = [_][]const u8{
    ".backup",
    ".bail",
    ".binary",
    ".cd",
    ".changes",
    ".check",
    ".clone",
    ".databases",
    ".dbconfig",
    ".dbinfo",
    ".dump",
    ".echo",
    ".eqp",
    ".excel",
    ".exit",
    ".expert",
    ".explain",
    ".filectrl",
    ".fullschema",
    ".headers",
    ".help",
    ".import",
    ".imposter",
    ".indexes",
    ".limit",
    ".lint",
    ".load",
    ".log",
    ".mode",
    ".nonce",
    ".nullvalue",
    ".once",
    ".open",
    ".output",
    ".parameter",
    ".print",
    ".progress",
    ".prompt",
    ".quit",
    ".read",
    ".recover",
    ".restore",
    ".save",
    ".scanstats",
    ".schema",
    ".selftest",
    ".separator",
    ".session",
    ".sha3sum",
    ".shell",
    ".show",
    ".stats",
    ".system",
    ".tables",
    ".testcase",
    ".testctrl",
    ".timeout",
    ".timer",
    ".trace",
    ".vfsinfo",
    ".vfslist",
    ".vfsname",
    ".width",
};

/// SQLite functions for completion
pub const SQL_FUNCTIONS = [_][]const u8{
    "abs",
    "changes",
    "char",
    "coalesce",
    "glob",
    "hex",
    "ifnull",
    "instr",
    "last_insert_rowid",
    "length",
    "like",
    "likelihood",
    "likely",
    "load_extension",
    "lower",
    "ltrim",
    "max",
    "min",
    "nullif",
    "printf",
    "quote",
    "random",
    "randomblob",
    "replace",
    "round",
    "rtrim",
    "soundex",
    "sqlite_compileoption_get",
    "sqlite_compileoption_used",
    "sqlite_offset",
    "sqlite_source_id",
    "sqlite_version",
    "substr",
    "total_changes",
    "trim",
    "typeof",
    "unicode",
    "unlikely",
    "upper",
    "zeroblob",
    "avg",
    "count",
    "group_concat",
    "sum",
    "total",
    "date",
    "time",
    "datetime",
    "julianday",
    "strftime",
    "json",
    "json_array",
    "json_array_length",
    "json_extract",
    "json_insert",
    "json_object",
    "json_patch",
    "json_remove",
    "json_replace",
    "json_set",
    "json_type",
    "json_valid",
    "json_quote",
    "json_group_array",
    "json_group_object",
    "json_each",
    "json_tree",
};

/// Completer state
pub const Completer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    tables: std.ArrayList([]const u8),
    columns: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .tables = std.ArrayList([]const u8).init(allocator),
            .columns = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.tables.deinit();
        self.columns.deinit();
    }

    /// Get completions for a prefix
    pub fn complete(self: *Self, text: []const u8) !std.ArrayList([]const u8) {
        var matches: std.ArrayList([]const u8) = .{};

        const upper = std.ascii.upperString(text);
        defer self.allocator.free(upper);

        // Check dot commands
        if (text.len > 0 and text[0] == '.') {
            for (DOT_COMMANDS) |cmd| {
                if (std.mem.startsWith(u8, cmd, text)) {
                    try matches.append(self.allocator, cmd);
                }
            }
            return matches;
        }

        // Check SQL keywords
        for (SQL_KEYWORDS) |kw| {
            if (std.mem.startsWith(u8, kw, upper)) {
                try matches.append(self.allocator, kw);
            }
        }

        // Check functions
        const lower = std.ascii.lowerString(text);
        defer self.allocator.free(lower);

        for (SQL_FUNCTIONS) |func| {
            if (std.mem.startsWith(u8, func, lower)) {
                try matches.append(self.allocator, func);
            }
        }

        // Check cached tables/columns
        for (self.tables.items) |table| {
            if (std.mem.startsWith(u8, table, text)) {
                try matches.append(self.allocator, table);
            }
        }

        return matches;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "SQL_KEYWORDS contains SELECT" {
    var found = false;
    for (SQL_KEYWORDS) |kw| {
        if (std.mem.eql(u8, kw, "SELECT")) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}

test "DOT_COMMANDS contains .quit" {
    var found = false;
    for (DOT_COMMANDS) |cmd| {
        if (std.mem.eql(u8, cmd, ".quit")) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}

test "Completer init" {
    const allocator = std.testing.allocator;
    var completer = Completer.init(allocator);
    defer completer.deinit();
    try std.testing.expectEqual(@as(usize, 0), completer.tables.items.len);
}
