/// Python sqlite3 module - SQLite database interface
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate sqlite3.connect(database) -> Connection
/// Uses the C interop sqlite3 module
pub fn genConnect(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    // Call the C interop sqlite3.connect function
    try self.emit("try sqlite3.connect(");
    try self.genExpr(args[0]);
    try self.emit(")");
}

/// Generate Connection struct
pub fn genConnection(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("const Connection = struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("database: []const u8,\n");
    try self.emitIndent();
    try self.emit("in_transaction: bool = false,\n");
    try self.emitIndent();
    try self.emit("pub fn cursor(self: *@This()) Cursor {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("return Cursor{ .conn = self };\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn execute(self: *@This(), sql: []const u8) Cursor {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var c = self.cursor();\n");
    try self.emitIndent();
    try self.emit("c.execute(sql);\n");
    try self.emitIndent();
    try self.emit("return c;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn executemany(self: *@This(), sql: []const u8, params: anytype) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = self; _ = sql; _ = params;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn commit(self: *@This()) void { self.in_transaction = false; }\n");
    try self.emitIndent();
    try self.emit("pub fn rollback(self: *@This()) void { self.in_transaction = false; }\n");
    try self.emitIndent();
    try self.emit("pub fn close(self: *@This()) void { _ = self; }\n");
    try self.emitIndent();
    try self.emit("pub fn __enter__(self: *@This()) *@This() { return self; }\n");
    try self.emitIndent();
    try self.emit("pub fn __exit__(self: *@This(), _: anytype) void { self.close(); }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate Cursor struct
pub fn genCursor(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("const Cursor = struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("conn: *Connection,\n");
    try self.emitIndent();
    try self.emit("description: ?[][]const u8 = null,\n");
    try self.emitIndent();
    try self.emit("rowcount: i64 = -1,\n");
    try self.emitIndent();
    try self.emit("lastrowid: ?i64 = null,\n");
    try self.emitIndent();
    try self.emit("results: std.ArrayList([][]const u8) = std.ArrayList([][]const u8).init(allocator),\n");
    try self.emitIndent();
    try self.emit("pos: usize = 0,\n");
    try self.emitIndent();
    try self.emit("pub fn execute(self: *@This(), sql: []const u8) void { _ = self; _ = sql; }\n");
    try self.emitIndent();
    try self.emit("pub fn executemany(self: *@This(), sql: []const u8, params: anytype) void { _ = self; _ = sql; _ = params; }\n");
    try self.emitIndent();
    try self.emit("pub fn fetchone(self: *@This()) ?[][]const u8 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (self.pos >= self.results.items.len) return null;\n");
    try self.emitIndent();
    try self.emit("const row = self.results.items[self.pos];\n");
    try self.emitIndent();
    try self.emit("self.pos += 1;\n");
    try self.emitIndent();
    try self.emit("return row;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn fetchall(self: *@This()) [][]const u8 { return self.results.items; }\n");
    try self.emitIndent();
    try self.emit("pub fn fetchmany(self: *@This(), size: i64) [][]const u8 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const end = @min(self.pos + @as(usize, @intCast(size)), self.results.items.len);\n");
    try self.emitIndent();
    try self.emit("const slice = self.results.items[self.pos..end];\n");
    try self.emitIndent();
    try self.emit("self.pos = end;\n");
    try self.emitIndent();
    try self.emit("return slice;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn close(self: *@This()) void { _ = self; }\n");
    try self.emitIndent();
    try self.emit("pub fn __iter__(self: *@This()) *@This() { return self; }\n");
    try self.emitIndent();
    try self.emit("pub fn __next__(self: *@This()) ?[][]const u8 { return self.fetchone(); }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate Row struct
pub fn genRow(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("data: [][]const u8,\n");
    try self.emitIndent();
    try self.emit("keys: ?[][]const u8 = null,\n");
    try self.emitIndent();
    try self.emit("pub fn get(self: *@This(), idx: usize) ?[]const u8 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (idx < self.data.len) return self.data[idx];\n");
    try self.emitIndent();
    try self.emit("return null;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

// Exception types
pub fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"Error\"");
}

pub fn genDatabaseError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"DatabaseError\"");
}

pub fn genIntegrityError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"IntegrityError\"");
}

pub fn genOperationalError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"OperationalError\"");
}

pub fn genProgrammingError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"ProgrammingError\"");
}

// Constants
pub fn genPARSE_DECLTYPES(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 1)");
}

pub fn genPARSE_COLNAMES(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 2)");
}

pub fn genSQLITE_OK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

pub fn genSQLITE_DENY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 1)");
}

pub fn genSQLITE_IGNORE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 2)");
}

/// Generate sqlite3.version constant
pub fn genVersion(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"3.0.0\"");
}

/// Generate sqlite3.sqlite_version constant
pub fn genSqliteVersion(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"3.39.0\"");
}

/// Generate sqlite3.register_adapter(type, callable)
pub fn genRegisterAdapter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate sqlite3.register_converter(typename, callable)
pub fn genRegisterConverter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}
