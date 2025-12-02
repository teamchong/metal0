/// Python _sqlite3 module - Internal SQLite3 support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "connect", genConnect }, .{ "connection", h.c(".{ .database = \":memory:\", .isolation_level = \"\", .row_factory = null }") },
    .{ "cursor", h.c(".{ .connection = null, .description = null, .rowcount = -1, .lastrowid = null, .arraysize = 1 }") },
    .{ "row", h.c(".{}") }, .{ "cursor_method", h.c(".{ .connection = null, .description = null, .rowcount = -1, .lastrowid = null, .arraysize = 1 }") },
    .{ "commit", h.c("{}") }, .{ "rollback", h.c("{}") }, .{ "close", h.c("{}") },
    .{ "execute", h.c(".{ .connection = null, .description = null, .rowcount = -1, .lastrowid = null, .arraysize = 1 }") },
    .{ "executemany", h.c(".{ .connection = null, .description = null, .rowcount = -1, .lastrowid = null, .arraysize = 1 }") },
    .{ "executescript", h.c(".{ .connection = null, .description = null, .rowcount = -1, .lastrowid = null, .arraysize = 1 }") },
    .{ "create_function", h.c("{}") }, .{ "create_aggregate", h.c("{}") }, .{ "create_collation", h.c("{}") },
    .{ "set_authorizer", h.c("{}") }, .{ "set_progress_handler", h.c("{}") }, .{ "set_trace_callback", h.c("{}") },
    .{ "enable_load_extension", h.c("{}") }, .{ "load_extension", h.c("{}") }, .{ "interrupt", h.c("{}") }, .{ "backup", h.c("{}") },
    .{ "iterdump", h.c("&[_][]const u8{}") }, .{ "fetchone", h.c("null") }, .{ "fetchmany", h.c("&[_]@TypeOf(.{}){}") }, .{ "fetchall", h.c("&[_]@TypeOf(.{}){}") },
    .{ "setinputsizes", h.c("{}") }, .{ "setoutputsize", h.c("{}") },
    .{ "version", h.c("\"2.6.0\"") }, .{ "version_info", h.c(".{ @as(i32, 2), @as(i32, 6), @as(i32, 0) }") },
    .{ "sqlite_version", h.c("\"3.45.0\"") }, .{ "sqlite_version_info", h.c(".{ @as(i32, 3), @as(i32, 45), @as(i32, 0) }") },
    .{ "p_a_r_s_e__d_e_c_l_t_y_p_e_s", h.I32(1) }, .{ "p_a_r_s_e__c_o_l_n_a_m_e_s", h.I32(2) },
    .{ "error", h.err("Error") }, .{ "database_error", h.err("DatabaseError") }, .{ "integrity_error", h.err("IntegrityError") },
    .{ "programming_error", h.err("ProgrammingError") }, .{ "operational_error", h.err("OperationalError") },
    .{ "not_supported_error", h.err("NotSupportedError") },
});

fn genConnect(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const db = "); try self.genExpr(args[0]);
        try self.emit("; _ = db; break :blk .{ .database = db, .isolation_level = \"\", .row_factory = null }; }");
    } else try self.emit(".{ .database = \":memory:\", .isolation_level = \"\", .row_factory = null }");
}
