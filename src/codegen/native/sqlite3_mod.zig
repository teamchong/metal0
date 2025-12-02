/// Python sqlite3 module - SQLite database interface
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "connect", genConnect }, .{ "Connection", genConnection }, .{ "Cursor", genCursor }, .{ "Row", genRow },
    .{ "Error", genErrStr }, .{ "DatabaseError", genDbError }, .{ "IntegrityError", genIntError },
    .{ "OperationalError", genOpError }, .{ "ProgrammingError", genProgError },
    .{ "PARSE_DECLTYPES", genI64_1 }, .{ "PARSE_COLNAMES", genI64_2 },
    .{ "SQLITE_OK", genI64_0 }, .{ "SQLITE_DENY", genI64_1 }, .{ "SQLITE_IGNORE", genI64_2 },
    .{ "version", genVersion }, .{ "sqlite_version", genSqliteVersion },
    .{ "register_adapter", genUnit }, .{ "register_converter", genUnit },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genI64_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0)"); }
fn genI64_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 1)"); }
fn genI64_2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 2)"); }
fn genVersion(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"3.0.0\""); }
fn genSqliteVersion(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"3.39.0\""); }
fn genErrStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"Error\""); }
fn genDbError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"DatabaseError\""); }
fn genIntError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"IntegrityError\""); }
fn genOpError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"OperationalError\""); }
fn genProgError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ProgrammingError\""); }

// Functions with logic
pub fn genConnect(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("try sqlite3.connect("); try self.genExpr(args[0]); try self.emit(")");
}

fn genConnection(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genConst(self, args, "const Connection = struct { database: []const u8, in_transaction: bool = false, pub fn cursor(s: *@This()) Cursor { return Cursor{ .conn = s }; } pub fn execute(s: *@This(), sql: []const u8) Cursor { var c = s.cursor(); c.execute(sql); return c; } pub fn executemany(s: *@This(), sql: []const u8, params: anytype) void { _ = s; _ = sql; _ = params; } pub fn commit(s: *@This()) void { s.in_transaction = false; } pub fn rollback(s: *@This()) void { s.in_transaction = false; } pub fn close(s: *@This()) void { _ = s; } pub fn __enter__(s: *@This()) *@This() { return s; } pub fn __exit__(s: *@This(), _: anytype) void { s.close(); } }");
}

fn genCursor(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genConst(self, args, "const Cursor = struct { conn: *Connection, description: ?[][]const u8 = null, rowcount: i64 = -1, lastrowid: ?i64 = null, results: std.ArrayList([][]const u8) = .{}, pos: usize = 0, pub fn execute(s: *@This(), sql: []const u8) void { _ = s; _ = sql; } pub fn executemany(s: *@This(), sql: []const u8, params: anytype) void { _ = s; _ = sql; _ = params; } pub fn fetchone(s: *@This()) ?[][]const u8 { if (s.pos >= s.results.items.len) return null; const row = s.results.items[s.pos]; s.pos += 1; return row; } pub fn fetchall(s: *@This()) [][]const u8 { return s.results.items; } pub fn fetchmany(s: *@This(), size: i64) [][]const u8 { const end = @min(s.pos + @as(usize, @intCast(size)), s.results.items.len); const slice = s.results.items[s.pos..end]; s.pos = end; return slice; } pub fn close(s: *@This()) void { _ = s; } pub fn __iter__(s: *@This()) *@This() { return s; } pub fn __next__(s: *@This()) ?[][]const u8 { return s.fetchone(); } }");
}

fn genRow(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genConst(self, args, "struct { data: [][]const u8, keys: ?[][]const u8 = null, pub fn get(s: *@This(), idx: usize) ?[]const u8 { if (idx < s.data.len) return s.data[idx]; return null; } }{}");
}
