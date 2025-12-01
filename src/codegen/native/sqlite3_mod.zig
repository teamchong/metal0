/// Python sqlite3 module - SQLite database interface
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "connect", genConnect },
    .{ "Connection", genConnection },
    .{ "Cursor", genCursor },
    .{ "Row", genRow },
    .{ "Error", genError },
    .{ "DatabaseError", genDatabaseError },
    .{ "IntegrityError", genIntegrityError },
    .{ "OperationalError", genOperationalError },
    .{ "ProgrammingError", genProgrammingError },
    .{ "PARSE_DECLTYPES", genPARSE_DECLTYPES },
    .{ "PARSE_COLNAMES", genPARSE_COLNAMES },
    .{ "SQLITE_OK", genSQLITE_OK },
    .{ "SQLITE_DENY", genSQLITE_DENY },
    .{ "SQLITE_IGNORE", genSQLITE_IGNORE },
    .{ "version", genVersion },
    .{ "sqlite_version", genSqliteVersion },
    .{ "register_adapter", genRegisterAdapter },
    .{ "register_converter", genRegisterConverter },
});

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
    try self.emit("pub fn cursor(__self: *@This()) Cursor {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("return Cursor{ .conn = __self };\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn execute(__self: *@This(), sql: []const u8) Cursor {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var c = __self.cursor();\n");
    try self.emitIndent();
    try self.emit("c.execute(sql);\n");
    try self.emitIndent();
    try self.emit("return c;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn executemany(__self: *@This(), sql: []const u8, params: anytype) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = __self; _ = sql; _ = params;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn commit(__self: *@This()) void { __self.in_transaction = false; }\n");
    try self.emitIndent();
    try self.emit("pub fn rollback(__self: *@This()) void { __self.in_transaction = false; }\n");
    try self.emitIndent();
    try self.emit("pub fn close(__self: *@This()) void { _ = __self; }\n");
    try self.emitIndent();
    try self.emit("pub fn __enter__(__self: *@This()) *@This() { return __self; }\n");
    try self.emitIndent();
    try self.emit("pub fn __exit__(__self: *@This(), _: anytype) void { __self.close(); }\n");
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
    try self.emit("results: std.ArrayList([][]const u8) = .{},\n");
    try self.emitIndent();
    try self.emit("pos: usize = 0,\n");
    try self.emitIndent();
    try self.emit("pub fn execute(__self: *@This(), sql: []const u8) void { _ = __self; _ = sql; }\n");
    try self.emitIndent();
    try self.emit("pub fn executemany(__self: *@This(), sql: []const u8, params: anytype) void { _ = __self; _ = sql; _ = params; }\n");
    try self.emitIndent();
    try self.emit("pub fn fetchone(__self: *@This()) ?[][]const u8 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (__self.pos >= __self.results.items.len) return null;\n");
    try self.emitIndent();
    try self.emit("const row = __self.results.items[__self.pos];\n");
    try self.emitIndent();
    try self.emit("__self.pos += 1;\n");
    try self.emitIndent();
    try self.emit("return row;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn fetchall(__self: *@This()) [][]const u8 { return __self.results.items; }\n");
    try self.emitIndent();
    try self.emit("pub fn fetchmany(__self: *@This(), size: i64) [][]const u8 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const end = @min(__self.pos + @as(usize, @intCast(size)), __self.results.items.len);\n");
    try self.emitIndent();
    try self.emit("const slice = __self.results.items[__self.pos..end];\n");
    try self.emitIndent();
    try self.emit("__self.pos = end;\n");
    try self.emitIndent();
    try self.emit("return slice;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn close(__self: *@This()) void { _ = __self; }\n");
    try self.emitIndent();
    try self.emit("pub fn __iter__(__self: *@This()) *@This() { return __self; }\n");
    try self.emitIndent();
    try self.emit("pub fn __next__(__self: *@This()) ?[][]const u8 { return __self.fetchone(); }\n");
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
    try self.emit("pub fn get(__self: *@This(), idx: usize) ?[]const u8 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (idx < __self.data.len) return __self.data[idx];\n");
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
