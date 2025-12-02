/// Python _sqlite3 module - Internal SQLite3 support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "connect", genConnect }, .{ "connection", genConnection }, .{ "cursor", genCursor }, .{ "row", genRow },
    .{ "cursor_method", genCursor }, .{ "commit", genUnit }, .{ "rollback", genUnit }, .{ "close", genUnit },
    .{ "execute", genCursor }, .{ "executemany", genCursor }, .{ "executescript", genCursor },
    .{ "create_function", genUnit }, .{ "create_aggregate", genUnit }, .{ "create_collation", genUnit },
    .{ "set_authorizer", genUnit }, .{ "set_progress_handler", genUnit }, .{ "set_trace_callback", genUnit },
    .{ "enable_load_extension", genUnit }, .{ "load_extension", genUnit }, .{ "interrupt", genUnit }, .{ "backup", genUnit },
    .{ "iterdump", genIterdump }, .{ "fetchone", genNull }, .{ "fetchmany", genEmptyRows }, .{ "fetchall", genEmptyRows },
    .{ "setinputsizes", genUnit }, .{ "setoutputsize", genUnit },
    .{ "version", genVersion }, .{ "version_info", genVersionInfo },
    .{ "sqlite_version", genSqliteVersion }, .{ "sqlite_version_info", genSqliteVersionInfo },
    .{ "p_a_r_s_e__d_e_c_l_t_y_p_e_s", genPARSE_DECLTYPES }, .{ "p_a_r_s_e__c_o_l_n_a_m_e_s", genPARSE_COLNAMES },
    .{ "error", genError }, .{ "database_error", genDatabaseError }, .{ "integrity_error", genIntegrityError },
    .{ "programming_error", genProgrammingError }, .{ "operational_error", genOperationalError },
    .{ "not_supported_error", genNotSupportedError },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }
fn genRow(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genEmptyRows(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]@TypeOf(.{}){}"); }
fn genIterdump(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{}"); }

// Types
fn genConnection(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .database = \":memory:\", .isolation_level = \"\", .row_factory = null }"); }
fn genCursor(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .connection = null, .description = null, .rowcount = -1, .lastrowid = null, .arraysize = 1 }"); }

fn genConnect(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const db = "); try self.genExpr(args[0]);
        try self.emit("; _ = db; break :blk .{ .database = db, .isolation_level = \"\", .row_factory = null }; }");
    } else try self.emit(".{ .database = \":memory:\", .isolation_level = \"\", .row_factory = null }");
}

// Constants
fn genVersion(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"2.6.0\""); }
fn genVersionInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ @as(i32, 2), @as(i32, 6), @as(i32, 0) }"); }
fn genSqliteVersion(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"3.45.0\""); }
fn genSqliteVersionInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ @as(i32, 3), @as(i32, 45), @as(i32, 0) }"); }
fn genPARSE_DECLTYPES(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 1)"); }
fn genPARSE_COLNAMES(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 2)"); }

// Exceptions
fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.Error"); }
fn genDatabaseError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.DatabaseError"); }
fn genIntegrityError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.IntegrityError"); }
fn genProgrammingError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.ProgrammingError"); }
fn genOperationalError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.OperationalError"); }
fn genNotSupportedError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.NotSupportedError"); }
