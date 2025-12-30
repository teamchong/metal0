/// Python _sqlite3 module - Internal SQLite3 support (C accelerator)
/// MIGRATED TO ZIGBUILDER
/// DRY: Uses h.c(), h.str(), h.I32(), h.err() factories for constants
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    // Connection/cursor operations (genConnect kept as function - has arg handling)
    .{ "connect", genConnect },
    .{ "connection", h.c(".{ .database = \":memory:\", .isolation_level = \"\", .row_factory = null }") },
    .{ "cursor", h.c(".{ .connection = null, .description = null, .rowcount = -1, .lastrowid = null, .arraysize = 1 }") },
    .{ "row", h.c(".{}") },
    .{ "cursor_method", h.c(".{ .connection = null, .description = null, .rowcount = -1, .lastrowid = null, .arraysize = 1 }") },
    // Transaction operations
    .{ "commit", h.c("{}") },
    .{ "rollback", h.c("{}") },
    .{ "close", h.c("{}") },
    // Execute operations
    .{ "execute", h.c(".{ .connection = null, .description = null, .rowcount = -1, .lastrowid = null, .arraysize = 1 }") },
    .{ "executemany", h.c(".{ .connection = null, .description = null, .rowcount = -1, .lastrowid = null, .arraysize = 1 }") },
    .{ "executescript", h.c(".{ .connection = null, .description = null, .rowcount = -1, .lastrowid = null, .arraysize = 1 }") },
    // Extension/callback registration
    .{ "create_function", h.c("{}") },
    .{ "create_aggregate", h.c("{}") },
    .{ "create_collation", h.c("{}") },
    .{ "set_authorizer", h.c("{}") },
    .{ "set_progress_handler", h.c("{}") },
    .{ "set_trace_callback", h.c("{}") },
    .{ "enable_load_extension", h.c("{}") },
    .{ "load_extension", h.c("{}") },
    .{ "interrupt", h.c("{}") },
    .{ "backup", h.c("{}") },
    .{ "iterdump", h.c("&[_][]const u8{}") },
    // Fetch operations
    .{ "fetchone", h.c("null") },
    .{ "fetchmany", h.c("&[_]@TypeOf(.{}){}") },
    .{ "fetchall", h.c("&[_]@TypeOf(.{}){}") },
    .{ "setinputsizes", h.c("{}") },
    .{ "setoutputsize", h.c("{}") },
    // Version info
    .{ "version", h.c("\"2.6.0\"") },
    .{ "version_info", h.c(".{ @as(i32, 2), @as(i32, 6), @as(i32, 0) }") },
    .{ "sqlite_version", h.c("\"3.45.0\"") },
    .{ "sqlite_version_info", h.c(".{ @as(i32, 3), @as(i32, 45), @as(i32, 0) }") },
    // Parse constants
    .{ "p_a_r_s_e__d_e_c_l_t_y_p_e_s", h.I32(1) },
    .{ "p_a_r_s_e__c_o_l_n_a_m_e_s", h.I32(2) },
    // Error types
    .{ "error", h.err("Error") },
    .{ "database_error", h.err("DatabaseError") },
    .{ "integrity_error", h.err("IntegrityError") },
    .{ "programming_error", h.err("ProgrammingError") },
    .{ "operational_error", h.err("OperationalError") },
    .{ "not_supported_error", h.err("NotSupportedError") },
});

// genConnect kept as function - has special arg handling with withInlineBlock
fn genConnect(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.withInlineBlock("sql", args, struct {
            fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try c.emit("const __v = ");
                try c.genExpr(a[0]);
                try c.emitFmt("; break :{s} .{{ .database = __v, .isolation_level = \"\", .row_factory = null }}", .{label});
            }
        }.emit);
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .database = \":memory:\", .isolation_level = \"\", .row_factory = null }"), builder_mod.EmitConfig.forExpression());
    }
}
