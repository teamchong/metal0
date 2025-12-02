/// Python _sqlite3 module - Internal SQLite3 support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "connect", genConnect }, .{ "connection", genConst(".{ .database = \":memory:\", .isolation_level = \"\", .row_factory = null }") },
    .{ "cursor", genConst(".{ .connection = null, .description = null, .rowcount = -1, .lastrowid = null, .arraysize = 1 }") },
    .{ "row", genConst(".{}") }, .{ "cursor_method", genConst(".{ .connection = null, .description = null, .rowcount = -1, .lastrowid = null, .arraysize = 1 }") },
    .{ "commit", genConst("{}") }, .{ "rollback", genConst("{}") }, .{ "close", genConst("{}") },
    .{ "execute", genConst(".{ .connection = null, .description = null, .rowcount = -1, .lastrowid = null, .arraysize = 1 }") },
    .{ "executemany", genConst(".{ .connection = null, .description = null, .rowcount = -1, .lastrowid = null, .arraysize = 1 }") },
    .{ "executescript", genConst(".{ .connection = null, .description = null, .rowcount = -1, .lastrowid = null, .arraysize = 1 }") },
    .{ "create_function", genConst("{}") }, .{ "create_aggregate", genConst("{}") }, .{ "create_collation", genConst("{}") },
    .{ "set_authorizer", genConst("{}") }, .{ "set_progress_handler", genConst("{}") }, .{ "set_trace_callback", genConst("{}") },
    .{ "enable_load_extension", genConst("{}") }, .{ "load_extension", genConst("{}") }, .{ "interrupt", genConst("{}") }, .{ "backup", genConst("{}") },
    .{ "iterdump", genConst("&[_][]const u8{}") }, .{ "fetchone", genConst("null") }, .{ "fetchmany", genConst("&[_]@TypeOf(.{}){}") }, .{ "fetchall", genConst("&[_]@TypeOf(.{}){}") },
    .{ "setinputsizes", genConst("{}") }, .{ "setoutputsize", genConst("{}") },
    .{ "version", genConst("\"2.6.0\"") }, .{ "version_info", genConst(".{ @as(i32, 2), @as(i32, 6), @as(i32, 0) }") },
    .{ "sqlite_version", genConst("\"3.45.0\"") }, .{ "sqlite_version_info", genConst(".{ @as(i32, 3), @as(i32, 45), @as(i32, 0) }") },
    .{ "p_a_r_s_e__d_e_c_l_t_y_p_e_s", genConst("@as(i32, 1)") }, .{ "p_a_r_s_e__c_o_l_n_a_m_e_s", genConst("@as(i32, 2)") },
    .{ "error", genConst("error.Error") }, .{ "database_error", genConst("error.DatabaseError") }, .{ "integrity_error", genConst("error.IntegrityError") },
    .{ "programming_error", genConst("error.ProgrammingError") }, .{ "operational_error", genConst("error.OperationalError") },
    .{ "not_supported_error", genConst("error.NotSupportedError") },
});

fn genConnect(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const db = "); try self.genExpr(args[0]);
        try self.emit("; _ = db; break :blk .{ .database = db, .isolation_level = \"\", .row_factory = null }; }");
    } else try self.emit(".{ .database = \":memory:\", .isolation_level = \"\", .row_factory = null }");
}
