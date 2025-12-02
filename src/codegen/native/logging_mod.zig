/// Python logging module - Logging facility
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "debug", genDebug }, .{ "info", genInfo }, .{ "warning", genWarning },
    .{ "error", genError }, .{ "critical", genCritical }, .{ "exception", genError },
    .{ "log", genLog }, .{ "basicConfig", genConst("{}") }, .{ "getLogger", genConst("struct { name: ?[]const u8 = null, level: i64 = 0, pub fn debug(s: *@This(), msg: []const u8) void { _ = s; std.debug.print(\"DEBUG: {s}\\n\", .{msg}); } pub fn info(s: *@This(), msg: []const u8) void { _ = s; std.debug.print(\"INFO: {s}\\n\", .{msg}); } pub fn warning(s: *@This(), msg: []const u8) void { _ = s; std.debug.print(\"WARNING: {s}\\n\", .{msg}); } pub fn @\"error\"(s: *@This(), msg: []const u8) void { _ = s; std.debug.print(\"ERROR: {s}\\n\", .{msg}); } pub fn critical(s: *@This(), msg: []const u8) void { _ = s; std.debug.print(\"CRITICAL: {s}\\n\", .{msg}); } pub fn setLevel(s: *@This(), lvl: i64) void { s.level = lvl; } pub fn addHandler(s: *@This(), h: anytype) void { _ = s; _ = h; } }{}") }, .{ "Logger", genConst("struct { name: ?[]const u8 = null, level: i64 = 0, pub fn debug(s: *@This(), msg: []const u8) void { _ = s; std.debug.print(\"DEBUG: {s}\\n\", .{msg}); } pub fn info(s: *@This(), msg: []const u8) void { _ = s; std.debug.print(\"INFO: {s}\\n\", .{msg}); } pub fn warning(s: *@This(), msg: []const u8) void { _ = s; std.debug.print(\"WARNING: {s}\\n\", .{msg}); } pub fn @\"error\"(s: *@This(), msg: []const u8) void { _ = s; std.debug.print(\"ERROR: {s}\\n\", .{msg}); } pub fn critical(s: *@This(), msg: []const u8) void { _ = s; std.debug.print(\"CRITICAL: {s}\\n\", .{msg}); } pub fn setLevel(s: *@This(), lvl: i64) void { s.level = lvl; } pub fn addHandler(s: *@This(), h: anytype) void { _ = s; _ = h; } }{}") },
    .{ "Handler", genConst("struct { pub fn setFormatter(s: *@This(), f: anytype) void { _ = s; _ = f; } pub fn setLevel(s: *@This(), l: i64) void { _ = s; _ = l; } }{}") }, .{ "StreamHandler", genConst("struct { pub fn setFormatter(s: *@This(), f: anytype) void { _ = s; _ = f; } pub fn setLevel(s: *@This(), l: i64) void { _ = s; _ = l; } }{}") }, .{ "FileHandler", genConst("struct { pub fn setFormatter(s: *@This(), f: anytype) void { _ = s; _ = f; } pub fn setLevel(s: *@This(), l: i64) void { _ = s; _ = l; } }{}") },
    .{ "Formatter", genConst("struct { fmt: []const u8 = \"\" }{}") },
    .{ "DEBUG", genConst("@as(i64, 10)") }, .{ "INFO", genConst("@as(i64, 20)") }, .{ "WARNING", genConst("@as(i64, 30)") },
    .{ "ERROR", genConst("@as(i64, 40)") }, .{ "CRITICAL", genConst("@as(i64, 50)") }, .{ "NOTSET", genConst("@as(i64, 0)") },
});

fn genLogLevel(self: *NativeCodegen, args: []ast.Node, level: []const u8) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const _m = "); try self.genExpr(args[0]);
    try self.emit("; std.debug.print(\""); try self.emit(level); try self.emit(": {s}\\n\", .{_m}); break :blk; }");
}

pub fn genDebug(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genLogLevel(self, args, "DEBUG"); }
pub fn genInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genLogLevel(self, args, "INFO"); }
pub fn genWarning(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genLogLevel(self, args, "WARNING"); }
pub fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genLogLevel(self, args, "ERROR"); }
pub fn genCritical(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genLogLevel(self, args, "CRITICAL"); }

fn genLog(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("blk: { _ = "); try self.genExpr(args[0]);
    try self.emit("; const _m = "); try self.genExpr(args[1]);
    try self.emit("; std.debug.print(\"{s}\\n\", .{_m}); break :blk; }");
}
