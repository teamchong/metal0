/// Python logging module - Logging facility
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "debug", genDebug },
    .{ "info", genInfo },
    .{ "warning", genWarning },
    .{ "error", genError },
    .{ "critical", genCritical },
    .{ "exception", genException },
    .{ "log", genLog },
    .{ "basicConfig", genBasicConfig },
    .{ "getLogger", genGetLogger },
    .{ "Logger", genLogger },
    .{ "Handler", genHandler },
    .{ "StreamHandler", genStreamHandler },
    .{ "FileHandler", genFileHandler },
    .{ "Formatter", genFormatter },
    .{ "DEBUG", genDEBUG },
    .{ "INFO", genINFO },
    .{ "WARNING", genWARNING },
    .{ "ERROR", genERROR },
    .{ "CRITICAL", genCRITICAL },
    .{ "NOTSET", genNOTSET },
});

/// Generate logging.debug(msg, *args) -> None
pub fn genDebug(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("logging_debug_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _msg = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("std.debug.print(\"DEBUG: {s}\\n\", .{_msg});\n");
    try self.emitIndent();
    try self.emit("break :logging_debug_blk;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate logging.info(msg, *args) -> None
pub fn genInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("logging_info_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _msg = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("std.debug.print(\"INFO: {s}\\n\", .{_msg});\n");
    try self.emitIndent();
    try self.emit("break :logging_info_blk;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate logging.warning(msg, *args) -> None
pub fn genWarning(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("logging_warning_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _msg = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("std.debug.print(\"WARNING: {s}\\n\", .{_msg});\n");
    try self.emitIndent();
    try self.emit("break :logging_warning_blk;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate logging.error(msg, *args) -> None
pub fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("logging_error_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _msg = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("std.debug.print(\"ERROR: {s}\\n\", .{_msg});\n");
    try self.emitIndent();
    try self.emit("break :logging_error_blk;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate logging.critical(msg, *args) -> None
pub fn genCritical(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("logging_critical_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _msg = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("std.debug.print(\"CRITICAL: {s}\\n\", .{_msg});\n");
    try self.emitIndent();
    try self.emit("break :logging_critical_blk;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate logging.exception(msg, *args) -> None
pub fn genException(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genError(self, args);
}

/// Generate logging.log(level, msg, *args) -> None
pub fn genLog(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("logging_log_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _level = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _msg = ");
    try self.genExpr(args[1]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("_ = _level;\n");
    try self.emitIndent();
    try self.emit("std.debug.print(\"{s}\\n\", .{_msg});\n");
    try self.emitIndent();
    try self.emit("break :logging_log_blk;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate logging.basicConfig(**kwargs) -> None
pub fn genBasicConfig(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate logging.getLogger(name=None) -> Logger
pub fn genGetLogger(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("name: ?[]const u8 = null,\n");
    try self.emitIndent();
    try self.emit("level: i64 = 0,\n");
    try self.emitIndent();
    try self.emit("pub fn debug(s: *@This(), msg: []const u8) void { _ = s; std.debug.print(\"DEBUG: {s}\\n\", .{msg}); }\n");
    try self.emitIndent();
    try self.emit("pub fn info(s: *@This(), msg: []const u8) void { _ = s; std.debug.print(\"INFO: {s}\\n\", .{msg}); }\n");
    try self.emitIndent();
    try self.emit("pub fn warning(s: *@This(), msg: []const u8) void { _ = s; std.debug.print(\"WARNING: {s}\\n\", .{msg}); }\n");
    try self.emitIndent();
    try self.emit("pub fn @\"error\"(s: *@This(), msg: []const u8) void { _ = s; std.debug.print(\"ERROR: {s}\\n\", .{msg}); }\n");
    try self.emitIndent();
    try self.emit("pub fn critical(s: *@This(), msg: []const u8) void { _ = s; std.debug.print(\"CRITICAL: {s}\\n\", .{msg}); }\n");
    try self.emitIndent();
    try self.emit("pub fn setLevel(s: *@This(), lvl: i64) void { s.level = lvl; }\n");
    try self.emitIndent();
    try self.emit("pub fn addHandler(s: *@This(), h: anytype) void { _ = s; _ = h; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate logging.Logger class
pub fn genLogger(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genGetLogger(self, args);
}

/// Generate logging.Handler class
pub fn genHandler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { pub fn setFormatter(__self: *@This(), f: anytype) void { _ = f; } pub fn setLevel(__self: *@This(), l: i64) void { _ = l; } }{}");
}

/// Generate logging.StreamHandler class
pub fn genStreamHandler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genHandler(self, args);
}

/// Generate logging.FileHandler class
pub fn genFileHandler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genHandler(self, args);
}

/// Generate logging.Formatter class
pub fn genFormatter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { fmt: []const u8 = \"\" }{}");
}

/// Level constants
pub fn genDEBUG(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 10)");
}

pub fn genINFO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 20)");
}

pub fn genWARNING(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 30)");
}

pub fn genERROR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 40)");
}

pub fn genCRITICAL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 50)");
}

pub fn genNOTSET(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}
