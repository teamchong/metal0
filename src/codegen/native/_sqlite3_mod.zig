/// Python _sqlite3 module - Internal SQLite3 support (C accelerator)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "connect", genConnect },
    .{ "connection", genConnection },
    .{ "cursor", genCursor },
    .{ "row", genRow },
    .{ "cursor_method", genCursorMethod },
    .{ "commit", genCommit },
    .{ "rollback", genRollback },
    .{ "close", genClose },
    .{ "execute", genExecute },
    .{ "executemany", genExecutemany },
    .{ "executescript", genExecutescript },
    .{ "create_function", genCreateFunction },
    .{ "create_aggregate", genCreateAggregate },
    .{ "create_collation", genCreateCollation },
    .{ "set_authorizer", genSetAuthorizer },
    .{ "set_progress_handler", genSetProgressHandler },
    .{ "set_trace_callback", genSetTraceCallback },
    .{ "enable_load_extension", genEnableLoadExtension },
    .{ "load_extension", genLoadExtension },
    .{ "interrupt", genInterrupt },
    .{ "backup", genBackup },
    .{ "iterdump", genIterdump },
    .{ "fetchone", genFetchone },
    .{ "fetchmany", genFetchmany },
    .{ "fetchall", genFetchall },
    .{ "setinputsizes", genSetinputsizes },
    .{ "setoutputsize", genSetoutputsize },
    .{ "version", genVersion },
    .{ "version_info", genVersionInfo },
    .{ "sqlite_version", genSqliteVersion },
    .{ "sqlite_version_info", genSqliteVersionInfo },
    .{ "p_a_r_s_e__d_e_c_l_t_y_p_e_s", genParseDeclTypes },
    .{ "p_a_r_s_e__c_o_l_n_a_m_e_s", genParseColNames },
    .{ "error", genErrorType },
    .{ "database_error", genDatabaseError },
    .{ "integrity_error", genIntegrityError },
    .{ "programming_error", genProgrammingError },
    .{ "operational_error", genOperationalError },
    .{ "not_supported_error", genNotSupportedError },
});

fn genConnect(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const label = try self.emitInlineBlockStart("sql");
        try self.emit("const __v = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; break :{s} .{{ .database = __v, .isolation_level = \"\", .row_factory = null }}; ", .{label});
        try self.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .database = \":memory:\", .isolation_level = \"\", .row_factory = null }"), builder_mod.EmitConfig.forExpression());
    }
}

fn genConnection(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .database = \":memory:\", .isolation_level = \"\", .row_factory = null }"), builder_mod.EmitConfig.forExpression());
}

fn genCursor(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .connection = null, .description = null, .rowcount = -1, .lastrowid = null, .arraysize = 1 }"), builder_mod.EmitConfig.forExpression());
}

fn genRow(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genCursorMethod(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .connection = null, .description = null, .rowcount = -1, .lastrowid = null, .arraysize = 1 }"), builder_mod.EmitConfig.forExpression());
}

fn genCommit(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genRollback(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genClose(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genExecute(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .connection = null, .description = null, .rowcount = -1, .lastrowid = null, .arraysize = 1 }"), builder_mod.EmitConfig.forExpression());
}

fn genExecutemany(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .connection = null, .description = null, .rowcount = -1, .lastrowid = null, .arraysize = 1 }"), builder_mod.EmitConfig.forExpression());
}

fn genExecutescript(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .connection = null, .description = null, .rowcount = -1, .lastrowid = null, .arraysize = 1 }"), builder_mod.EmitConfig.forExpression());
}

fn genCreateFunction(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genCreateAggregate(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genCreateCollation(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genSetAuthorizer(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genSetProgressHandler(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genSetTraceCallback(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genEnableLoadExtension(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genLoadExtension(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genInterrupt(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genBackup(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genIterdump(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{}"), builder_mod.EmitConfig.forExpression());
}

fn genFetchone(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
}

fn genFetchmany(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]@TypeOf(.{}){}"), builder_mod.EmitConfig.forExpression());
}

fn genFetchall(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]@TypeOf(.{}){}"), builder_mod.EmitConfig.forExpression());
}

fn genSetinputsizes(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genSetoutputsize(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genVersion(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("2.6.0"), builder_mod.EmitConfig.forExpression());
}

fn genVersionInfo(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ @as(i32, 2), @as(i32, 6), @as(i32, 0) }"), builder_mod.EmitConfig.forExpression());
}

fn genSqliteVersion(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("3.45.0"), builder_mod.EmitConfig.forExpression());
}

fn genSqliteVersionInfo(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ @as(i32, 3), @as(i32, 45), @as(i32, 0) }"), builder_mod.EmitConfig.forExpression());
}

fn genParseDeclTypes(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 1)"), builder_mod.EmitConfig.forExpression());
}

fn genParseColNames(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 2)"), builder_mod.EmitConfig.forExpression());
}

fn genErrorType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.Error"), builder_mod.EmitConfig.forExpression());
}

fn genDatabaseError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.DatabaseError"), builder_mod.EmitConfig.forExpression());
}

fn genIntegrityError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.IntegrityError"), builder_mod.EmitConfig.forExpression());
}

fn genProgrammingError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.ProgrammingError"), builder_mod.EmitConfig.forExpression());
}

fn genOperationalError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.OperationalError"), builder_mod.EmitConfig.forExpression());
}

fn genNotSupportedError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.NotSupportedError"), builder_mod.EmitConfig.forExpression());
}
