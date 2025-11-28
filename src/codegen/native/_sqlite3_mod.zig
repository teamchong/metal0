/// Python _sqlite3 module - Internal SQLite3 support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _sqlite3.connect(database, timeout=5.0, detect_types=0, isolation_level="", check_same_thread=True, factory=None, cached_statements=128, uri=False)
pub fn genConnect(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const db = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = db; break :blk .{ .database = db, .isolation_level = \"\", .row_factory = null }; }");
    } else {
        try self.emit(".{ .database = \":memory:\", .isolation_level = \"\", .row_factory = null }");
    }
}

/// Generate _sqlite3.Connection class
pub fn genConnection(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .database = \":memory:\", .isolation_level = \"\", .row_factory = null }");
}

/// Generate _sqlite3.Cursor class
pub fn genCursor(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .connection = null, .description = null, .rowcount = -1, .lastrowid = null, .arraysize = 1 }");
}

/// Generate _sqlite3.Row class
pub fn genRow(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate Connection.cursor(factory=Cursor)
pub fn genCursorMethod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .connection = null, .description = null, .rowcount = -1, .lastrowid = null, .arraysize = 1 }");
}

/// Generate Connection.commit()
pub fn genCommit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Connection.rollback()
pub fn genRollback(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Connection.close()
pub fn genClose(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Connection.execute(sql, parameters=())
pub fn genExecute(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .connection = null, .description = null, .rowcount = -1, .lastrowid = null, .arraysize = 1 }");
}

/// Generate Connection.executemany(sql, seq_of_parameters)
pub fn genExecutemany(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .connection = null, .description = null, .rowcount = -1, .lastrowid = null, .arraysize = 1 }");
}

/// Generate Connection.executescript(sql_script)
pub fn genExecutescript(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .connection = null, .description = null, .rowcount = -1, .lastrowid = null, .arraysize = 1 }");
}

/// Generate Connection.create_function(name, narg, func, *, deterministic=False)
pub fn genCreateFunction(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Connection.create_aggregate(name, narg, aggregate_class)
pub fn genCreateAggregate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Connection.create_collation(name, callable)
pub fn genCreateCollation(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Connection.set_authorizer(authorizer_callback)
pub fn genSetAuthorizer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Connection.set_progress_handler(handler, n)
pub fn genSetProgressHandler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Connection.set_trace_callback(trace_callback)
pub fn genSetTraceCallback(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Connection.enable_load_extension(enabled)
pub fn genEnableLoadExtension(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Connection.load_extension(path)
pub fn genLoadExtension(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Connection.interrupt()
pub fn genInterrupt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Connection.iterdump()
pub fn genIterdump(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{}");
}

/// Generate Connection.backup(target, *, pages=-1, progress=None, name=\"main\", sleep=0.250)
pub fn genBackup(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Cursor.fetchone()
pub fn genFetchone(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate Cursor.fetchmany(size=cursor.arraysize)
pub fn genFetchmany(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]@TypeOf(.{}){}");
}

/// Generate Cursor.fetchall()
pub fn genFetchall(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]@TypeOf(.{}){}");
}

/// Generate Cursor.setinputsizes(sizes)
pub fn genSetinputsizes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Cursor.setoutputsize(size, column=None)
pub fn genSetoutputsize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _sqlite3.version constant
pub fn genVersion(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"2.6.0\"");
}

/// Generate _sqlite3.version_info constant
pub fn genVersionInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(i32, 2), @as(i32, 6), @as(i32, 0) }");
}

/// Generate _sqlite3.sqlite_version constant
pub fn genSqliteVersion(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"3.45.0\"");
}

/// Generate _sqlite3.sqlite_version_info constant
pub fn genSqliteVersionInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(i32, 3), @as(i32, 45), @as(i32, 0) }");
}

/// Generate _sqlite3.PARSE_DECLTYPES constant
pub fn genPARSE_DECLTYPES(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

/// Generate _sqlite3.PARSE_COLNAMES constant
pub fn genPARSE_COLNAMES(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

/// Generate _sqlite3.Error exception
pub fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.Error");
}

/// Generate _sqlite3.DatabaseError exception
pub fn genDatabaseError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.DatabaseError");
}

/// Generate _sqlite3.IntegrityError exception
pub fn genIntegrityError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.IntegrityError");
}

/// Generate _sqlite3.ProgrammingError exception
pub fn genProgrammingError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.ProgrammingError");
}

/// Generate _sqlite3.OperationalError exception
pub fn genOperationalError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.OperationalError");
}

/// Generate _sqlite3.NotSupportedError exception
pub fn genNotSupportedError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.NotSupportedError");
}
