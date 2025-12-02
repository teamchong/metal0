/// Python logging module - Logging facility
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "debug", h.logLevel("DEBUG") }, .{ "info", h.logLevel("INFO") }, .{ "warning", h.logLevel("WARNING") },
    .{ "error", h.logLevel("ERROR") }, .{ "critical", h.logLevel("CRITICAL") }, .{ "exception", h.logLevel("ERROR") },
    .{ "log", h.wrap2("blk: { _ = ", "; const _m = ", "; std.debug.print(\"{s}\\n\", .{_m}); break :blk; }", "{}") },
    .{ "basicConfig", h.c("{}") },
    .{ "getLogger", h.c("struct { name: ?[]const u8 = null, level: i64 = 0, pub fn debug(s: *@This(), msg: []const u8) void { _ = s; std.debug.print(\"DEBUG: {s}\\n\", .{msg}); } pub fn info(s: *@This(), msg: []const u8) void { _ = s; std.debug.print(\"INFO: {s}\\n\", .{msg}); } pub fn warning(s: *@This(), msg: []const u8) void { _ = s; std.debug.print(\"WARNING: {s}\\n\", .{msg}); } pub fn @\"error\"(s: *@This(), msg: []const u8) void { _ = s; std.debug.print(\"ERROR: {s}\\n\", .{msg}); } pub fn critical(s: *@This(), msg: []const u8) void { _ = s; std.debug.print(\"CRITICAL: {s}\\n\", .{msg}); } pub fn setLevel(s: *@This(), lvl: i64) void { s.level = lvl; } pub fn addHandler(s: *@This(), h: anytype) void { _ = s; _ = h; } }{}") },
    .{ "Logger", h.c("struct { name: ?[]const u8 = null, level: i64 = 0, pub fn debug(s: *@This(), msg: []const u8) void { _ = s; std.debug.print(\"DEBUG: {s}\\n\", .{msg}); } pub fn info(s: *@This(), msg: []const u8) void { _ = s; std.debug.print(\"INFO: {s}\\n\", .{msg}); } pub fn warning(s: *@This(), msg: []const u8) void { _ = s; std.debug.print(\"WARNING: {s}\\n\", .{msg}); } pub fn @\"error\"(s: *@This(), msg: []const u8) void { _ = s; std.debug.print(\"ERROR: {s}\\n\", .{msg}); } pub fn critical(s: *@This(), msg: []const u8) void { _ = s; std.debug.print(\"CRITICAL: {s}\\n\", .{msg}); } pub fn setLevel(s: *@This(), lvl: i64) void { s.level = lvl; } pub fn addHandler(s: *@This(), h: anytype) void { _ = s; _ = h; } }{}") },
    .{ "Handler", h.c("struct { pub fn setFormatter(s: *@This(), f: anytype) void { _ = s; _ = f; } pub fn setLevel(s: *@This(), l: i64) void { _ = s; _ = l; } }{}") },
    .{ "StreamHandler", h.c("struct { pub fn setFormatter(s: *@This(), f: anytype) void { _ = s; _ = f; } pub fn setLevel(s: *@This(), l: i64) void { _ = s; _ = l; } }{}") },
    .{ "FileHandler", h.c("struct { pub fn setFormatter(s: *@This(), f: anytype) void { _ = s; _ = f; } pub fn setLevel(s: *@This(), l: i64) void { _ = s; _ = l; } }{}") },
    .{ "Formatter", h.c("struct { fmt: []const u8 = \"\" }{}") },
    .{ "DEBUG", h.I64(10) }, .{ "INFO", h.I64(20) }, .{ "WARNING", h.I64(30) },
    .{ "ERROR", h.I64(40) }, .{ "CRITICAL", h.I64(50) }, .{ "NOTSET", h.I64(0) },
});
