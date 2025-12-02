/// Python pprint module - Pretty-print data structures
const std = @import("std");
const h = @import("mod_helper.zig");

const pprint = h.debugPrint("", "{any}", "{}");
const pformat = h.bufPrint("{any}", "\"\"");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "pprint", pprint }, .{ "pformat", pformat }, .{ "pp", pprint },
    .{ "isreadable", h.c("true") }, .{ "isrecursive", h.c("false") }, .{ "saferepr", pformat },
    .{ "PrettyPrinter", h.c("struct { indent: i64 = 1, width: i64 = 80, depth: ?i64 = null, compact: bool = false, sort_dicts: bool = true, underscore_numbers: bool = false, pub fn pprint(s: @This(), object: anytype) void { _ = s; std.debug.print(\"{any}\\n\", .{object}); } pub fn pformat(s: @This(), object: anytype) []const u8 { _ = s; _ = object; return \"\"; } pub fn isreadable(s: @This(), object: anytype) bool { _ = s; _ = object; return true; } pub fn isrecursive(s: @This(), object: anytype) bool { _ = s; _ = object; return false; } pub fn format(s: @This(), object: anytype) []const u8 { _ = s; _ = object; return \"\"; } }{}") },
});
