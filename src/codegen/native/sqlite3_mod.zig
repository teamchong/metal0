/// Python sqlite3 module - SQLite database interface
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "connect", h.wrap("try sqlite3.connect(", ")", "@as(?*anyopaque, null)") },
    .{ "Connection", h.c("const Connection = struct { database: []const u8, in_transaction: bool = false, pub fn cursor(s: *@This()) Cursor { return Cursor{ .conn = s }; } pub fn execute(s: *@This(), sql: []const u8) Cursor { var c = s.cursor(); c.execute(sql); return c; } pub fn executemany(s: *@This(), sql: []const u8, params: anytype) void { _ = s; _ = sql; _ = params; } pub fn commit(s: *@This()) void { s.in_transaction = false; } pub fn rollback(s: *@This()) void { s.in_transaction = false; } pub fn close(s: *@This()) void { _ = s; } pub fn __enter__(s: *@This()) *@This() { return s; } pub fn __exit__(s: *@This(), _: anytype) void { s.close(); } }") },
    .{ "Cursor", h.c("const Cursor = struct { conn: *Connection, description: ?[][]const u8 = null, rowcount: i64 = -1, lastrowid: ?i64 = null, results: std.ArrayList([][]const u8) = .{}, pos: usize = 0, pub fn execute(s: *@This(), sql: []const u8) void { _ = s; _ = sql; } pub fn executemany(s: *@This(), sql: []const u8, params: anytype) void { _ = s; _ = sql; _ = params; } pub fn fetchone(s: *@This()) ?[][]const u8 { if (s.pos >= s.results.items.len) return null; const row = s.results.items[s.pos]; s.pos += 1; return row; } pub fn fetchall(s: *@This()) [][]const u8 { return s.results.items; } pub fn fetchmany(s: *@This(), size: i64) [][]const u8 { const end = @min(s.pos + @as(usize, @intCast(size)), s.results.items.len); const slice = s.results.items[s.pos..end]; s.pos = end; return slice; } pub fn close(s: *@This()) void { _ = s; } pub fn __iter__(s: *@This()) *@This() { return s; } pub fn __next__(s: *@This()) ?[][]const u8 { return s.fetchone(); } }") },
    .{ "Row", h.c("struct { data: [][]const u8, keys: ?[][]const u8 = null, pub fn get(s: *@This(), idx: usize) ?[]const u8 { if (idx < s.data.len) return s.data[idx]; return null; } }{}") },
    .{ "Error", h.c("\"Error\"") }, .{ "DatabaseError", h.c("\"DatabaseError\"") },
    .{ "IntegrityError", h.c("\"IntegrityError\"") }, .{ "OperationalError", h.c("\"OperationalError\"") },
    .{ "ProgrammingError", h.c("\"ProgrammingError\"") },
    .{ "PARSE_DECLTYPES", h.I64(1) }, .{ "PARSE_COLNAMES", h.I64(2) },
    .{ "SQLITE_OK", h.I64(0) }, .{ "SQLITE_DENY", h.I64(1) }, .{ "SQLITE_IGNORE", h.I64(2) },
    .{ "version", h.c("\"3.0.0\"") }, .{ "sqlite_version", h.c("\"3.39.0\"") },
    .{ "register_adapter", h.c("{}") }, .{ "register_converter", h.c("{}") },
});

