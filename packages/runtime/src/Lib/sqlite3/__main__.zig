//! sqlite3.__main__ - Command-line interface for sqlite3 module
//! Reference: cpython/Lib/sqlite3/__main__.py
//!
//! Entry point for `python -m sqlite3` which provides an interactive shell.

const std = @import("std");
const dbapi2 = @import("dbapi2.zig");

/// Command-line options
pub const Options = struct {
    database: []const u8 = ":memory:",
    version: bool = false,
    help: bool = false,
};

/// Parse command line arguments
pub fn parseArgs(args: []const []const u8) Options {
    var opts = Options{};

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--version")) {
            opts.version = true;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            opts.help = true;
        } else if (arg[0] != '-') {
            opts.database = arg;
        }
    }

    return opts;
}

/// Print help message
pub fn printHelp() void {
    const help =
        \\usage: python -m sqlite3 [-h] [-v] [database]
        \\
        \\SQLite3 command-line interface
        \\
        \\positional arguments:
        \\  database        database file (default: :memory:)
        \\
        \\options:
        \\  -h, --help      show this help message and exit
        \\  -v, --version   print SQLite version and exit
        \\
    ;
    std.io.getStdOut().writeAll(help) catch {};
}

/// Print version
pub fn printVersion() void {
    std.io.getStdOut().writeAll("SQLite3 (metal0 native)\n") catch {};
}

/// Interactive REPL
pub fn repl(conn: *dbapi2.Connection) !void {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    try stdout.writeAll("SQLite3 shell. Type '.help' for commands, '.quit' to exit.\n");

    var buf: [4096]u8 = undefined;
    while (true) {
        try stdout.writeAll("sqlite> ");

        const line = stdin.readUntilDelimiterOrEof(&buf, '\n') catch |err| {
            if (err == error.EndOfStream) break;
            return err;
        } orelse break;

        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0) continue;

        // Handle dot commands
        if (trimmed[0] == '.') {
            if (std.mem.eql(u8, trimmed, ".quit") or std.mem.eql(u8, trimmed, ".exit")) {
                break;
            } else if (std.mem.eql(u8, trimmed, ".help")) {
                try stdout.writeAll(
                    \\.help      Show this help
                    \\.quit      Exit the shell
                    \\.tables    List tables
                    \\.schema    Show schema
                    \\
                );
            } else if (std.mem.eql(u8, trimmed, ".tables")) {
                var cur = try conn.cursor();
                defer cur.deinit();
                try cur.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name", null);
                for (cur.rows.items) |row| {
                    if (row.len > 0) {
                        if (row[0]) |name| {
                            try stdout.print("{s}\n", .{name});
                        }
                    }
                }
            } else if (std.mem.eql(u8, trimmed, ".schema")) {
                var cur = try conn.cursor();
                defer cur.deinit();
                try cur.execute("SELECT sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY type, name", null);
                for (cur.rows.items) |row| {
                    if (row.len > 0) {
                        if (row[0]) |sql| {
                            try stdout.print("{s};\n", .{sql});
                        }
                    }
                }
            } else {
                try stdout.print("Unknown command: {s}\n", .{trimmed});
            }
            continue;
        }

        // Execute SQL
        var cur = conn.cursor() catch |err| {
            try stdout.print("Error: {}\n", .{err});
            continue;
        };
        defer cur.deinit();

        cur.execute(trimmed, null) catch |err| {
            try stdout.print("Error: {}\n", .{err});
            continue;
        };

        // Print results
        for (cur.rows.items) |row| {
            for (row, 0..) |col, i| {
                if (i > 0) try stdout.writeAll("|");
                if (col) |v| {
                    try stdout.writeAll(v);
                } else {
                    try stdout.writeAll("NULL");
                }
            }
            try stdout.writeAll("\n");
        }
    }
}

/// Main entry point
pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const opts = if (args.len > 1) parseArgs(args[1..]) else Options{};

    if (opts.help) {
        printHelp();
        return;
    }

    if (opts.version) {
        printVersion();
        return;
    }

    var conn = try dbapi2.Connection.init(allocator, opts.database);
    defer conn.deinit();

    try repl(&conn);
}

// ============================================================================
// Tests
// ============================================================================

test "parseArgs" {
    const args = [_][]const u8{ "-v", "test.db" };
    const opts = parseArgs(&args);
    try std.testing.expect(opts.version);
    try std.testing.expectEqualStrings("test.db", opts.database);
}

test "Options defaults" {
    const opts = Options{};
    try std.testing.expectEqualStrings(":memory:", opts.database);
    try std.testing.expect(!opts.version);
}
