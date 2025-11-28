/// Python logging module - Logging facility
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

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
    try self.emit("const stderr = std.io.getStdErr().writer();\n");
    try self.emitIndent();
    try self.emit("stderr.print(\"DEBUG: {s}\\n\", .{_msg}) catch {};\n");
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
    try self.emit("const stderr = std.io.getStdErr().writer();\n");
    try self.emitIndent();
    try self.emit("stderr.print(\"INFO: {s}\\n\", .{_msg}) catch {};\n");
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
    try self.emit("const stderr = std.io.getStdErr().writer();\n");
    try self.emitIndent();
    try self.emit("stderr.print(\"WARNING: {s}\\n\", .{_msg}) catch {};\n");
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
    try self.emit("const stderr = std.io.getStdErr().writer();\n");
    try self.emitIndent();
    try self.emit("stderr.print(\"ERROR: {s}\\n\", .{_msg}) catch {};\n");
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
    try self.emit("const stderr = std.io.getStdErr().writer();\n");
    try self.emitIndent();
    try self.emit("stderr.print(\"CRITICAL: {s}\\n\", .{_msg}) catch {};\n");
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
    try self.emit("const stderr = std.io.getStdErr().writer();\n");
    try self.emitIndent();
    try self.emit("stderr.print(\"{s}\\n\", .{_msg}) catch {};\n");
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
    try self.emit("pub fn debug(self: *@This(), msg: []const u8) void { _ = self; const w = std.io.getStdErr().writer(); w.print(\"DEBUG: {s}\\n\", .{msg}) catch {}; }\n");
    try self.emitIndent();
    try self.emit("pub fn info(self: *@This(), msg: []const u8) void { _ = self; const w = std.io.getStdErr().writer(); w.print(\"INFO: {s}\\n\", .{msg}) catch {}; }\n");
    try self.emitIndent();
    try self.emit("pub fn warning(self: *@This(), msg: []const u8) void { _ = self; const w = std.io.getStdErr().writer(); w.print(\"WARNING: {s}\\n\", .{msg}) catch {}; }\n");
    try self.emitIndent();
    try self.emit("pub fn @\"error\"(self: *@This(), msg: []const u8) void { _ = self; const w = std.io.getStdErr().writer(); w.print(\"ERROR: {s}\\n\", .{msg}) catch {}; }\n");
    try self.emitIndent();
    try self.emit("pub fn critical(self: *@This(), msg: []const u8) void { _ = self; const w = std.io.getStdErr().writer(); w.print(\"CRITICAL: {s}\\n\", .{msg}) catch {}; }\n");
    try self.emitIndent();
    try self.emit("pub fn setLevel(self: *@This(), lvl: i64) void { self.level = lvl; }\n");
    try self.emitIndent();
    try self.emit("pub fn addHandler(self: *@This(), h: anytype) void { _ = self; _ = h; }\n");
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
    try self.emit("struct { pub fn setFormatter(self: *@This(), f: anytype) void { _ = self; _ = f; } pub fn setLevel(self: *@This(), l: i64) void { _ = self; _ = l; } }{}");
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
